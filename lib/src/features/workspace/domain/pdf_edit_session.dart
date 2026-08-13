import 'pdf_edit_command.dart';
import 'pdf_text_types.dart';

final class PdfEditingSession {
  const PdfEditingSession._({
    required this.documentId,
    required this.sourceRevision,
    required this.mode,
    required this.blocks,
    required this.bookmarks,
    required this.highlights,
    required this.commands,
    required this.cursor,
    required this.savedCursor,
    required this.selection,
    required this.caseMatching,
  });

  factory PdfEditingSession.empty(
    String documentId, {
    required String sourceRevision,
  }) => PdfEditingSession._(
    documentId: documentId,
    sourceRevision: sourceRevision,
    mode: PdfEditingMode.reading,
    blocks: const <PdfTextBlock>[],
    bookmarks: const <PdfBookmarkSnapshot>[],
    highlights: const <PdfHighlightSnapshot>[],
    commands: const <PdfEditCommand>[],
    cursor: 0,
    savedCursor: 0,
    selection: null,
    caseMatching: true,
  );

  final String documentId;
  final String sourceRevision;
  final PdfEditingMode mode;
  final List<PdfTextBlock> blocks;
  final List<PdfBookmarkSnapshot> bookmarks;
  final List<PdfHighlightSnapshot> highlights;
  final List<PdfEditCommand> commands;
  final int cursor;
  final int savedCursor;
  final PdfTextSelection? selection;
  final bool caseMatching;

  String get revision => sourceRevision;
  bool get canUndo => cursor > 0;
  bool get canRedo => cursor < commands.length;
  bool get isDirty => cursor != savedCursor;
  Set<PdfTextBlockLocator> get overflowingLocators =>
      Set<PdfTextBlockLocator>.unmodifiable(
        blocks
            .where((PdfTextBlock block) => block.overflow)
            .map((PdfTextBlock block) => block.locator),
      );

  PdfEditingSession withBlocks(List<PdfTextBlock> blocks) =>
      _copy(blocks: blocks);

  PdfEditingSession withMetadata({
    required List<PdfBookmarkSnapshot> bookmarks,
    required List<PdfHighlightSnapshot> highlights,
  }) => _copy(bookmarks: bookmarks, highlights: highlights);

  PdfEditingSession withMode(PdfEditingMode mode) => _copy(mode: mode);

  PdfEditingSession withSelection(PdfTextSelection? selection) =>
      _copy(selection: selection, replaceSelection: true);

  PdfEditingSession withCaseMatching(bool caseMatching) =>
      _copy(caseMatching: caseMatching);

  PdfEditingSession applyCommand(PdfEditCommand command) {
    final PdfEditCommand materialized = command.materialize(
      blocks: blocks,
      bookmarks: bookmarks,
      highlights: highlights,
    );
    final List<PdfEditCommand> kept =
        commands.take(cursor).toList(growable: true)..add(materialized);
    final int checkpoint = savedCursor > cursor ? -1 : savedCursor;
    return _copy(
      commands: kept,
      cursor: kept.length,
      savedCursor: checkpoint,
      blocks: materialized.apply(blocks),
      bookmarks: materialized.applyBookmarks(bookmarks),
      highlights: materialized.applyHighlights(highlights),
    );
  }

  PdfEditingSession undo() => cursor == 0
      ? this
      : _copy(
          cursor: cursor - 1,
          blocks: commands[cursor - 1].revert(blocks),
          bookmarks: commands[cursor - 1].revertBookmarks(bookmarks),
          highlights: commands[cursor - 1].revertHighlights(highlights),
        );

  PdfEditingSession redo() => cursor == commands.length
      ? this
      : _copy(
          cursor: cursor + 1,
          blocks: commands[cursor].apply(blocks),
          bookmarks: commands[cursor].applyBookmarks(bookmarks),
          highlights: commands[cursor].applyHighlights(highlights),
        );

  PdfEditingSession markSaved() => _copy(savedCursor: cursor);

  PdfEditingSession _copy({
    String? sourceRevision,
    PdfEditingMode? mode,
    List<PdfTextBlock>? blocks,
    List<PdfBookmarkSnapshot>? bookmarks,
    List<PdfHighlightSnapshot>? highlights,
    List<PdfEditCommand>? commands,
    int? cursor,
    int? savedCursor,
    PdfTextSelection? selection,
    bool replaceSelection = false,
    bool? caseMatching,
  }) => PdfEditingSession._(
    documentId: documentId,
    sourceRevision: sourceRevision ?? this.sourceRevision,
    mode: mode ?? this.mode,
    blocks: List<PdfTextBlock>.unmodifiable(blocks ?? this.blocks),
    bookmarks: List<PdfBookmarkSnapshot>.unmodifiable(
      bookmarks ?? this.bookmarks,
    ),
    highlights: List<PdfHighlightSnapshot>.unmodifiable(
      highlights ?? this.highlights,
    ),
    commands: List<PdfEditCommand>.unmodifiable(commands ?? this.commands),
    cursor: cursor ?? this.cursor,
    savedCursor: savedCursor ?? this.savedCursor,
    selection: replaceSelection ? selection : this.selection,
    caseMatching: caseMatching ?? this.caseMatching,
  );
}
