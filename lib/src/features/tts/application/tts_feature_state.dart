import '../domain/tts_models.dart';
import '../infrastructure/tts_model_catalog.dart';

class TtsFeatureState {
  const TtsFeatureState({
    required this.installState,
    required this.selectedModelId,
    required this.selectedSid,
    required this.speed,
    required this.playback,
    this.errorMessage,
  });

  factory TtsFeatureState.initial() => TtsFeatureState(
    installState: <String, TtsModelInstallState>{},
    selectedModelId: TtsModelCatalog.defaultModel.id,
    selectedSid: 0,
    speed: 1,
    playback: TtsPlaybackState(),
  );

  final Map<String, TtsModelInstallState> installState;
  final String selectedModelId;
  final int selectedSid;
  final double speed;
  final TtsPlaybackState playback;
  final String? errorMessage;

  TtsFeatureState copyWith({
    Map<String, TtsModelInstallState>? installState,
    String? selectedModelId,
    int? selectedSid,
    double? speed,
    TtsPlaybackState? playback,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsFeatureState(
    installState: installState ?? this.installState,
    selectedModelId: selectedModelId ?? this.selectedModelId,
    selectedSid: selectedSid ?? this.selectedSid,
    speed: speed ?? this.speed,
    playback: playback ?? this.playback,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}
