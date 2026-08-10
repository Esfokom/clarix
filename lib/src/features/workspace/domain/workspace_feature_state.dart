import '../../../core/models.dart';
import 'ai_provider.dart';

class OutlineNodeState {
  const OutlineNodeState({
    required this.title,
    required this.pageNumber,
    required this.children,
  });

  final String title;
  final int? pageNumber;
  final List<OutlineNodeState> children;
}

class WorkspaceFeatureState {
  const WorkspaceFeatureState({
    required this.session,
    required this.aiState,
    required this.outlines,
    required this.documentMetadata,
    required this.composerExpanded,
    required this.bannerMessage,
    this.providerProfiles = const <AiProviderProfile>[],
    this.dirtyDocumentIds = const <String>{},
  });

  final WorkspaceSession session;
  final AiWorkspaceState aiState;
  final Map<String, List<OutlineNodeState>> outlines;
  final Map<String, DocumentMetadata> documentMetadata;
  final bool composerExpanded;
  final String? bannerMessage;
  final List<AiProviderProfile> providerProfiles;
  final Set<String> dirtyDocumentIds;

  WorkspaceFeatureState copyWith({
    WorkspaceSession? session,
    AiWorkspaceState? aiState,
    Map<String, List<OutlineNodeState>>? outlines,
    Map<String, DocumentMetadata>? documentMetadata,
    bool? composerExpanded,
    String? bannerMessage,
    bool clearBannerMessage = false,
    List<AiProviderProfile>? providerProfiles,
    Set<String>? dirtyDocumentIds,
  }) {
    return WorkspaceFeatureState(
      session: session ?? this.session,
      aiState: aiState ?? this.aiState,
      outlines: outlines ?? this.outlines,
      documentMetadata: documentMetadata ?? this.documentMetadata,
      composerExpanded: composerExpanded ?? this.composerExpanded,
      bannerMessage: clearBannerMessage
          ? null
          : bannerMessage ?? this.bannerMessage,
      providerProfiles: providerProfiles ?? this.providerProfiles,
      dirtyDocumentIds: dirtyDocumentIds ?? this.dirtyDocumentIds,
    );
  }
}
