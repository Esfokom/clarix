import 'pdf_text_types.dart';

sealed class PdfEditIntent {
  const PdfEditIntent({
    required this.documentId,
    required this.documentRevision,
  });

  final String documentId;
  final String documentRevision;

  List<PdfTextBlockLocator> get affectedLocators =>
      const <PdfTextBlockLocator>[];
  int get editCount => 0;
  bool get requiresFontSubstitution => false;
  double get deletionRatio => 0;
  Set<int> get affectedPages => Set<int>.unmodifiable(
    affectedLocators.map((PdfTextBlockLocator locator) => locator.pageNumber),
  );

  @override
  bool operator ==(Object other) =>
      other is PdfEditIntent &&
      runtimeType == other.runtimeType &&
      documentId == other.documentId &&
      documentRevision == other.documentRevision;

  @override
  int get hashCode => Object.hash(runtimeType, documentId, documentRevision);
}

final class SetPdfEditingModeIntent extends PdfEditIntent {
  const SetPdfEditingModeIntent({
    required super.documentId,
    required super.documentRevision,
    required this.mode,
  });

  final PdfEditingMode mode;

  @override
  bool operator ==(Object other) =>
      other is SetPdfEditingModeIntent && super == other && other.mode == mode;

  @override
  int get hashCode => Object.hash(super.hashCode, mode);
}

final class ReplacePdfTextIntent extends PdfEditIntent {
  const ReplacePdfTextIntent({
    required super.documentId,
    required super.documentRevision,
    required this.locator,
    required this.range,
    required this.replacement,
    this.caseMatching = true,
  });

  final PdfTextBlockLocator locator;
  final PdfTextRange range;
  final String replacement;
  final bool caseMatching;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  int get editCount => 1;

  @override
  bool operator ==(Object other) =>
      other is ReplacePdfTextIntent &&
      super == other &&
      other.locator == locator &&
      other.range == range &&
      other.replacement == replacement &&
      other.caseMatching == caseMatching;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, locator, range, replacement, caseMatching);
}

final class FormatPdfTextIntent extends PdfEditIntent {
  const FormatPdfTextIntent({
    required super.documentId,
    required super.documentRevision,
    required this.locator,
    required this.range,
    required this.patch,
  });

  final PdfTextBlockLocator locator;
  final PdfTextRange range;
  final PdfTextStylePatch patch;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  int get editCount => 1;

  @override
  bool operator ==(Object other) =>
      other is FormatPdfTextIntent &&
      super == other &&
      other.locator == locator &&
      other.range == range &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(super.hashCode, locator, range, patch);
}

final class MovePdfTextBlockIntent extends PdfEditIntent {
  const MovePdfTextBlockIntent({
    required super.documentId,
    required super.documentRevision,
    required this.locator,
    required this.bounds,
  });

  final PdfTextBlockLocator locator;
  final PdfBox bounds;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  int get editCount => 1;

  @override
  bool operator ==(Object other) =>
      other is MovePdfTextBlockIntent &&
      super == other &&
      other.locator == locator &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(super.hashCode, locator, bounds);
}

final class ResizePdfTextBlockIntent extends PdfEditIntent {
  const ResizePdfTextBlockIntent({
    required super.documentId,
    required super.documentRevision,
    required this.locator,
    required this.bounds,
  });

  final PdfTextBlockLocator locator;
  final PdfBox bounds;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  int get editCount => 1;

  @override
  bool operator ==(Object other) =>
      other is ResizePdfTextBlockIntent &&
      super == other &&
      other.locator == locator &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(super.hashCode, locator, bounds);
}

final class SetPdfCaseMatchingIntent extends PdfEditIntent {
  const SetPdfCaseMatchingIntent({
    required super.documentId,
    required super.documentRevision,
    required this.enabled,
  });

  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is SetPdfCaseMatchingIntent &&
      super == other &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(super.hashCode, enabled);
}

final class UndoPdfEditIntent extends PdfEditIntent {
  const UndoPdfEditIntent({
    required super.documentId,
    required super.documentRevision,
  });
}

final class RedoPdfEditIntent extends PdfEditIntent {
  const RedoPdfEditIntent({
    required super.documentId,
    required super.documentRevision,
  });
}

final class SavePdfEditsIntent extends PdfEditIntent {
  const SavePdfEditsIntent({
    required super.documentId,
    required super.documentRevision,
  });
}

final class PdfEditResult {
  PdfEditResult._({
    required this.revision,
    required List<String> commandIds,
    required List<PdfTextBlockLocator> affectedLocators,
    required this.failure,
    required List<String> warnings,
    required this.isDirty,
  }) : commandIds = List<String>.unmodifiable(commandIds),
       affectedLocators = List<PdfTextBlockLocator>.unmodifiable(
         affectedLocators,
       ),
       warnings = List<String>.unmodifiable(warnings);

  PdfEditResult.applied({
    required String revision,
    required List<String> commandIds,
    required List<PdfTextBlockLocator> affectedLocators,
    List<String> warnings = const <String>[],
    bool isDirty = true,
  }) : this._(
         revision: revision,
         commandIds: commandIds,
         affectedLocators: affectedLocators,
         failure: null,
         warnings: warnings,
         isDirty: isDirty,
       );

  PdfEditResult.failure(PdfEditFailure failure)
    : this._(
        revision: null,
        commandIds: const <String>[],
        affectedLocators: const <PdfTextBlockLocator>[],
        failure: failure,
        warnings: const <String>[],
        isDirty: true,
      );

  final String? revision;
  final List<String> commandIds;
  final List<PdfTextBlockLocator> affectedLocators;
  final PdfEditFailure? failure;
  final List<String> warnings;
  final bool isDirty;

  bool get isSuccess => failure == null;

  @override
  bool operator ==(Object other) =>
      other is PdfEditResult &&
      other.revision == revision &&
      _sameList(other.commandIds, commandIds) &&
      _sameList(other.affectedLocators, affectedLocators) &&
      other.failure == failure &&
      _sameList(other.warnings, warnings) &&
      other.isDirty == isDirty;

  @override
  int get hashCode => Object.hash(
    revision,
    Object.hashAll(commandIds),
    Object.hashAll(affectedLocators),
    failure,
    Object.hashAll(warnings),
    isDirty,
  );
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
