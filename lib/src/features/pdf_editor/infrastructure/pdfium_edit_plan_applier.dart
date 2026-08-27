import '../../../core/editing/editor_bridge_types.dart';

/// A physical text replacement issued by the semantic editor layer.
///
/// All operations in a [LivePdfiumEditPlan] must target one page so they can
/// be resolved, applied, and regenerated against one live `FPDF_PAGE` handle.
class LivePdfiumTextReplacement {
  const LivePdfiumTextReplacement({
    required this.locator,
    required this.replacement,
    this.expectedText,
  });

  final EditorPhysicalLocator locator;
  final String replacement;

  /// Semantic text observed when the plan was prepared. Supplying it prevents
  /// a reused physical object index from receiving an unintended edit.
  final String? expectedText;
}

/// The currently supported, all-or-nothing physical PDFium edit transaction.
class LivePdfiumEditPlan {
  LivePdfiumEditPlan({
    required List<LivePdfiumTextReplacement> replacements,
    this.expectedRevision,
    this.revision,
  }) : replacements = List.unmodifiable(replacements) {
    if (replacements.isEmpty) {
      throw ArgumentError.value(
        replacements,
        'replacements',
        'must not be empty',
      );
    }
    final pageNumber = replacements.first.locator.pageNumber;
    if (replacements.any((item) => item.locator.pageNumber != pageNumber)) {
      throw ArgumentError.value(
        replacements,
        'replacements',
        'must target exactly one page',
      );
    }
    if (revision != null &&
        expectedRevision != null &&
        revision! <= expectedRevision!) {
      throw ArgumentError.value(
        revision,
        'revision',
        'must advance the expected revision',
      );
    }
  }

  final List<LivePdfiumTextReplacement> replacements;

  /// Semantic revision at which this plan was prepared. Omitted only by
  /// direct local callers that do not participate in the bridge protocol.
  final int? expectedRevision;

  /// Semantic revision acknowledged after this plan has been applied. Omitted
  /// only by direct local callers, which advance by one.
  final int? revision;

  int get pageNumber => replacements.first.locator.pageNumber;
}

/// Result returned only after the plan has been regenerated in the live PDF.
class LivePdfiumApplyResult {
  const LivePdfiumApplyResult({
    required this.revision,
    required this.invalidations,
  });

  final int revision;
  final List<EditorTileInvalidation> invalidations;
}
