import 'ai_models.dart';
import 'ai_provider.dart';
import 'local_model_profile.dart';

class AiFeatureState {
  const AiFeatureState({
    required this.chat,
    required this.providerProfiles,
    this.localModels = const <LocalModelProfile>[],
  });

  factory AiFeatureState.initial() => AiFeatureState(
    chat: AiWorkspaceState.initial(),
    providerProfiles: const <AiProviderProfile>[],
  );

  final AiWorkspaceState chat;
  final List<AiProviderProfile> providerProfiles;
  final List<LocalModelProfile> localModels;

  AiFeatureState copyWith({
    AiWorkspaceState? chat,
    List<AiProviderProfile>? providerProfiles,
    List<LocalModelProfile>? localModels,
  }) => AiFeatureState(
    chat: chat ?? this.chat,
    providerProfiles: providerProfiles ?? this.providerProfiles,
    localModels: localModels ?? this.localModels,
  );
}
