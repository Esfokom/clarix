import 'dart:async';

import 'package:flutter/foundation.dart';

enum VoiceInputStatus { idle, recording, transcribing }

abstract interface class VoiceRecorder {
  Future<bool> hasPermission();
  Future<void> start();
  Future<String?> stop();
  Future<bool> didRecordSpeech();
  Future<void> dispose();
}

class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required VoiceRecorder recorder,
    required Future<String> Function(String audioPath) transcribe,
    required ValueChanged<String> onTranscript,
  }) : _recorder = recorder,
       _transcribe = transcribe,
       _onTranscript = onTranscript;

  final VoiceRecorder _recorder;
  final Future<String> Function(String audioPath) _transcribe;
  final ValueChanged<String> _onTranscript;

  VoiceInputStatus _status = VoiceInputStatus.idle;
  String? _errorMessage;

  VoiceInputStatus get status => _status;
  String? get errorMessage => _errorMessage;

  Future<void> toggle() async {
    switch (_status) {
      case VoiceInputStatus.idle:
        await _startRecording();
      case VoiceInputStatus.recording:
        await _stopAndTranscribe();
      case VoiceInputStatus.transcribing:
        return;
    }
  }

  Future<void> _startRecording() async {
    _errorMessage = null;
    try {
      if (!await _recorder.hasPermission()) {
        _errorMessage = 'Microphone permission was not granted.';
        notifyListeners();
        return;
      }
      await _recorder.start();
      _status = VoiceInputStatus.recording;
    } catch (_) {
      _errorMessage = 'Could not start recording. Check your microphone.';
    }
    notifyListeners();
  }

  Future<void> _stopAndTranscribe() async {
    _status = VoiceInputStatus.transcribing;
    _errorMessage = null;
    notifyListeners();
    try {
      final String? audioPath = await _recorder.stop();
      if (audioPath == null) {
        throw StateError('No audio was captured.');
      }
      if (!await _recorder.didRecordSpeech()) {
        throw StateError('No speech was detected. Try again.');
      }
      final String transcript = await _transcribe(audioPath);
      if (transcript.isNotEmpty) _onTranscript(transcript);
    } catch (error) {
      _errorMessage = _errorDescription(error);
    } finally {
      _status = VoiceInputStatus.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    super.dispose();
  }

  String _errorDescription(Object error) => switch (error) {
    StateError(:final message) => message.toString(),
    _ => error.toString(),
  };
}
