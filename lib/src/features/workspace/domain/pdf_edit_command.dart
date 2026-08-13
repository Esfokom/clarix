import 'pdf_text_types.dart';

sealed class PdfEditCommand {
  const PdfEditCommand({
    required this.id,
    required this.provenance,
    required this.summary,
  });

  final String id;
  final PdfCommandProvenance provenance;
  final String summary;

  List<PdfTextBlockLocator> get affectedLocators =>
      const <PdfTextBlockLocator>[];

  List<PdfTextBlock> apply(List<PdfTextBlock> blocks);
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks);

  List<PdfBookmarkSnapshot> applyBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => List<PdfBookmarkSnapshot>.unmodifiable(bookmarks);
  List<PdfBookmarkSnapshot> revertBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => List<PdfBookmarkSnapshot>.unmodifiable(bookmarks);
  List<PdfHighlightSnapshot> applyHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => List<PdfHighlightSnapshot>.unmodifiable(highlights);
  List<PdfHighlightSnapshot> revertHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => List<PdfHighlightSnapshot>.unmodifiable(highlights);
}

final class ReplacePdfTextCommand extends PdfEditCommand {
  const ReplacePdfTextCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.before,
    required this.after,
    required this.range,
  }) : super(summary: 'Replace PDF text');

  final PdfTextBlockLocator locator;
  final String before;
  final String after;
  final PdfTextRange range;

  @override
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) => _replaceBlock(
    blocks,
    locator,
    (PdfTextBlock block) => block.replaceText(range, before, after),
  );

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) => _replaceBlock(
    blocks,
    locator,
    (PdfTextBlock block) => block.replaceText(
      PdfTextRange(range.start, range.start + after.length),
      after,
      before,
    ),
  );
}

final class FormatPdfTextCommand extends PdfEditCommand {
  const FormatPdfTextCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.range,
    required this.before,
    required this.after,
  }) : super(summary: 'Format PDF text');

  final PdfTextBlockLocator locator;
  final PdfTextRange range;
  final PdfTextStyle before;
  final PdfTextStyle after;

  @override
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) => _replaceBlock(
    blocks,
    locator,
    (PdfTextBlock block) => block.formatRange(range, after),
  );

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) => _replaceBlock(
    blocks,
    locator,
    (PdfTextBlock block) => block.formatRange(range, before),
  );
}

final class MovePdfTextBlockCommand extends PdfEditCommand {
  const MovePdfTextBlockCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.before,
    required this.after,
  }) : super(summary: 'Move PDF text block');

  final PdfTextBlockLocator locator;
  final PdfBox before;
  final PdfBox after;

  @override
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, after);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, before);
}

final class ResizePdfTextBlockCommand extends PdfEditCommand {
  const ResizePdfTextBlockCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.before,
    required this.after,
  }) : super(summary: 'Resize PDF text block');

  final PdfTextBlockLocator locator;
  final PdfBox before;
  final PdfBox after;

  @override
  List<PdfTextBlockLocator> get affectedLocators => <PdfTextBlockLocator>[
    locator,
  ];

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, after);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, before);
}

final class ChangePdfBookmarkCommand extends PdfEditCommand {
  const ChangePdfBookmarkCommand({
    required super.id,
    required super.provenance,
    required this.before,
    required this.after,
  }) : super(summary: 'Change PDF bookmark');

  final PdfBookmarkSnapshot? before;
  final PdfBookmarkSnapshot? after;

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      List<PdfTextBlock>.unmodifiable(blocks);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      List<PdfTextBlock>.unmodifiable(blocks);

  @override
  List<PdfBookmarkSnapshot> applyBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => _replaceSnapshot(bookmarks, before?.id ?? after!.id, after);

  @override
  List<PdfBookmarkSnapshot> revertBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => _replaceSnapshot(bookmarks, after?.id ?? before!.id, before);
}

final class ChangePdfHighlightCommand extends PdfEditCommand {
  const ChangePdfHighlightCommand({
    required super.id,
    required super.provenance,
    required this.before,
    required this.after,
  }) : super(summary: 'Change PDF highlight');

  final PdfHighlightSnapshot? before;
  final PdfHighlightSnapshot? after;

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      List<PdfTextBlock>.unmodifiable(blocks);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      List<PdfTextBlock>.unmodifiable(blocks);

  @override
  List<PdfHighlightSnapshot> applyHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => _replaceSnapshot(highlights, before?.id ?? after!.id, after);

  @override
  List<PdfHighlightSnapshot> revertHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => _replaceSnapshot(highlights, after?.id ?? before!.id, before);
}

final class CompoundPdfEditCommand extends PdfEditCommand {
  CompoundPdfEditCommand({
    required super.id,
    required super.provenance,
    required super.summary,
    required List<PdfEditCommand> children,
  }) : children = List<PdfEditCommand>.unmodifiable(children);

  final List<PdfEditCommand> children;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(
        children.expand((PdfEditCommand command) => command.affectedLocators),
      );

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) => children.fold(
    List<PdfTextBlock>.unmodifiable(blocks),
    (List<PdfTextBlock> value, PdfEditCommand command) => command.apply(value),
  );

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      children.reversed.fold(
        List<PdfTextBlock>.unmodifiable(blocks),
        (List<PdfTextBlock> value, PdfEditCommand command) =>
            command.revert(value),
      );

  @override
  List<PdfBookmarkSnapshot> applyBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => children.fold(
    List<PdfBookmarkSnapshot>.unmodifiable(bookmarks),
    (List<PdfBookmarkSnapshot> value, PdfEditCommand command) =>
        command.applyBookmarks(value),
  );

  @override
  List<PdfBookmarkSnapshot> revertBookmarks(
    List<PdfBookmarkSnapshot> bookmarks,
  ) => children.reversed.fold(
    List<PdfBookmarkSnapshot>.unmodifiable(bookmarks),
    (List<PdfBookmarkSnapshot> value, PdfEditCommand command) =>
        command.revertBookmarks(value),
  );

  @override
  List<PdfHighlightSnapshot> applyHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => children.fold(
    List<PdfHighlightSnapshot>.unmodifiable(highlights),
    (List<PdfHighlightSnapshot> value, PdfEditCommand command) =>
        command.applyHighlights(value),
  );

  @override
  List<PdfHighlightSnapshot> revertHighlights(
    List<PdfHighlightSnapshot> highlights,
  ) => children.reversed.fold(
    List<PdfHighlightSnapshot>.unmodifiable(highlights),
    (List<PdfHighlightSnapshot> value, PdfEditCommand command) =>
        command.revertHighlights(value),
  );
}

List<PdfTextBlock> _replaceBounds(
  List<PdfTextBlock> blocks,
  PdfTextBlockLocator locator,
  PdfBox bounds,
) => _replaceBlock(
  blocks,
  locator,
  (PdfTextBlock block) => block.copyWith(bounds: bounds),
);

List<PdfTextBlock> _replaceBlock(
  List<PdfTextBlock> blocks,
  PdfTextBlockLocator locator,
  PdfTextBlock Function(PdfTextBlock block) replacement,
) {
  final int index = blocks.indexWhere(
    (PdfTextBlock block) => block.locator == locator,
  );
  if (index == -1) throw PdfStaleLocatorFailure(locator);
  final List<PdfTextBlock> next = List<PdfTextBlock>.from(blocks);
  next[index] = replacement(next[index]);
  return List<PdfTextBlock>.unmodifiable(next);
}

List<T> _replaceSnapshot<T>(List<T> values, String id, T? replacement) {
  final List<T> next = List<T>.from(values);
  final int index = next.indexWhere(
    (T value) => switch (value) {
      PdfBookmarkSnapshot bookmark => bookmark.id == id,
      PdfHighlightSnapshot highlight => highlight.id == id,
      _ => false,
    },
  );
  if (replacement == null) {
    if (index != -1) next.removeAt(index);
  } else if (index == -1) {
    next.add(replacement);
  } else {
    next[index] = replacement;
  }
  return List<T>.unmodifiable(next);
}
