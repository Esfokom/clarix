import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects stale document revisions before mutation', () async {
    final controller = PdfEditingController(commandId: () => 'command-1')
      ..registerSession('tab', _session());

    final result = await controller.dispatch(
      ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'rev-1',
        locator: _locator,
        range: const PdfTextRange(0, 3),
        replacement: 'New',
      ),
      provenance: PdfCommandProvenance.manual,
    );

    expect(result.failure, isA<PdfRevisionConflictFailure>());
    expect(controller.sessionFor('tab').blocks.single.text, 'Old');
  });

  test('bookmark then text replacement undo in chronological order', () async {
    final controller = PdfEditingController(
      commandId: (() {
        var value = 0;
        return () => 'command-${++value}';
      })(),
    )..registerSession('tab', _session());
    final bookmark = PdfBookmarkSnapshot(
      id: 'bookmark-1',
      label: 'Methods',
      pageNumber: 1,
      createdAt: DateTime.utc(2026),
    );

    await controller.dispatch(
      ChangePdfBookmarkIntent(
        documentId: 'doc',
        documentRevision: 'rev-2',
        before: null,
        after: bookmark,
      ),
      provenance: PdfCommandProvenance.manual,
    );
    await controller.dispatch(
      ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'rev-2',
        locator: _locator,
        range: const PdfTextRange(0, 3),
        replacement: 'New',
      ),
      provenance: PdfCommandProvenance.manual,
    );

    await controller.undo('tab');
    expect(controller.sessionFor('tab').blocks.single.text, 'Old');
    expect(controller.sessionFor('tab').bookmarks, <PdfBookmarkSnapshot>[
      bookmark,
    ]);
    await controller.undo('tab');
    expect(controller.sessionFor('tab').bookmarks, isEmpty);
  });

  test(
    'validates capabilities and exposes immutable controller snapshots',
    () async {
      final controller = PdfEditingController(commandId: () => 'command-1')
        ..registerSession('tab', _session(editable: false));

      final result = await controller.dispatch(
        ReplacePdfTextIntent(
          documentId: 'doc',
          documentRevision: 'rev-2',
          locator: _locator,
          range: const PdfTextRange(0, 3),
          replacement: 'New',
        ),
        provenance: PdfCommandProvenance.agent,
      );

      expect(result.failure, isA<PdfReadOnlyTextBlockFailure>());
      expect(() => controller.sessionsByTabId.clear(), throwsUnsupportedError);
    },
  );

  test('matches selected casing and coalesces one typing group', () async {
    var nextId = 0;
    final controller = PdfEditingController(
      commandId: () => 'command-${++nextId}',
    )..registerSession('tab', _session(text: 'TOTAL'));

    for (final edit in <(PdfTextRange, String)>[
      (const PdfTextRange(0, 5), 'net'),
      (const PdfTextRange(3, 3), ' '),
      (const PdfTextRange(4, 4), 'income'),
    ]) {
      await controller.dispatch(
        ReplacePdfTextIntent(
          documentId: 'doc',
          documentRevision: 'rev-2',
          locator: _locator,
          range: edit.$1,
          replacement: edit.$2,
          coalescingKey: 'typing-1',
        ),
        provenance: PdfCommandProvenance.manual,
      );
    }

    expect(controller.sessionFor('tab').blocks.single.text, 'NET INCOME');
    expect(controller.sessionFor('tab').commands, hasLength(1));

    await controller.dispatch(
      ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'rev-2',
        locator: _locator,
        range: const PdfTextRange(10, 10),
        replacement: '!',
        coalescingKey: 'typing-2',
      ),
      provenance: PdfCommandProvenance.manual,
    );
    expect(controller.sessionFor('tab').commands, hasLength(2));
  });
}

final _locator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  textDigest: 'text',
  geometryDigest: 'geometry',
  fontFingerprint: 'font',
  sourceRevision: 'rev-2',
);

PdfEditingSession _session({bool editable = true, String text = 'Old'}) {
  const style = PdfTextStyle(
    fontFamily: 'Helvetica',
    fontSize: 12,
    fillColorValue: 0xff000000,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 12,
    horizontalScaling: 1,
  );
  final block = PdfTextBlock(
    locator: _locator,
    text: text,
    originalText: text,
    runs: <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, text.length), style: style),
    ],
    bounds: const PdfBox(0, 0, 100, 20),
    transform: const PdfTransform(1, 0, 0, 1, 0, 0),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: editable
        ? PdfTextCapability.values
        : const <PdfTextCapability>[],
    readOnlyReason: editable ? null : PdfReadOnlyReason.complexRendering,
  );
  return PdfEditingSession.empty(
    'doc',
    sourceRevision: 'rev-2',
  ).withBlocks(<PdfTextBlock>[block]);
}
