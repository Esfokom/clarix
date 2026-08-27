import '../../../core/editing/editor_bridge_types.dart';

/// A physical text replacement issued by the semantic editor layer.
///
/// All operations in a [LivePdfiumEditPlan] must target one page so they can
/// be resolved, applied, and regenerated against one live `FPDF_PAGE` handle.
class LivePdfiumTextReplacement {
  const LivePdfiumTextReplacement({
    required this.locator,
    required this.replacement,
  });

  final EditorPhysicalLocator locator;
  final String replacement;
}

/// The currently supported, all-or-nothing physical PDFium edit transaction.
class LivePdfiumEditPlan {
  LivePdfiumEditPlan({required List<LivePdfiumTextReplacement> replacements})
    : replacements = List.unmodifiable(replacements) {
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
  }

  final List<LivePdfiumTextReplacement> replacements;

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
