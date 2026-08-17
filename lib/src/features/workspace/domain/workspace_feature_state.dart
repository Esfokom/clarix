import '../../../core/models.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';

enum PdfRecoveryAction { reload, saveCopy, selectBlock, rediscover }

final class PdfFailurePresentation {
  PdfFailurePresentation({
    required this.message,
    required List<PdfRecoveryAction> actions,
    this.locator,
  }) : actions = List<PdfRecoveryAction>.unmodifiable(actions);

  final String message;
  final List<PdfRecoveryAction> actions;
  final PdfTextBlockLocator? locator;
}

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
    this.pdfFailure,
    this.pdfSaveInProgress = false,
  });

  final WorkspaceSession session;
  final AiWorkspaceState aiState;
  final Map<String, List<OutlineNodeState>> outlines;
  final Map<String, DocumentMetadata> documentMetadata;
  final bool composerExpanded;
  final String? bannerMessage;
  final List<AiProviderProfile> providerProfiles;
  final Set<String> dirtyDocumentIds;
  final PdfFailurePresentation? pdfFailure;
  final bool pdfSaveInProgress;

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
    PdfFailurePresentation? pdfFailure,
    bool clearPdfFailure = false,
    bool? pdfSaveInProgress,
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
      pdfFailure: clearPdfFailure ? null : pdfFailure ?? this.pdfFailure,
      pdfSaveInProgress: pdfSaveInProgress ?? this.pdfSaveInProgress,
    );
  }
}
