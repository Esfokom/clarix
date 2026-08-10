class PdfBookmarkEdit {
  const PdfBookmarkEdit({
    required this.id,
    required this.title,
    required this.pageNumber,
  });

  final String id;
  final String title;
  final int pageNumber;

  @override
  bool operator ==(Object other) =>
      other is PdfBookmarkEdit &&
      other.id == id &&
      other.title == title &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => Object.hash(id, title, pageNumber);
}

class PdfEditSession {
  const PdfEditSession._({
    required this.documentId,
    required this.bookmarks,
    required List<PdfBookmarkEdit> savedBookmarks,
    required List<_BookmarkCommand> undo,
    required List<_BookmarkCommand> redo,
  }) : _savedBookmarks = savedBookmarks,
       _undo = undo,
       _redo = redo;

  factory PdfEditSession.empty(String documentId) => PdfEditSession._(
    documentId: documentId,
    bookmarks: const <PdfBookmarkEdit>[],
    savedBookmarks: const <PdfBookmarkEdit>[],
    undo: const <_BookmarkCommand>[],
    redo: const <_BookmarkCommand>[],
  );

  final String documentId;
  final List<PdfBookmarkEdit> bookmarks;
  final List<PdfBookmarkEdit> _savedBookmarks;
  final List<_BookmarkCommand> _undo;
  final List<_BookmarkCommand> _redo;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isDirty => !_sameBookmarks(bookmarks, _savedBookmarks);

  PdfEditSession addBookmark(PdfBookmarkEdit bookmark) => _apply(
    _BookmarkCommand.add(bookmark),
  );

  PdfEditSession undo() {
    if (_undo.isEmpty) return this;
    final _BookmarkCommand command = _undo.last;
    return PdfEditSession._(
      documentId: documentId,
      bookmarks: command.revert(bookmarks),
      savedBookmarks: _savedBookmarks,
      undo: _undo.sublist(0, _undo.length - 1),
      redo: <_BookmarkCommand>[..._redo, command],
    );
  }

  PdfEditSession redo() {
    if (_redo.isEmpty) return this;
    final _BookmarkCommand command = _redo.last;
    return PdfEditSession._(
      documentId: documentId,
      bookmarks: command.apply(bookmarks),
      savedBookmarks: _savedBookmarks,
      undo: <_BookmarkCommand>[..._undo, command],
      redo: _redo.sublist(0, _redo.length - 1),
    );
  }

  PdfEditSession _apply(_BookmarkCommand command) => PdfEditSession._(
    documentId: documentId,
    bookmarks: command.apply(bookmarks),
    savedBookmarks: _savedBookmarks,
    undo: <_BookmarkCommand>[..._undo, command],
    redo: const <_BookmarkCommand>[],
  );

  static bool _sameBookmarks(
    List<PdfBookmarkEdit> left,
    List<PdfBookmarkEdit> right,
  ) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class _BookmarkCommand {
  const _BookmarkCommand.add(this.bookmark);
  final PdfBookmarkEdit bookmark;

  List<PdfBookmarkEdit> apply(List<PdfBookmarkEdit> value) =>
      <PdfBookmarkEdit>[...value, bookmark];

  List<PdfBookmarkEdit> revert(List<PdfBookmarkEdit> value) => value
      .where((PdfBookmarkEdit item) => item.id != bookmark.id)
      .toList(growable: false);
}
