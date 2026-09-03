import 'package:clarix/src/features/ai/application/voice_input_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records, transcribes, and supplies the completed transcript', () async {
    final _FakeVoiceRecorder recorder = _FakeVoiceRecorder();
    String? appended;
    final VoiceInputController controller = VoiceInputController(
      recorder: recorder,
      transcribe: (String path) async {
        expect(path, 'voice.m4a');
        return 'A spoken question';
      },
      onTranscript: (String transcript) => appended = transcript,
    );

    await controller.toggle();
    expect(controller.status, VoiceInputStatus.recording);
    expect(recorder.started, isTrue);

    await controller.toggle();
    expect(controller.status, VoiceInputStatus.idle);
    expect(appended, 'A spoken question');
  });

  test('returns to idle with an error when transcription fails', () async {
    final VoiceInputController controller = VoiceInputController(
      recorder: _FakeVoiceRecorder(),
      transcribe: (String _) async => throw StateError('Network unavailable'),
      onTranscript: (_) {},
    );

    await controller.toggle();
    await controller.toggle();

    expect(controller.status, VoiceInputStatus.idle);
    expect(controller.errorMessage, 'Network unavailable');
  });

  test('does not send a silent recording to the transcription API', () async {
    bool transcriptionCalled = false;
    final VoiceInputController controller = VoiceInputController(
      recorder: _FakeVoiceRecorder(hasRecordedSpeech: false),
      transcribe: (String _) async {
        transcriptionCalled = true;
        return 'Unexpected transcript';
      },
      onTranscript: (_) {},
    );

    await controller.toggle();
    await controller.toggle();

    expect(transcriptionCalled, isFalse);
    expect(controller.errorMessage, 'No speech was detected. Try again.');
  });

  test(
    'exposes available microphones and selects the requested device',
    () async {
      final _FakeVoiceRecorder recorder = _FakeVoiceRecorder();
      final VoiceInputController controller = VoiceInputController(
        recorder: recorder,
        transcribe: (_) async => '',
        onTranscript: (_) {},
      );

      expect(await controller.listInputDevices(), const <VoiceInputDevice>[
        VoiceInputDevice(id: 'usb-mic', label: 'USB Microphone'),
      ]);

      await controller.selectInputDevice('usb-mic');

      expect(recorder.selectedDeviceId, 'usb-mic');
    },
  );
}

class _FakeVoiceRecorder implements VoiceRecorder {
  _FakeVoiceRecorder({this.hasRecordedSpeech = true});

  bool started = false;
  final bool hasRecordedSpeech;
  String? selectedDeviceId;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<String?> stop() async => 'voice.m4a';

  @override
  Future<bool> didRecordSpeech() async => hasRecordedSpeech;

  @override
  Future<List<VoiceInputDevice>> listInputDevices() async =>
      const <VoiceInputDevice>[
        VoiceInputDevice(id: 'usb-mic', label: 'USB Microphone'),
      ];

  @override
  Future<void> selectInputDevice(String? id) async {
    selectedDeviceId = id;
  }

  @override
  Future<void> dispose() async {}
}
