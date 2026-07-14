import '../../../core/models.dart';

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
    required this.downloads,
    required this.catalog,
    required this.outlines,
    required this.documentMetadata,
    required this.composerExpanded,
    required this.showModelCatalog,
    required this.bannerMessage,
  });

  final WorkspaceSession session;
  final AiWorkspaceState aiState;
  final Map<String, DownloadTaskState> downloads;
  final List<ModelCatalogItem> catalog;
  final Map<String, List<OutlineNodeState>> outlines;
  final Map<String, DocumentMetadata> documentMetadata;
  final bool composerExpanded;
  final bool showModelCatalog;
  final String? bannerMessage;

  WorkspaceFeatureState copyWith({
    WorkspaceSession? session,
    AiWorkspaceState? aiState,
    Map<String, DownloadTaskState>? downloads,
    List<ModelCatalogItem>? catalog,
    Map<String, List<OutlineNodeState>>? outlines,
    Map<String, DocumentMetadata>? documentMetadata,
    bool? composerExpanded,
    bool? showModelCatalog,
    String? bannerMessage,
    bool clearBannerMessage = false,
  }) {
    return WorkspaceFeatureState(
      session: session ?? this.session,
      aiState: aiState ?? this.aiState,
      downloads: downloads ?? this.downloads,
      catalog: catalog ?? this.catalog,
      outlines: outlines ?? this.outlines,
      documentMetadata: documentMetadata ?? this.documentMetadata,
      composerExpanded: composerExpanded ?? this.composerExpanded,
      showModelCatalog: showModelCatalog ?? this.showModelCatalog,
      bannerMessage:
          clearBannerMessage ? null : bannerMessage ?? this.bannerMessage,
    );
  }
}
