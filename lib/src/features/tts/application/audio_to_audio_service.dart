import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/clarix_logger.dart';
import '../../ai/ai.dart';
import 'kitten_tts_service.dart';

enum AudioInteractionState {
  idle,
  listening,
  transcribing,
  thinking,
  speaking,
  error,
}

class AudioToAudioService extends ChangeNotifier {
  AudioToAudioService({
    required KittenTtsService ttsService,
    String? sttBaseUrl,
  })  : _ttsService = ttsService,
        _sttBaseUrl = sttBaseUrl ?? 'http://127.0.0.1:8880';

  final KittenTtsService _ttsService;
  String _sttBaseUrl;
  AudioInteractionState _state = AudioInteractionState.idle;
  String _lastUserTranscript = '';
  String _lastAiResponse = '';
  String? _lastError;
  Process? _recorderProcess;
  File? _recordedAudioFile;

  AudioInteractionState get state => _state;
  String get lastUserTranscript => _lastUserTranscript;
  String get lastAiResponse => _lastAiResponse;
  String? get lastError => _lastError;
  bool get isActive => _state != AudioInteractionState.idle && _state != AudioInteractionState.error;

  void updateSttBaseUrl(String url) {
    _sttBaseUrl = url.replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  /// Starts recording microphone audio
  Future<void> startListening() async {
    await stop();

    _state = AudioInteractionState.listening;
    _lastError = null;
    _lastUserTranscript = '';
    _lastAiResponse = '';
    notifyListeners();

    try {
      final tempDir = await getTemporaryDirectory();
      _recordedAudioFile = File('${tempDir.path}${Platform.pathSeparator}mic_input_${DateTime.now().millisecondsSinceEpoch}.wav');

      if (Platform.isWindows) {
        // Record audio via Windows PowerShell / SOX / ffmpeg if installed, or record buffer
        _recorderProcess = await Process.start('powershell', [
          '-c',
          '''
          Add-Type -TypeDefinition @"
          using System;
          using System.Runtime.InteropServices;
          public class WinMic {
              [DllImport("winmm.dll", EntryPoint = "mciSendStringA")]
              public static extern int mciSendString(string command, string buffer, int bufferSize, IntPtr hwndCallback);
          }
"@
          [WinMic]::mciSendString("open new type waveaudio alias grabber", \$null, 0, 0)
          [WinMic]::mciSendString("record grabber", \$null, 0, 0)
          Start-Sleep -Seconds 10
          [WinMic]::mciSendString("save grabber \\"${_recordedAudioFile!.path.replaceAll('\\', '/')}\\"", \$null, 0, 0)
          [WinMic]::mciSendString("close grabber", \$null, 0, 0)
          ''',
        ]);
      }
    } catch (e) {
      clarixLog.w('Failed to start mic recorder: $e');
      _setState(AudioInteractionState.error, error: 'Could not access microphone: $e');
    }
  }

  /// Stops recording, transcribes audio, queries AI notifier, and speaks back response
  Future<void> stopAndProcess(AiNotifier aiNotifier) async {
    if (_state != AudioInteractionState.listening) return;

    if (_recorderProcess != null) {
      _recorderProcess!.kill();
      _recorderProcess = null;
    }

    _state = AudioInteractionState.transcribing;
    notifyListeners();

    try {
      final text = await _transcribeRecordedAudio();
      if (text == null || text.trim().isEmpty) {
        _setState(AudioInteractionState.error, error: 'No spoken text detected.');
        return;
      }

      _lastUserTranscript = text;
      // Submit transcript to AI Notifier & wait for AI response
      await aiNotifier.sendPrompt(
        text,
        const AiDocumentContext(
          tabId: 'voice',
          documentId: 'voice',
          title: 'Voice Interaction',
          filePath: 'voice',
          editorRevision: 0,
        ),
      );
      final aiState = aiNotifier.state.value;

      final messages = aiState?.chat.messages ?? [];
      final reply = messages.isEmpty
          ? 'I processed your voice request.'
          : (messages.lastWhere((m) => m.role == 'assistant', orElse: () => messages.last).text);
      _lastAiResponse = reply;

      _state = AudioInteractionState.speaking;
      notifyListeners();

      // Speak back the AI response via KittenTTS
      await _ttsService.speak(reply);

      _setState(AudioInteractionState.idle);
    } catch (e, stack) {
      clarixLog.e('Audio-to-Audio loop error: $e\n$stack');
      _setState(AudioInteractionState.error, error: e.toString());
    } finally {
      _cleanUpTempAudio();
    }
  }

  Future<String?> _transcribeRecordedAudio() async {
    if (_recordedAudioFile == null || !_recordedAudioFile!.existsSync()) {
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final endpoints = [
      '$_sttBaseUrl/v1/audio/transcriptions',
      '$_sttBaseUrl/api/stt',
    ];

    for (final endpoint in endpoints) {
      try {
        final request = await client.postUrl(Uri.parse(endpoint));
        final boundary = '----WebKitFormBoundary${DateTime.now().millisecondsSinceEpoch}';
        request.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});

        final audioBytes = await _recordedAudioFile!.readAsBytes();
        final body = BytesBuilder();

        body.add(utf8.encode('--$boundary\r\n'));
        body.add(utf8.encode('Content-Disposition: form-data; name="file"; filename="mic.wav"\r\n'));
        body.add(utf8.encode('Content-Type: audio/wav\r\n\r\n'));
        body.add(audioBytes);
        body.add(utf8.encode('\r\n--$boundary\r\n'));
        body.add(utf8.encode('Content-Disposition: form-data; name="model"\r\n\r\nwhisper-1\r\n'));
        body.add(utf8.encode('--$boundary--\r\n'));

        request.add(body.takeBytes());
        final response = await request.close();

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final jsonMap = jsonDecode(responseBody) as Map<String, dynamic>;
          return jsonMap['text'] as String?;
        }
      } catch (e) {
        clarixLog.w('STT endpoint $endpoint failed: $e');
      }
    }

    client.close();
    return null;
  }

  Future<void> stop() async {
    if (_recorderProcess != null) {
      _recorderProcess!.kill();
      _recorderProcess = null;
    }
    await _ttsService.stop();
    _cleanUpTempAudio();
    _setState(AudioInteractionState.idle);
  }

  void _cleanUpTempAudio() {
    if (_recordedAudioFile != null && _recordedAudioFile!.existsSync()) {
      try {
        _recordedAudioFile!.deleteSync();
      } catch (_) {}
      _recordedAudioFile = null;
    }
  }

  void _setState(AudioInteractionState newState, {String? error}) {
    _state = newState;
    _lastError = error;
    notifyListeners();
  }
}
