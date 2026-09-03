import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../application/voice_input_controller.dart';

abstract interface class RecordAudioEngine {
  Future<bool> hasPermission();
  Future<List<InputDevice>> listInputDevices();
  Future<void> start(RecordConfig config, {required String path});
  Future<String?> stop();
  Stream<double> onAmplitudeChanged(Duration interval);
  Future<void> dispose();
}

class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({
    RecordAudioEngine? engine,
    Future<Directory> Function()? temporaryDirectory,
  }) : _engine = engine ?? _RecordPackageAudioEngine(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final RecordAudioEngine _engine;
  final Future<Directory> Function() _temporaryDirectory;
  StreamSubscription<double>? _amplitudeSubscription;
  bool _didRecordSpeech = false;
  InputDevice? _selectedDevice;

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  @override
  Future<List<VoiceInputDevice>> listInputDevices() async =>
      (await _engine.listInputDevices())
          .map(
            (InputDevice device) =>
                VoiceInputDevice(id: device.id, label: device.label),
          )
          .toList(growable: false);

  @override
  Future<void> selectInputDevice(String? id) async {
    if (id == null) {
      _selectedDevice = null;
      return;
    }
    _selectedDevice = (await _engine.listInputDevices())
        .where((InputDevice device) => device.id == id)
        .firstOrNull;
    if (_selectedDevice == null) {
      throw StateError('The selected microphone is no longer available.');
    }
  }

  @override
  Future<void> start() async {
    final directory = await _temporaryDirectory();
    final String audioPath = path.join(
      directory.path,
      'clarix-voice-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await _engine.start(
      RecordConfig(encoder: AudioEncoder.wav, device: _selectedDevice),
      path: audioPath,
    );
    _didRecordSpeech = false;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _engine
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((double decibels) {
          if (decibels > -50) _didRecordSpeech = true;
        });
  }

  @override
  Future<String?> stop() async {
    final String? audioPath = await _engine.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    return audioPath;
  }

  @override
  Future<bool> didRecordSpeech() async => _didRecordSpeech;

  @override
  Future<void> dispose() async {
    await _amplitudeSubscription?.cancel();
    await _engine.dispose();
  }
}

class _RecordPackageAudioEngine implements RecordAudioEngine {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<void> dispose() => _recorder.dispose();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<List<InputDevice>> listInputDevices() => _recorder.listInputDevices();

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Stream<double> onAmplitudeChanged(Duration interval) => _recorder
      .onAmplitudeChanged(interval)
      .map((Amplitude amplitude) => amplitude.current);

  @override
  Future<String?> stop() => _recorder.stop();
}
