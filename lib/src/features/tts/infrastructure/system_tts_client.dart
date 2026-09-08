import 'package:flutter_tts/flutter_tts.dart';

/// One voice reported by the platform's TTS engine.
class SystemTtsVoice {
  const SystemTtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is SystemTtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Parses the raw, platform-shaped value returned by `FlutterTts.getVoices`
/// (a `List` of `Map`s with at least `name`/`locale` keys on Android/iOS/
/// Windows/macOS) into [SystemTtsVoice]s, skipping anything malformed.
List<SystemTtsVoice> parseSystemTtsVoices(dynamic raw) {
  if (raw is! List) return const <SystemTtsVoice>[];
  final List<SystemTtsVoice> voices = <SystemTtsVoice>[];
  for (final dynamic entry in raw) {
    if (entry is! Map) continue;
    final Object? name = entry['name'];
    final Object? locale = entry['locale'];
    if (name is String && locale is String) {
      voices.add(SystemTtsVoice(name: name, locale: locale));
    }
  }
  return voices;
}

/// Mockable wrapper around [FlutterTts] used by the system-voice read-aloud
/// path, so tests can substitute a fake without a platform channel.
abstract class SystemTtsClient {
  Future<List<SystemTtsVoice>> getVoices();
  Future<void> setVoice(SystemTtsVoice voice);

  /// Best-effort rate, 0.0-1.0 per flutter_tts's own normalization.
  Future<void> setSpeechRate(double rate);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  void onComplete(void Function() callback);
  void onError(void Function(Object error) callback);
  Future<void> dispose();
}

class FlutterTtsClient implements SystemTtsClient {
  FlutterTtsClient() : _tts = FlutterTts() {
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts;

  @override
  Future<List<SystemTtsVoice>> getVoices() async =>
      parseSystemTtsVoices(await _tts.getVoices);

  @override
  Future<void> setVoice(SystemTtsVoice voice) => _tts.setVoice(<String, String>{
    'name': voice.name,
    'locale': voice.locale,
  });

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> pause() => _tts.pause();

  @override
  void onComplete(void Function() callback) => _tts.setCompletionHandler(callback);

  @override
  void onError(void Function(Object error) callback) =>
      _tts.setErrorHandler((dynamic error) => callback(error as Object));

  @override
  Future<void> dispose() => _tts.stop();
}
