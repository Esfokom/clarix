import 'dart:io';

import 'package:clarix/src/features/ai/infrastructure/record_voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('records a WAV file for Groq transcription', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'clarix-recording-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final _FakeRecordAudioEngine engine = _FakeRecordAudioEngine();
    final RecordVoiceRecorder recorder = RecordVoiceRecorder(
      engine: engine,
      temporaryDirectory: () async => directory,
    );

    await recorder.start();

    expect(engine.config?.encoder, AudioEncoder.wav);
    expect(engine.path, endsWith('.wav'));
  });
}

class _FakeRecordAudioEngine implements RecordAudioEngine {
  RecordConfig? config;
  String? path;

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<double> onAmplitudeChanged(Duration interval) =>
      Stream<double>.empty();

  @override
  Future<void> start(RecordConfig value, {required String path}) async {
    config = value;
    this.path = path;
  }

  @override
  Future<String?> stop() async => path;
}
