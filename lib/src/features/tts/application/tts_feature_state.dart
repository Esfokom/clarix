import '../domain/tts_models.dart';
import '../infrastructure/system_tts_client.dart';

class TtsFeatureState {
  const TtsFeatureState({
    required this.installState,
    required this.defaultVoiceSid,
    required this.defaultSpeed,
    required this.playback,
    required this.activeEngine,
    this.activeModelId,
    this.systemVoice,
    this.availableSystemVoices = const <SystemTtsVoice>[],
    this.errorMessage,
  });

  factory TtsFeatureState.initial() => const TtsFeatureState(
    installState: <String, TtsModelInstallState>{},
    defaultVoiceSid: 0,
    defaultSpeed: 1,
    playback: TtsPlaybackState(),
    activeEngine: TtsEngineKind.kittenSherpa,
  );

  final Map<String, TtsModelInstallState> installState;
  final int defaultVoiceSid;
  final double defaultSpeed;
  final TtsPlaybackState playback;

  /// Which engine is currently selected in Settings.
  final TtsEngineKind activeEngine;

  /// Which [TtsModelCatalog] spec is active, when [activeEngine] is one of
  /// the sherpa-onnx engines. Null when no sherpa spec has been chosen yet
  /// (falls back to [TtsModelCatalog.defaultModel]) or when using system TTS.
  final String? activeModelId;

  /// The chosen OS voice, when [activeEngine] is [TtsEngineKind.system].
  final SystemTtsVoice? systemVoice;

  /// Voices reported by the platform's TTS engine, loaded once on startup.
  final List<SystemTtsVoice> availableSystemVoices;

  final String? errorMessage;

  TtsFeatureState copyWith({
    Map<String, TtsModelInstallState>? installState,
    int? defaultVoiceSid,
    double? defaultSpeed,
    TtsPlaybackState? playback,
    TtsEngineKind? activeEngine,
    String? activeModelId,
    bool clearActiveModelId = false,
    SystemTtsVoice? systemVoice,
    bool clearSystemVoice = false,
    List<SystemTtsVoice>? availableSystemVoices,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsFeatureState(
    installState: installState ?? this.installState,
    defaultVoiceSid: defaultVoiceSid ?? this.defaultVoiceSid,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    playback: playback ?? this.playback,
    activeEngine: activeEngine ?? this.activeEngine,
    activeModelId: clearActiveModelId ? null : (activeModelId ?? this.activeModelId),
    systemVoice: clearSystemVoice ? null : (systemVoice ?? this.systemVoice),
    availableSystemVoices: availableSystemVoices ?? this.availableSystemVoices,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}
