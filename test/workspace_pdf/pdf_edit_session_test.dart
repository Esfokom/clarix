import 'package:clarix/src/features/workspace/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved checkpoint survives undo and redo', () {
    final PdfTextBlock block = editableBlock(text: 'Revenue');
    final PdfEditingSession session =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              ReplacePdfTextCommand(
                id: 'c1',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                before: 'Revenue',
                after: 'Net revenue',
                range: const PdfTextRange(0, 7),
              ),
            )
            .markSaved();

    expect(session.isDirty, isFalse);
    expect(session.undo().isDirty, isTrue);
    expect(session.undo().redo().isDirty, isFalse);
  });

  test('a new command after undo clears redo across command kinds', () {
    final PdfEditingSession session = sessionWithOneBlock()
        .applyCommand(replaceCommand('c1', 'A', 'B'))
        .applyCommand(formatCommand('c2', fontSize: 14))
        .undo()
        .applyCommand(resizeCommand('c3', width: 220));

    expect(session.canRedo, isFalse);
    expect(
      session.commands.map((PdfEditCommand command) => command.id),
      <String>['c1', 'c3'],
    );
  });

  test('replacement uses UTF-16 range offsets and restores the exact text', () {
    final PdfTextBlock block = editableBlock(text: 'A😀B');
    final PdfEditingSession edited =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              ReplacePdfTextCommand(
                id: 'emoji',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                before: '😀',
                after: 'Z',
                range: const PdfTextRange(1, 3),
              ),
            );

    expect(edited.blocks.single.text, 'AZB');
    expect(edited.undo().blocks.single.text, 'A😀B');
  });

  test('insertion into an empty block inherits its available text style', () {
    final PdfTextBlock block = editableBlock(text: '');
    final PdfEditingSession edited =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              ReplacePdfTextCommand(
                id: 'insert',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                before: '',
                after: 'New',
                range: const PdfTextRange(0, 0),
              ),
            );

    expect(edited.blocks.single.text, 'New');
    expect(edited.blocks.single.styleAt(0), testStyle);
  });

  test('compound commands revert children in reverse order', () {
    final PdfTextBlock block = editableBlock(text: 'A');
    final PdfEditingSession edited =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              CompoundPdfEditCommand(
                id: 'compound',
                provenance: PdfCommandProvenance.agent,
                summary: 'Replace and resize',
                children: <PdfEditCommand>[
                  replaceCommand('replace', 'A', 'B'),
                  resizeCommand('resize', width: 220),
                ],
              ),
            );

    expect(edited.blocks.single.text, 'B');
    expect(edited.blocks.single.bounds.width, 220);
    expect(edited.undo().blocks.single.text, 'A');
    expect(edited.undo().blocks.single.bounds.width, 100);
  });

  test('bookmark and highlight changes share chronological undo history', () {
    final PdfBookmarkSnapshot bookmark = PdfBookmarkSnapshot(
      id: 'bookmark',
      label: 'Summary',
      pageNumber: 2,
      createdAt: DateTime.utc(2026),
    );
    final PdfHighlightSnapshot highlight = PdfHighlightSnapshot(
      id: 'highlight',
      pageNumber: 2,
      bounds: const <PdfBox>[PdfBox(0, 0, 10, 10)],
      selectedText: 'Summary',
      note: null,
      colorValue: 0x66FFD54F,
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
    );
    final PdfEditingSession session =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .applyCommand(
              ChangePdfBookmarkCommand(
                id: 'bookmark',
                provenance: PdfCommandProvenance.manual,
                before: null,
                after: bookmark,
              ),
            )
            .applyCommand(
              ChangePdfHighlightCommand(
                id: 'highlight',
                provenance: PdfCommandProvenance.manual,
                before: null,
                after: highlight,
              ),
            );

    expect(session.bookmarks, <PdfBookmarkSnapshot>[bookmark]);
    expect(session.highlights, <PdfHighlightSnapshot>[highlight]);
    expect(session.undo().highlights, isEmpty);
    expect(session.undo().undo().bookmarks, isEmpty);
  });

  test(
    'commands reject blocks that are read-only or lack the operation capability',
    () {
      final PdfTextBlock readOnly = editableBlock(
        text: 'Locked',
        readOnlyReason: PdfReadOnlyReason.type3Font,
      );
      final PdfTextBlock noMove = editableBlock(
        text: 'Fixed',
        capabilities: const <PdfTextCapability>[PdfTextCapability.replace],
      );

      expect(
        () => PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[readOnly])
            .applyCommand(
              ReplacePdfTextCommand(
                id: 'locked',
                provenance: PdfCommandProvenance.manual,
                locator: readOnly.locator,
                before: 'Locked',
                after: 'Changed',
                range: const PdfTextRange(0, 6),
              ),
            ),
        throwsA(isA<PdfReadOnlyTextBlockFailure>()),
      );
      expect(
        () => PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[noMove])
            .applyCommand(
              MovePdfTextBlockCommand(
                id: 'fixed',
                provenance: PdfCommandProvenance.manual,
                locator: noMove.locator,
                before: noMove.bounds,
                after: const PdfBox(10, 0, 110, 20),
              ),
            ),
        throwsA(isA<PdfUnsupportedTextOperationFailure>()),
      );
    },
  );

  test('text and format commands restore every heterogeneous text run', () {
    final PdfTextStyle boldStyle = testStyle.copyWith(fontWeight: 700);
    final PdfTextBlock block = editableBlock(
      text: 'ABCD',
      runs: <PdfTextRun>[
        const PdfTextRun(range: PdfTextRange(0, 2), style: testStyle),
        PdfTextRun(range: const PdfTextRange(2, 4), style: boldStyle),
      ],
    );
    final PdfEditingSession replaced =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              ReplacePdfTextCommand(
                id: 'replace',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                before: 'BC',
                after: 'X',
                range: const PdfTextRange(1, 3),
              ),
            );
    final PdfEditingSession formatted =
        PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
            .withBlocks(<PdfTextBlock>[block])
            .applyCommand(
              FormatPdfTextCommand(
                id: 'format',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                range: const PdfTextRange(1, 3),
                before: testStyle,
                after: testStyle.copyWith(fontSize: 16),
              ),
            );

    expect(replaced.undo().blocks.single, block);
    expect(
      replaced.undo().redo().blocks.single.runs,
      replaced.blocks.single.runs,
    );
    expect(formatted.undo().blocks.single, block);
    expect(
      formatted.undo().redo().blocks.single.runs,
      formatted.blocks.single.runs,
    );
  });

  test(
    'undo restores deleted bookmark and highlight at their original indexes',
    () {
      final PdfBookmarkSnapshot firstBookmark = bookmark('first');
      final PdfBookmarkSnapshot removedBookmark = bookmark('removed');
      final PdfBookmarkSnapshot lastBookmark = bookmark('last');
      final PdfHighlightSnapshot firstHighlight = highlight('first');
      final PdfHighlightSnapshot removedHighlight = highlight('removed');
      final PdfHighlightSnapshot lastHighlight = highlight('last');
      final PdfEditingSession session =
          PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
              .applyCommand(
                ChangePdfBookmarkCommand(
                  id: 'add-first-bookmark',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: firstBookmark,
                ),
              )
              .applyCommand(
                ChangePdfBookmarkCommand(
                  id: 'add-removed-bookmark',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: removedBookmark,
                ),
              )
              .applyCommand(
                ChangePdfBookmarkCommand(
                  id: 'add-last-bookmark',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: lastBookmark,
                ),
              )
              .applyCommand(
                ChangePdfHighlightCommand(
                  id: 'add-first-highlight',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: firstHighlight,
                ),
              )
              .applyCommand(
                ChangePdfHighlightCommand(
                  id: 'add-removed-highlight',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: removedHighlight,
                ),
              )
              .applyCommand(
                ChangePdfHighlightCommand(
                  id: 'add-last-highlight',
                  provenance: PdfCommandProvenance.manual,
                  before: null,
                  after: lastHighlight,
                ),
              )
              .applyCommand(
                ChangePdfBookmarkCommand(
                  id: 'delete-bookmark',
                  provenance: PdfCommandProvenance.manual,
                  before: removedBookmark,
                  after: null,
                ),
              )
              .applyCommand(
                ChangePdfHighlightCommand(
                  id: 'delete-highlight',
                  provenance: PdfCommandProvenance.manual,
                  before: removedHighlight,
                  after: null,
                ),
              );

      final PdfEditingSession restored = session.undo().undo();

      expect(restored.bookmarks, <PdfBookmarkSnapshot>[
        firstBookmark,
        removedBookmark,
        lastBookmark,
      ]);
      expect(restored.highlights, <PdfHighlightSnapshot>[
        firstHighlight,
        removedHighlight,
        lastHighlight,
      ]);
    },
  );

  test('replacement rejects a UTF-16 range that splits a surrogate pair', () {
    final PdfTextBlock block = editableBlock(text: 'A😀B');

    expect(
      () => PdfEditingSession.empty('doc', sourceRevision: 'sha256:a')
          .withBlocks(<PdfTextBlock>[block])
          .applyCommand(
            ReplacePdfTextCommand(
              id: 'split-surrogate',
              provenance: PdfCommandProvenance.manual,
              locator: block.locator,
              before: '\ud83d',
              after: 'X',
              range: const PdfTextRange(1, 2),
            ),
          ),
      throwsA(isA<PdfInvalidTextRangeFailure>()),
    );
  });
}

PdfEditingSession sessionWithOneBlock() => PdfEditingSession.empty(
  'doc',
  sourceRevision: 'sha256:a',
).withBlocks(<PdfTextBlock>[editableBlock(text: 'A')]);

ReplacePdfTextCommand replaceCommand(String id, String before, String after) =>
    ReplacePdfTextCommand(
      id: id,
      provenance: PdfCommandProvenance.manual,
      locator: testLocator,
      before: before,
      after: after,
      range: PdfTextRange(0, before.length),
    );

FormatPdfTextCommand formatCommand(String id, {required double fontSize}) =>
    FormatPdfTextCommand(
      id: id,
      provenance: PdfCommandProvenance.manual,
      locator: testLocator,
      range: const PdfTextRange(0, 1),
      before: testStyle,
      after: testStyle.copyWith(fontSize: fontSize),
    );

ResizePdfTextBlockCommand resizeCommand(String id, {required double width}) =>
    ResizePdfTextBlockCommand(
      id: id,
      provenance: PdfCommandProvenance.manual,
      locator: testLocator,
      before: const PdfBox(0, 0, 100, 20),
      after: PdfBox(0, 0, width, 20),
    );

final PdfTextBlockLocator testLocator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: <int>[0],
  textDigest: 'text',
  geometryDigest: 'geometry',
  fontFingerprint: 'font',
  sourceRevision: 'sha256:a',
);

const PdfTextStyle testStyle = PdfTextStyle(
  fontFamily: 'Inter',
  fontSize: 12,
  fillColorValue: 0xFF000000,
  fontWeight: 400,
  italic: false,
  underline: false,
  baselineShift: 0,
  alignment: PdfTextAlignment.left,
  characterSpacing: 0,
  lineSpacing: 0,
  horizontalScaling: 1,
);

PdfTextBlock editableBlock({
  required String text,
  List<PdfTextRun>? runs,
  List<PdfTextCapability> capabilities = const <PdfTextCapability>[
    PdfTextCapability.replace,
    PdfTextCapability.format,
    PdfTextCapability.move,
    PdfTextCapability.resize,
  ],
  PdfReadOnlyReason? readOnlyReason,
}) => PdfTextBlock(
  locator: testLocator,
  text: text,
  originalText: text,
  runs:
      runs ??
      <PdfTextRun>[
        PdfTextRun(range: PdfTextRange(0, text.length), style: testStyle),
      ],
  bounds: const PdfBox(0, 0, 100, 20),
  transform: const PdfTransform(1, 0, 0, 1, 0, 0),
  baseline: 0,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: capabilities,
  readOnlyReason: readOnlyReason,
);

PdfBookmarkSnapshot bookmark(String id) => PdfBookmarkSnapshot(
  id: id,
  label: id,
  pageNumber: 1,
  createdAt: DateTime.utc(2026),
);

PdfHighlightSnapshot highlight(String id) => PdfHighlightSnapshot(
  id: id,
  pageNumber: 1,
  bounds: const <PdfBox>[PdfBox(0, 0, 10, 10)],
  selectedText: id,
  note: null,
  colorValue: 0x66FFD54F,
  createdAt: DateTime.utc(2026),
  modifiedAt: DateTime.utc(2026),
);
