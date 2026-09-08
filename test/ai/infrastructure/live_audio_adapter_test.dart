import 'dart:typed_data';

import 'package:clarix/src/features/ai/infrastructure/live_audio_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stopping the adapter stops capture and clears queued output', () async {
    final _FakeLiveAudioAdapter audio = _FakeLiveAudioAdapter();

    await audio.startCapture();
    await audio.enqueueOutputPcm24(Uint8List.fromList(<int>[1, 2]));
    await audio.stop();

    expect(audio.captureActive, isFalse);
    expect(audio.queuedOutput, isEmpty);
  });
}

class _FakeLiveAudioAdapter implements LiveAudioAdapter {
  bool captureActive = false;
  final List<Uint8List> queuedOutput = <Uint8List>[];

  @override
  Stream<Uint8List> get inputPcm16 => const Stream<Uint8List>.empty();

  @override
  Stream<double> get inputLevel => const Stream<double>.empty();

  @override
  Future<void> dispose() => stop();

  @override
  Future<void> enqueueOutputPcm24(Uint8List bytes) async {
    queuedOutput.add(bytes);
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> startCapture({String? deviceId}) async {
    captureActive = true;
  }

  @override
  Future<void> stop() async {
    captureActive = false;
    queuedOutput.clear();
  }

  @override
  Future<void> stopOutput() async => queuedOutput.clear();
}
