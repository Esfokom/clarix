import 'pdf_text_types.dart';

abstract class PdfEditFailure implements Exception {
  const PdfEditFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';

  List<Object?> get equalityFields => <Object?>[code, message];

  @override
  bool operator ==(Object other) =>
      other is PdfEditFailure &&
      runtimeType == other.runtimeType &&
      _sameFailureList(other.equalityFields, equalityFields);

  @override
  int get hashCode => Object.hashAll(<Object?>[runtimeType, ...equalityFields]);
}

final class PdfReadOnlyTextBlockFailure extends PdfEditFailure {
  PdfReadOnlyTextBlockFailure({required this.locator, required this.reason})
    : super(
        'read_only_text_block',
        'This text block is read-only: ${reason.name}.',
      );

  final PdfTextBlockLocator locator;
  final PdfReadOnlyReason reason;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
    reason,
  ];
}

final class PdfUnsupportedTextOperationFailure extends PdfEditFailure {
  PdfUnsupportedTextOperationFailure({
    required this.locator,
    required this.capability,
  }) : super(
         'unsupported_text_operation',
         'This text block does not support ${capability.name}.',
       );

  final PdfTextBlockLocator locator;
  final PdfTextCapability capability;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
    capability,
  ];
}

final class PdfRevisionConflictFailure extends PdfEditFailure {
  const PdfRevisionConflictFailure({
    required this.expected,
    required this.actual,
  }) : super(
         'revision_conflict',
         'Expected revision $expected but found $actual.',
       );

  final String expected;
  final String actual;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    expected,
    actual,
  ];
}

final class PdfStaleLocatorFailure extends PdfEditFailure {
  const PdfStaleLocatorFailure(this.locator)
    : super(
        'stale_locator',
        'The text block no longer matches the source PDF.',
      );

  final PdfTextBlockLocator locator;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
  ];
}

final class PdfAmbiguousLocatorFailure extends PdfEditFailure {
  const PdfAmbiguousLocatorFailure(this.locator, this.candidateCount)
    : super(
        'ambiguous_locator',
        'The text block matches $candidateCount PDF objects.',
      );

  final PdfTextBlockLocator locator;
  final int candidateCount;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
    candidateCount,
  ];
}

final class PdfInvalidTextRangeFailure extends PdfEditFailure {
  const PdfInvalidTextRangeFailure({
    required this.range,
    required this.textLength,
  }) : super(
         'invalid_text_range',
         'The UTF-16 range is outside the text block.',
       );

  final PdfTextRange range;
  final int textLength;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    range,
    textLength,
  ];
}

final class PdfTextMismatchFailure extends PdfEditFailure {
  const PdfTextMismatchFailure({required this.locator, required this.expected})
    : super(
        'text_mismatch',
        'The text block no longer contains the expected text.',
      );

  final PdfTextBlockLocator locator;
  final String expected;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
    expected,
  ];
}

final class PdfTextOverflowFailure extends PdfEditFailure {
  const PdfTextOverflowFailure({required this.locator})
    : super('text_overflow', 'Text does not fit its box.');

  final PdfTextBlockLocator locator;

  @override
  List<Object?> get equalityFields => <Object?>[
    ...super.equalityFields,
    locator,
  ];
}

final class PdfNativeEditingUnavailableFailure extends PdfEditFailure {
  const PdfNativeEditingUnavailableFailure()
    : super(
        'native_editing_unavailable',
        'Native PDF text editing is unavailable.',
      );
}

final class PdfFontUnavailableFailure extends PdfEditFailure {
  const PdfFontUnavailableFailure(String message)
    : super('font_unavailable', message);
}

final class PdfExternalRevisionFailure extends PdfEditFailure {
  const PdfExternalRevisionFailure({
    required this.expected,
    required this.actual,
  }) : super('external_revision', 'The PDF changed outside Clarix.');

  final String expected;
  final String actual;
}

final class PdfValidationFailure extends PdfEditFailure {
  const PdfValidationFailure(String message)
    : super('pdf_validation_failed', message);
}

final class PdfAtomicReplacementFailure extends PdfEditFailure {
  const PdfAtomicReplacementFailure(String message)
    : super('pdf_replacement_failed', message);
}

bool _sameFailureList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
