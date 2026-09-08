import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

abstract interface class LiveAudioAdapter {
  Future<bool> requestPermission();
  Stream<Uint8List> get inputPcm16;
  Stream<double> get inputLevel;
  Future<void> startCapture({String? deviceId});
  Future<void> enqueueOutputPcm24(Uint8List bytes);
  Future<void> stopOutput();
  Future<void> stop();
  Future<void> dispose();
}

class RecordSoloudLiveAudioAdapter implements LiveAudioAdapter {
  RecordSoloudLiveAudioAdapter({AudioRecorder? recorder, SoLoud? soloud})
    : _recorder = recorder ?? AudioRecorder(),
      _soloud = soloud ?? SoLoud.instance;

  final AudioRecorder _recorder;
  final SoLoud _soloud;
  final StreamController<Uint8List> _input =
      StreamController<Uint8List>.broadcast();
  final StreamController<double> _level = StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<Amplitude>? _levelSubscription;
  AudioSource? _output;
  SoundHandle? _outputHandle;
  bool _disposed = false;

  @override
  Stream<Uint8List> get inputPcm16 => _input.stream;
  @override
  Stream<double> get inputLevel => _level.stream;

  @override
  Future<bool> requestPermission() async =>
      (await Permission.microphone.request()).isGranted;

  @override
  Future<void> startCapture({String? deviceId}) async {
    if (_disposed) throw StateError('The audio adapter has been disposed.');
    await _inputSubscription?.cancel();
    await _levelSubscription?.cancel();
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        device: deviceId == null
            ? null
            : InputDevice(id: deviceId, label: deviceId),
      ),
    );
    _inputSubscription = stream.listen(_input.add, onError: _input.addError);
    _levelSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen(
          (Amplitude amplitude) =>
              _level.add(((amplitude.current + 60) / 60).clamp(0, 1)),
        );
  }

  @override
  Future<void> enqueueOutputPcm24(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    if (!_soloud.isInitialized) await _soloud.init();
    final source = _output ??= _soloud.setBufferStream(
      maxBufferSizeDuration: const Duration(milliseconds: 800),
      bufferingTimeNeeds: .03,
      sampleRate: 24000,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _soloud.addAudioDataStream(source, bytes);
    _outputHandle ??= _soloud.play(source);
  }

  @override
  Future<void> stopOutput() async {
    final handle = _outputHandle;
    if (handle != null) _soloud.stop(handle);
    final source = _output;
    if (source != null) await _soloud.disposeSource(source);
    _output = null;
    _outputHandle = null;
  }

  @override
  Future<void> stop() async {
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    await stopOutput();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _recorder.dispose();
    await _input.close();
    await _level.close();
  }
}
