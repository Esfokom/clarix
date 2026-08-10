import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('undoing a new bookmark restores a clean session and redo restores it', () {
    final PdfEditSession initial = PdfEditSession.empty('document');
    final PdfEditSession edited = initial.addBookmark(
      const PdfBookmarkEdit(id: 'bookmark-1', title: 'Methods', pageNumber: 3),
    );

    expect(edited.isDirty, isTrue);
    expect(edited.canUndo, isTrue);

    final PdfEditSession undone = edited.undo();
    expect(undone.bookmarks, isEmpty);
    expect(undone.isDirty, isFalse);
    expect(undone.canRedo, isTrue);

    final PdfEditSession redone = undone.redo();
    expect(redone.bookmarks.single.title, 'Methods');
    expect(redone.isDirty, isTrue);
  });

  test('a new edit clears redo history', () {
    final PdfEditSession undone = PdfEditSession.empty('document')
        .addBookmark(
          const PdfBookmarkEdit(id: 'bookmark-1', title: 'Methods', pageNumber: 3),
        )
        .undo();

    expect(
      undone
          .addBookmark(
            const PdfBookmarkEdit(id: 'bookmark-2', title: 'Results', pageNumber: 7),
          )
          .canRedo,
      isFalse,
    );
  });
}
