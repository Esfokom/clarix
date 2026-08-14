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

  /// Captures every inverse value the command needs before it enters history.
  PdfEditCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) => this;

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

  @override
  bool operator ==(Object other) =>
      other is PdfEditCommand &&
      runtimeType == other.runtimeType &&
      id == other.id &&
      provenance == other.provenance &&
      summary == other.summary;

  @override
  int get hashCode => Object.hash(runtimeType, id, provenance, summary);
}

final class ReplacePdfTextCommand extends PdfEditCommand {
  const ReplacePdfTextCommand({
    required super.id,
    required super.provenance,
    required this.locator,
    required this.before,
    required this.after,
    required this.range,
    this.beforeBlock,
    this.afterBlock,
    this.coalescingKey,
  }) : super(summary: 'Replace PDF text');

  final PdfTextBlockLocator locator;
  final String before;
  final String after;
  final PdfTextRange range;
  final PdfTextBlock? beforeBlock;
  final PdfTextBlock? afterBlock;
  final String? coalescingKey;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  ReplacePdfTextCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) {
    if (beforeBlock != null && afterBlock != null) return this;
    final PdfTextBlock original = _findBlock(blocks, locator);
    return ReplacePdfTextCommand(
      id: id,
      provenance: provenance,
      locator: locator,
      before: before,
      after: after,
      range: range,
      beforeBlock: original,
      afterBlock: original.replaceText(range, before, after),
      coalescingKey: coalescingKey,
    );
  }

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) {
    final ReplacePdfTextCommand prepared = materialize(
      blocks: blocks,
      bookmarks: const <PdfBookmarkSnapshot>[],
      highlights: const <PdfHighlightSnapshot>[],
    );
    return _replaceBlock(blocks, locator, (PdfTextBlock block) {
      block.validateOperation(PdfTextCapability.replace);
      return prepared.afterBlock!;
    });
  }

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) {
    if (beforeBlock == null) {
      throw StateError(
        'A text command must be materialized before it is reverted.',
      );
    }
    return _replaceBlock(blocks, locator, (_) => beforeBlock!);
  }

  @override
  bool operator ==(Object other) =>
      other is ReplacePdfTextCommand &&
      super == other &&
      other.locator == locator &&
      other.before == before &&
      other.after == after &&
      other.range == range &&
      other.beforeBlock == beforeBlock &&
      other.afterBlock == afterBlock &&
      other.coalescingKey == coalescingKey;

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    locator,
    before,
    after,
    range,
    beforeBlock,
    afterBlock,
    coalescingKey,
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
    this.beforeBlock,
    this.afterBlock,
  }) : super(summary: 'Format PDF text');

  final PdfTextBlockLocator locator;
  final PdfTextRange range;
  final PdfTextStyle before;
  final PdfTextStyle after;
  final PdfTextBlock? beforeBlock;
  final PdfTextBlock? afterBlock;

  @override
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  FormatPdfTextCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) {
    if (beforeBlock != null && afterBlock != null) return this;
    final PdfTextBlock original = _findBlock(blocks, locator);
    return FormatPdfTextCommand(
      id: id,
      provenance: provenance,
      locator: locator,
      range: range,
      before: before,
      after: after,
      beforeBlock: original,
      afterBlock: original.formatRange(range, after),
    );
  }

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) {
    final FormatPdfTextCommand prepared = materialize(
      blocks: blocks,
      bookmarks: const <PdfBookmarkSnapshot>[],
      highlights: const <PdfHighlightSnapshot>[],
    );
    return _replaceBlock(blocks, locator, (PdfTextBlock block) {
      block.validateOperation(PdfTextCapability.format);
      return prepared.afterBlock!;
    });
  }

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) {
    if (beforeBlock == null) {
      throw StateError(
        'A format command must be materialized before it is reverted.',
      );
    }
    return _replaceBlock(blocks, locator, (_) => beforeBlock!);
  }

  @override
  bool operator ==(Object other) =>
      other is FormatPdfTextCommand &&
      super == other &&
      other.locator == locator &&
      other.range == range &&
      other.before == before &&
      other.after == after &&
      other.beforeBlock == beforeBlock &&
      other.afterBlock == afterBlock;

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    locator,
    range,
    before,
    after,
    beforeBlock,
    afterBlock,
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
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, after, PdfTextCapability.move);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, before, PdfTextCapability.move);

  @override
  bool operator ==(Object other) =>
      other is MovePdfTextBlockCommand &&
      super == other &&
      other.locator == locator &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(super.hashCode, locator, before, after);
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
  List<PdfTextBlockLocator> get affectedLocators =>
      List<PdfTextBlockLocator>.unmodifiable(<PdfTextBlockLocator>[locator]);

  @override
  List<PdfTextBlock> apply(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, after, PdfTextCapability.resize);

  @override
  List<PdfTextBlock> revert(List<PdfTextBlock> blocks) =>
      _replaceBounds(blocks, locator, before, PdfTextCapability.resize);

  @override
  bool operator ==(Object other) =>
      other is ResizePdfTextBlockCommand &&
      super == other &&
      other.locator == locator &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(super.hashCode, locator, before, after);
}

final class ChangePdfBookmarkCommand extends PdfEditCommand {
  const ChangePdfBookmarkCommand({
    required super.id,
    required super.provenance,
    required this.before,
    required this.after,
    this.beforeIndex,
  }) : super(summary: 'Change PDF bookmark');

  final PdfBookmarkSnapshot? before;
  final PdfBookmarkSnapshot? after;
  final int? beforeIndex;

  @override
  ChangePdfBookmarkCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) {
    if (before == null || after != null || beforeIndex != null) return this;
    final int index = bookmarks.indexWhere(
      (PdfBookmarkSnapshot item) => item.id == before!.id,
    );
    if (index == -1) throw StateError('The bookmark to delete is absent.');
    return ChangePdfBookmarkCommand(
      id: id,
      provenance: provenance,
      before: before,
      after: after,
      beforeIndex: index,
    );
  }

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
  ) => _replaceSnapshot(
    bookmarks,
    after?.id ?? before!.id,
    before,
    insertIndex: beforeIndex,
  );

  @override
  bool operator ==(Object other) =>
      other is ChangePdfBookmarkCommand &&
      super == other &&
      other.before == before &&
      other.after == after &&
      other.beforeIndex == beforeIndex;

  @override
  int get hashCode => Object.hash(super.hashCode, before, after, beforeIndex);
}

final class ChangePdfHighlightCommand extends PdfEditCommand {
  const ChangePdfHighlightCommand({
    required super.id,
    required super.provenance,
    required this.before,
    required this.after,
    this.beforeIndex,
  }) : super(summary: 'Change PDF highlight');

  final PdfHighlightSnapshot? before;
  final PdfHighlightSnapshot? after;
  final int? beforeIndex;

  @override
  ChangePdfHighlightCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) {
    if (before == null || after != null || beforeIndex != null) return this;
    final int index = highlights.indexWhere(
      (PdfHighlightSnapshot item) => item.id == before!.id,
    );
    if (index == -1) throw StateError('The highlight to delete is absent.');
    return ChangePdfHighlightCommand(
      id: id,
      provenance: provenance,
      before: before,
      after: after,
      beforeIndex: index,
    );
  }

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
  ) => _replaceSnapshot(
    highlights,
    after?.id ?? before!.id,
    before,
    insertIndex: beforeIndex,
  );

  @override
  bool operator ==(Object other) =>
      other is ChangePdfHighlightCommand &&
      super == other &&
      other.before == before &&
      other.after == after &&
      other.beforeIndex == beforeIndex;

  @override
  int get hashCode => Object.hash(super.hashCode, before, after, beforeIndex);
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
  CompoundPdfEditCommand materialize({
    required List<PdfTextBlock> blocks,
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) {
    List<PdfTextBlock> nextBlocks = blocks;
    List<PdfBookmarkSnapshot> nextBookmarks = bookmarks;
    List<PdfHighlightSnapshot> nextHighlights = highlights;
    final List<PdfEditCommand> prepared = <PdfEditCommand>[];
    for (final PdfEditCommand child in children) {
      final PdfEditCommand materialized = child.materialize(
        blocks: nextBlocks,
        bookmarks: nextBookmarks,
        highlights: nextHighlights,
      );
      prepared.add(materialized);
      nextBlocks = materialized.apply(nextBlocks);
      nextBookmarks = materialized.applyBookmarks(nextBookmarks);
      nextHighlights = materialized.applyHighlights(nextHighlights);
    }
    return CompoundPdfEditCommand(
      id: id,
      provenance: provenance,
      summary: summary,
      children: prepared,
    );
  }

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

  @override
  bool operator ==(Object other) =>
      other is CompoundPdfEditCommand &&
      super == other &&
      _sameList(other.children, children);

  @override
  int get hashCode => Object.hash(super.hashCode, Object.hashAll(children));
}

List<PdfTextBlock> _replaceBounds(
  List<PdfTextBlock> blocks,
  PdfTextBlockLocator locator,
  PdfBox bounds,
  PdfTextCapability capability,
) => _replaceBlock(
  blocks,
  locator,
  (PdfTextBlock block) => block.withBoundsFor(capability, bounds),
);

PdfTextBlock _findBlock(
  List<PdfTextBlock> blocks,
  PdfTextBlockLocator locator,
) {
  final int index = blocks.indexWhere(
    (PdfTextBlock block) => block.locator == locator,
  );
  if (index == -1) throw PdfStaleLocatorFailure(locator);
  return blocks[index];
}

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

List<T> _replaceSnapshot<T>(
  List<T> values,
  String id,
  T? replacement, {
  int? insertIndex,
}) {
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
    next.insert(insertIndex?.clamp(0, next.length) ?? next.length, replacement);
  } else {
    next[index] = replacement;
  }
  return List<T>.unmodifiable(next);
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
