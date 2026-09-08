import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/clarix_logger.dart';

enum KittenTtsState {
  idle,
  synthesizing,
  playing,
  paused,
  error,
}

class KittenTtsVoice {
  const KittenTtsVoice({
    required this.id,
    required this.name,
    this.gender = 'neutral',
    this.language = 'en-US',
  });

  final String id;
  final String name;
  final String gender;
  final String language;

  static const List<KittenTtsVoice> defaults = [
    KittenTtsVoice(id: 'kitten_female_1', name: 'Kitten Female (Clear)', gender: 'female'),
    KittenTtsVoice(id: 'kitten_male_1', name: 'Kitten Male (Warm)', gender: 'male'),
    KittenTtsVoice(id: 'kokoro_af_heart', name: 'Kokoro Heart (Soft)', gender: 'female'),
    KittenTtsVoice(id: 'kokoro_am_adam', name: 'Kokoro Adam (Deep)', gender: 'male'),
  ];
}

class KittenTtsService extends ChangeNotifier {
  KittenTtsService({
    String? baseUrl,
    String? defaultVoiceId,
  })  : _baseUrl = baseUrl ?? 'http://127.0.0.1:8880',
        _selectedVoiceId = defaultVoiceId ?? 'kitten_female_1';

  String _baseUrl;
  String _selectedVoiceId;
  KittenTtsState _state = KittenTtsState.idle;
  double _speed = 1.0;
  String? _lastError;
  Process? _activePlayerProcess;

  String get baseUrl => _baseUrl;
  String get selectedVoiceId => _selectedVoiceId;
  KittenTtsState get state => _state;
  double get speed => _speed;
  String? get lastError => _lastError;
  bool get isSpeaking => _state == KittenTtsState.playing || _state == KittenTtsState.synthesizing;

  void updateBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  void setVoice(String voiceId) {
    _selectedVoiceId = voiceId;
    notifyListeners();
  }

  void setSpeed(double speed) {
    _speed = speed.clamp(0.5, 2.0);
    notifyListeners();
  }

  /// Synthesizes text via KittenTTS server and plays back audio with fallback to Native System Speech.
  Future<void> speak(String text, {String? voiceId, double? speed}) async {
    if (text.trim().isEmpty) return;

    await stop();

    _state = KittenTtsState.synthesizing;
    _lastError = null;
    notifyListeners();

    final targetVoice = voiceId ?? _selectedVoiceId;
    final targetSpeed = speed ?? _speed;

    try {
      final audioFile = await _synthesizeText(text, targetVoice, targetSpeed);
      if (audioFile != null) {
        _state = KittenTtsState.playing;
        notifyListeners();
        await _playAudioFile(audioFile);
      } else {
        // Fallback to Native System Speech Synthesizer (SAPI on Windows)
        _state = KittenTtsState.playing;
        notifyListeners();
        await _speakWithNativeTts(text, targetSpeed);
      }

      if (_state == KittenTtsState.playing) {
        _setState(KittenTtsState.idle);
      }
    } catch (e, stack) {
      clarixLog.e('KittenTTS speak error: $e\n$stack');
      _setState(KittenTtsState.error, error: e.toString());
    }
  }

  Future<void> _speakWithNativeTts(String text, double speed) async {
    final cleanText = _cleanTextForHumanSpeech(text);
    if (cleanText.isEmpty) return;

    try {
      if (Platform.isWindows) {
        final base64Text = base64Encode(utf8.encode(cleanText));
        final sapiRate = ((speed - 1.0) * 5).round().clamp(-10, 10);

        final psScript =
            '\$b=[Convert]::FromBase64String("$base64Text");'
            '\$t=[Text.Encoding]::UTF8.GetString(\$b);'
            'Add-Type -AssemblyName System.Speech;'
            '\$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;'
            '\$v=\$s.GetInstalledVoices() | Where-Object { \$_.Enabled -and \$_.VoiceInfo.Culture.Name -like "en*" } | Select-Object -First 1;'
            'if (\$v) { \$s.SelectVoice(\$v.VoiceInfo.Name); };'
            '\$s.Rate=$sapiRate;'
            '\$s.Speak(\$t);';

        final process = await Process.start('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          psScript,
        ]);
        _activePlayerProcess = process;
        await process.exitCode;
        _activePlayerProcess = null;
      } else if (Platform.isMacOS) {
        final rate = (speed * 175).round();
        final process = await Process.start('say', ['-r', '$rate', cleanText]);
        _activePlayerProcess = process;
        await process.exitCode;
        _activePlayerProcess = null;
      } else if (Platform.isLinux) {
        final rate = (speed * 100).round();
        final process = await Process.start('spd-say', ['-r', '$rate', cleanText]);
        _activePlayerProcess = process;
        await process.exitCode;
        _activePlayerProcess = null;
      }
    } catch (e) {
      clarixLog.w('Native TTS playback warning: $e');
    }
  }

  String _cleanTextForHumanSpeech(String input) {
    var t = input;
    // Strip URLs
    t = t.replaceAll(RegExp(r'https?://\S+'), '');
    // Strip markdown headings
    t = t.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    // Strip bullet points and list markers (•, -, *, 1.)
    t = t.replaceAll(RegExp(r'^[\•\-\*\+]\s*', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\d+\.\s*', multiLine: true), '');
    // Strip bold/italic markdown symbols (*, _, ~)
    t = t.replaceAll(RegExp(r'[\*\_\~]+'), '');
    // Strip page citations like (page 3) or [1]
    t = t.replaceAll(RegExp(r'\(pages?\s*\d+(?:–\d+)?\)|\[\d+\]', caseSensitive: false), '');
    // Replace mathematical symbols with natural words
    t = t.replaceAll('&', ' and ')
         .replaceAll('@', ' at ')
         .replaceAll('%', ' percent ')
         .replaceAll('=', ' equals ');
    // Normalize newlines into natural sentence breaks
    t = t.replaceAll(RegExp(r'\n+'), '. ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  Future<File?> _synthesizeText(String text, String voice, double speed) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final endpoints = [
      '$_baseUrl/v1/audio/speech',
      '$_baseUrl/tts',
      '$_baseUrl/api/tts',
    ];

    for (final endpoint in endpoints) {
      try {
        final request = await client.postUrl(Uri.parse(endpoint));
        request.headers.contentType = ContentType.json;

        final body = jsonEncode({
          'input': text,
          'text': text,
          'model': 'kitten-tts',
          'voice': voice,
          'speed': speed,
          'response_format': 'wav',
        });

        request.write(body);
        final response = await request.close();

        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}${Platform.pathSeparator}kitten_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
          final sink = tempFile.openWrite();

          await response.pipe(sink);
          return tempFile;
        }
      } catch (e) {
        clarixLog.w('KittenTTS endpoint $endpoint failed: $e');
      }
    }

    client.close();
    return null;
  }

  Future<void> _playAudioFile(File file) async {
    try {
      if (Platform.isWindows) {
        // Powershell SoundPlayer for Windows WAV playback
        final process = await Process.start('powershell', [
          '-c',
          '(New-Object System.Media.SoundPlayer "${file.path.replaceAll('\\', '/')}").PlaySync();',
        ]);
        _activePlayerProcess = process;
        await process.exitCode;
        _activePlayerProcess = null;
      }
    } catch (e) {
      clarixLog.w('Audio playback warning: $e');
    } finally {
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    if (_activePlayerProcess != null) {
      _activePlayerProcess!.kill();
      _activePlayerProcess = null;
    }
    _setState(KittenTtsState.idle);
  }

  void _setState(KittenTtsState newState, {String? error}) {
    _state = newState;
    _lastError = error;
    notifyListeners();
  }
}
