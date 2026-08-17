import 'ai_models.dart';
import 'ai_provider.dart';

class AiFeatureState {
  const AiFeatureState({required this.chat, required this.providerProfiles});

  factory AiFeatureState.initial() => AiFeatureState(
    chat: AiWorkspaceState.initial(),
    providerProfiles: const <AiProviderProfile>[],
  );

  final AiWorkspaceState chat;
  final List<AiProviderProfile> providerProfiles;

  AiFeatureState copyWith({
    AiWorkspaceState? chat,
    List<AiProviderProfile>? providerProfiles,
  }) => AiFeatureState(
    chat: chat ?? this.chat,
    providerProfiles: providerProfiles ?? this.providerProfiles,
  );
}
