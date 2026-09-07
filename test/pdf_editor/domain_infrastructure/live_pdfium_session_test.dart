import 'dart:io';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_import_manifest_builder.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pdf_text_fixture.dart';

void main() {
  test(
    'measures proportional glyphs by object identity in the live document',
    () async {
      final file = await PdfTextFixture.singleBlock('Wi');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      final block = (await session.inspectTextBlocks(
        sourceRevision: 'source',
        pageNumbers: [1],
      )).single;
      final locator = const LivePdfiumImportManifestBuilder()
          .build(sourceFingerprint: 'source', blocks: [block])
          .bindings
          .single
          .locator;
      final objects = await session.measureTextObjects([
        EditorSceneObject(
          kind: EditorSceneObjectKind.text,
          objectId: 'text',
          pageId: 'page',
          text: 'Wi',
          bounds: EditorPdfBox(
            left: block.bounds.left,
            bottom: block.bounds.bottom,
            right: block.bounds.right,
            top: block.bounds.top,
          ),
          transform: const EditorAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: 1,
            e: 0,
            f: 0,
          ),
          capability: 'editable',
          modifiedRevision: 0,
          runs: const [],
          physicalLocator: locator,
        ),
      ]);
      final boxes = objects.single.characterBoxes;
      expect(boxes, hasLength(2));
      expect(
        boxes[0].bounds.right - boxes[0].bounds.left,
        greaterThan(2 * (boxes[1].bounds.right - boxes[1].bounds.left)),
      );
      expect(boxes[1].start, 1);
    },
  );

  test(
    'insertion invalidates both original and expanded native text bounds',
    () async {
      final file = await PdfTextFixture.singleBlock('Hi');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      final before = (await session.inspectTextBlocks(
        sourceRevision: 'source',
        pageNumbers: [1],
      )).single;
      final locator = const LivePdfiumImportManifestBuilder()
          .build(sourceFingerprint: 'source', blocks: [before])
          .bindings
          .single
          .locator;
      final result = await session.apply(
        LivePdfiumEditPlan(
          replacements: [
            LivePdfiumTextReplacement(
              locator: locator,
              replacement: 'Hello much longer text',
            ),
          ],
        ),
      );
      final after = (await session.inspectTextBlocks(
        sourceRevision: 'source',
        pageNumbers: [1],
      )).single;
      expect(
        result.invalidations.any(
          (tile) => tile.bounds.right >= after.bounds.right,
        ),
        isTrue,
      );
      expect(
        result.invalidations.any(
          (tile) => tile.bounds.left <= before.bounds.left,
        ),
        isTrue,
      );
    },
  );

  test(
    'a seeded session accepts a plan prepared at the seed revision',
    () async {
      final file = await PdfTextFixture.singleBlock('Before');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      final blocks = await session.inspectTextBlocks(
        sourceRevision: 'source',
        pageNumbers: const <int>[1],
      );
      final locator = const LivePdfiumImportManifestBuilder()
          .build(sourceFingerprint: 'source', blocks: blocks)
          .bindings
          .single
          .locator;

      session.seedRevision(3);
      final result = await session.apply(
        LivePdfiumEditPlan(
          replacements: <LivePdfiumTextReplacement>[
            LivePdfiumTextReplacement(locator: locator, replacement: 'x'),
          ],
          expectedRevision: 3,
          revision: 4,
        ),
      );

      expect(result.revision, 4);
      expect(session.appliedRevision, 4);
    },
  );

  test(
    'acknowledgeRevision advances the revision and rejects receding values',
    () async {
      final file = await PdfTextFixture.singleBlock('Before');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);

      session.acknowledgeRevision(2);

      expect(session.appliedRevision, 2);
      expect(() => session.acknowledgeRevision(1), throwsStateError);
    },
  );

  test('renders a page rectangle from its live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Live tile');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);

    final tile = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 120,
        height: 160,
      ),
    );

    expect(tile.width, 120);
    expect(tile.height, 160);
    expect(tile.rgbaBytes, hasLength(120 * 160 * 4));
    expect(tile.rgbaBytes.any((channel) => channel != 255), isTrue);
  });

  test('inspects text from its owned live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Live import text');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);

    final blocks = await session.inspectTextBlocks(
      sourceRevision: 'source-revision',
      pageNumbers: const <int>[1],
    );

    expect(blocks, hasLength(1));
    expect(blocks.single.text, 'Live import text');
    expect(blocks.single.locator.sourceRevision, 'source-revision');
    expect(blocks.single.locator.objectPath, isNotEmpty);
  });

  test('builds a path-based manifest from a live PDFium inspection', () async {
    final file = await PdfTextFixture.singleBlock('Live import text');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    final blocks = await session.inspectTextBlocks(
      sourceRevision: 'ignored-by-live-manifest',
      pageNumbers: const <int>[1],
    );
    final inspected = blocks.single;
    final singleObject = PdfTextBlock(
      locator: inspected.locator,
      text: inspected.text,
      originalText: inspected.originalText,
      runs: inspected.runs,
      bounds: inspected.bounds,
      transform: inspected.transform,
      baseline: inspected.baseline,
      writingDirection: inspected.writingDirection,
      capabilities: inspected.capabilities.toList(growable: false),
      readOnlyReason: inspected.readOnlyReason,
      objectPaths: <List<int>>[inspected.locator.objectPath],
    );

    final manifest = const LivePdfiumImportManifestBuilder().build(
      sourceFingerprint: 'source',
      blocks: <PdfTextBlock>[singleObject],
    );

    expect(manifest.bindings, hasLength(1));
    final binding = manifest.bindings.single;
    expect(binding.sourceKey, 'source/live-pdfium/page/1/object/0');
    expect(binding.locator.objectPath, <int>[0]);
    expect(binding.objectId, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('applies sequential replacements across a multi-object block', () async {
    final file = await PdfTextFixture.multiObjectBlock();
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);

    final blocks = await session.inspectTextBlocks(
      sourceRevision: 'source',
      pageNumbers: const <int>[1],
    );
    final block = blocks.single;
    expect(block.objectPaths.length, greaterThan(1));
    expect(block.text, 'Hello world');

    final manifest = const LivePdfiumImportManifestBuilder().build(
      sourceFingerprint: 'source',
      blocks: <PdfTextBlock>[block],
    );
    final locator = manifest.bindings.single.locator;

    // First edit: intra-block replacement keeps the separator in place.
    await session.apply(
      LivePdfiumEditPlan(
        replacements: <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(
            locator: locator,
            replacement: 'Bye world',
            expectedText: 'Hello world',
          ),
        ],
        revision: 1,
      ),
    );
    var after = await session.inspectTextBlocks(
      sourceRevision: 'source',
      pageNumbers: const <int>[1],
    );
    expect(after.single.text.trimRight(), 'Bye world');

    // Second edit through the same locator: deleting the separator collapses
    // into the first object and pins the trailing object with a space anchor.
    await session.apply(
      LivePdfiumEditPlan(
        replacements: <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(
            locator: locator,
            replacement: 'Bye',
            expectedText: 'Bye world',
          ),
        ],
        revision: 2,
      ),
    );
    after = await session.inspectTextBlocks(
      sourceRevision: 'source',
      pageNumbers: const <int>[1],
    );
    expect(after.single.text.trimRight(), 'Bye');
    expect(after.single.objectPaths.length, greaterThan(1));
  });

  test(
    'regenerating changed page content updates a live PDFium tile',
    () async {
      final file = await PdfTextFixture.singleBlock('Original');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      const beforeRequest = LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      );
      final before = await session.renderTile(beforeRequest);

      await session.replaceTextObject(
        const EditorPhysicalLocator(
          pageNumber: 1,
          objectPath: <int>[0],
          objectType: 'text',
          sourceFingerprint: 'fixture',
          objectRevision: 0,
        ),
        'Changed',
      );
      final after = await session.renderTile(
        const LivePdfiumTileRequest(
          pageNumber: 1,
          revision: 1,
          bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
          width: 240,
          height: 320,
        ),
      );

      expect(after.rgbaBytes, isNot(orderedEquals(before.rgbaBytes)));
    },
  );

  test(
    'regenerates each live text mutation before its page handle closes',
    () async {
      final file = await PdfTextFixture.singleBlock('Original');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      const locator = EditorPhysicalLocator(
        pageNumber: 1,
        objectPath: <int>[0],
        objectType: 'text',
        sourceFingerprint: 'fixture',
        objectRevision: 0,
      );

      await session.replaceTextObject(locator, 'First');
      await session.replaceTextObject(locator, 'Final');
      final committed = await session.commit();

      expect(committed, isEmpty);
      expect(await session.commit(), isEmpty);
    },
  );

  test('applies a same-page text plan in one live revision', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    final result = await session.apply(
      LivePdfiumEditPlan(
        replacements: const <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(locator: locator, replacement: 'First'),
          LivePdfiumTextReplacement(locator: locator, replacement: 'Final'),
        ],
      ),
    );

    expect(result.revision, 1);
    expect(result.invalidations, hasLength(2));
    expect(result.invalidations.every((item) => item.pageNumber == 1), isTrue);
  });

  test('rejects a plan prepared for a different live revision', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    await expectLater(
      session.apply(
        LivePdfiumEditPlan(
          expectedRevision: 1,
          revision: 2,
          replacements: const <LivePdfiumTextReplacement>[
            LivePdfiumTextReplacement(locator: locator, replacement: 'Changed'),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a physical edit plan that spans pages', () {
    const pageOne = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );
    const pageTwo = EditorPhysicalLocator(
      pageNumber: 2,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    expect(
      () => LivePdfiumEditPlan(
        replacements: const <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(locator: pageOne, replacement: 'One'),
          LivePdfiumTextReplacement(locator: pageTwo, replacement: 'Two'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rejects a stale text plan before mutating its live object', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );
    final before = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      ),
    );

    await expectLater(
      session.apply(
        LivePdfiumEditPlan(
          replacements: const <LivePdfiumTextReplacement>[
            LivePdfiumTextReplacement(
              locator: locator,
              replacement: 'Changed',
              expectedText: 'Different source text',
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    final after = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 1,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      ),
    );
    expect(after.rgbaBytes, orderedEquals(before.rgbaBytes));
  });

  test('saves committed text through the live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const tileRequest = LivePdfiumTileRequest(
      pageNumber: 1,
      revision: 0,
      bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
      width: 240,
      height: 320,
    );
    final originalTile = await session.renderTile(tileRequest);
    await session.replaceTextObject(
      const EditorPhysicalLocator(
        pageNumber: 1,
        objectPath: <int>[0],
        objectType: 'text',
        sourceFingerprint: 'fixture',
        objectRevision: 0,
      ),
      'Persisted',
    );

    final saved = await session.saveBytes();
    expect(saved, hasLength(greaterThan(64)));
    expect(String.fromCharCodes(saved.take(5)), '%PDF-');
    final savedFile = File('${file.parent.path}/persisted.pdf');
    await savedFile.writeAsBytes(saved, flush: true);
    final reopened = await LivePdfiumSession.open(savedFile.path);
    addTearDown(reopened.close);
    final persistedTile = await reopened.renderTile(tileRequest);
    expect(
      persistedTile.rgbaBytes,
      isNot(orderedEquals(originalTile.rgbaBytes)),
    );
  });
}
