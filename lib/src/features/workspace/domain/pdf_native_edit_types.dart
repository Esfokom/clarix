import 'pdf_text_types.dart';

final class PdfNativeBlockState {
  PdfNativeBlockState({
    required this.blockId,
    required this.editRevision,
    required this.block,
  }) {
    if (blockId.isEmpty) {
      throw ArgumentError.value(blockId, 'blockId', 'Must not be empty.');
    }
    RangeError.checkNotNegative(editRevision, 'editRevision');
  }

  final String blockId;
  final int editRevision;
  final PdfTextBlock block;
}

final class PdfNativeCharacterBox {
  const PdfNativeCharacterBox({required this.offset, required this.bounds});

  final int offset;
  final PdfBox bounds;
}

final class PdfNativeLine {
  const PdfNativeLine({required this.range, required this.bounds});

  final PdfTextRange range;
  final PdfBox bounds;
}

final class PdfNativeProjectionRequest {
  PdfNativeProjectionRequest({
    required this.documentRevision,
    required this.editRevision,
    required this.block,
    this.nativeTarget,
  }) {
    if (documentRevision.isEmpty) {
      throw ArgumentError.value(
        documentRevision,
        'documentRevision',
        'Must not be empty.',
      );
    }
    RangeError.checkNotNegative(editRevision, 'editRevision');
    if (nativeTarget != null &&
        nativeTarget!.locator.pageNumber != block.locator.pageNumber) {
      throw ArgumentError.value(
        nativeTarget,
        'nativeTarget',
        'Must be on the same page as the logical block.',
      );
    }
  }

  final String documentRevision;
  final int editRevision;
  final PdfTextBlock block;
  final PdfTextBlock? nativeTarget;

  PdfNativeProjectionRequest withNativeTarget(PdfTextBlock target) =>
      PdfNativeProjectionRequest(
        documentRevision: documentRevision,
        editRevision: editRevision,
        block: block,
        nativeTarget: target,
      );
}

final class PdfNativeProjectionResult {
  PdfNativeProjectionResult({
    required this.requestedRevision,
    required this.appliedRevision,
    required this.block,
    required List<PdfNativeLine> lines,
    required List<PdfNativeCharacterBox> characters,
    required List<int> affectedPages,
  }) : lines = List<PdfNativeLine>.unmodifiable(lines),
       characters = List<PdfNativeCharacterBox>.unmodifiable(characters),
       affectedPages = List<int>.unmodifiable(affectedPages) {
    RangeError.checkNotNegative(requestedRevision, 'requestedRevision');
    RangeError.checkValueInInterval(
      appliedRevision,
      0,
      requestedRevision,
      'appliedRevision',
    );
    for (final line in this.lines) {
      RangeError.checkValueInInterval(
        line.range.start,
        0,
        block.text.length,
        'line.range.start',
      );
      RangeError.checkValueInInterval(
        line.range.end,
        line.range.start,
        block.text.length,
        'line.range.end',
      );
    }
    for (final character in this.characters) {
      RangeError.checkValueInInterval(
        character.offset,
        0,
        block.text.length - 1,
        'character.offset',
      );
    }
    if (this.affectedPages.any((page) => page < 1)) {
      throw ArgumentError.value(
        this.affectedPages,
        'affectedPages',
        'Page numbers must be positive.',
      );
    }
    if (!this.affectedPages.contains(block.locator.pageNumber)) {
      throw ArgumentError.value(
        this.affectedPages,
        'affectedPages',
        'Must contain the edited block page.',
      );
    }
  }

  final int requestedRevision;
  final int appliedRevision;
  final PdfTextBlock block;
  final List<PdfNativeLine> lines;
  final List<PdfNativeCharacterBox> characters;
  final List<int> affectedPages;
}
