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
  Set<int> get affectedPages => affectedLocators
      .map((PdfTextBlockLocator locator) => locator.pageNumber)
      .toSet();
}

final class SetPdfEditingModeIntent extends PdfEditIntent {
  const SetPdfEditingModeIntent({
    required super.documentId,
    required super.documentRevision,
    required this.mode,
  });

  final PdfEditingMode mode;
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
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  int get editCount => 1;
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
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  int get editCount => 1;
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
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  int get editCount => 1;
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
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  int get editCount => 1;
}

final class SetPdfCaseMatchingIntent extends PdfEditIntent {
  const SetPdfCaseMatchingIntent({
    required super.documentId,
    required super.documentRevision,
    required this.enabled,
  });

  final bool enabled;
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
}
