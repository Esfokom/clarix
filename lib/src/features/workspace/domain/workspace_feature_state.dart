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
    required this.outlines,
    required this.documentMetadata,
    required this.composerExpanded,
    required this.bannerMessage,
    this.dirtyDocumentIds = const <String>{},
    this.pdfSaveInProgress = false,
  });

  final WorkspaceSession session;
  final Map<String, List<OutlineNodeState>> outlines;
  final Map<String, DocumentMetadata> documentMetadata;
  final bool composerExpanded;
  final String? bannerMessage;
  final Set<String> dirtyDocumentIds;
  final bool pdfSaveInProgress;

  WorkspaceFeatureState copyWith({
    WorkspaceSession? session,
    Map<String, List<OutlineNodeState>>? outlines,
    Map<String, DocumentMetadata>? documentMetadata,
    bool? composerExpanded,
    String? bannerMessage,
    bool clearBannerMessage = false,
    Set<String>? dirtyDocumentIds,
    bool? pdfSaveInProgress,
  }) {
    return WorkspaceFeatureState(
      session: session ?? this.session,
      outlines: outlines ?? this.outlines,
      documentMetadata: documentMetadata ?? this.documentMetadata,
      composerExpanded: composerExpanded ?? this.composerExpanded,
      bannerMessage: clearBannerMessage
          ? null
          : bannerMessage ?? this.bannerMessage,
      dirtyDocumentIds: dirtyDocumentIds ?? this.dirtyDocumentIds,
      pdfSaveInProgress: pdfSaveInProgress ?? this.pdfSaveInProgress,
    );
  }
}
