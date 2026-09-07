import '../domain/tts_models.dart';

class TtsFeatureState {
  const TtsFeatureState({
    required this.installState,
    required this.defaultVoiceSid,
    required this.defaultSpeed,
    required this.playback,
    this.errorMessage,
  });

  factory TtsFeatureState.initial() => const TtsFeatureState(
    installState: <String, TtsModelInstallState>{},
    defaultVoiceSid: 0,
    defaultSpeed: 1,
    playback: TtsPlaybackState(),
  );

  final Map<String, TtsModelInstallState> installState;
  final int defaultVoiceSid;
  final double defaultSpeed;
  final TtsPlaybackState playback;
  final String? errorMessage;

  TtsFeatureState copyWith({
    Map<String, TtsModelInstallState>? installState,
    int? defaultVoiceSid,
    double? defaultSpeed,
    TtsPlaybackState? playback,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsFeatureState(
    installState: installState ?? this.installState,
    defaultVoiceSid: defaultVoiceSid ?? this.defaultVoiceSid,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    playback: playback ?? this.playback,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}
