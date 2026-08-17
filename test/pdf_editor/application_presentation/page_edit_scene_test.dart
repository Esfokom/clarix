import 'dart:typed_data';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_document_state.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/presentation/clean_patch_layer.dart';
import 'package:clarix/src/features/pdf_editor/presentation/editor_hit_test.dart';
import 'package:clarix/src/features/pdf_editor/presentation/editor_text_painter.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_edit_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edited source is covered before replacement glyphs paint', (
    tester,
  ) async {
    final patch = (await tester.runAsync(() => _patch('object-1')))!;
    final observer = RecordingLayerObserver();
    await tester.pumpWidget(
      _harness(
        scene: _scene(1),
        document: _document(1, selectedObject: 'object-1'),
        patches: <String, CleanPatchAsset>{'object-1': patch},
        observer: observer,
      ),
    );

    expect(observer.layers, <String>[
      'clean-patch',
      'text-object',
      'selection-chrome',
    ]);
    patch.image.dispose();
  });

  testWidgets('typing repaints only the active object boundary', (
    tester,
  ) async {
    final scene = _scene(3);
    final patches = <String, CleanPatchAsset>{};
    for (var index = 1; index <= 3; index++) {
      patches['object-$index'] = (await tester.runAsync(
        () => _patch('object-$index'),
      ))!;
    }
    final document = ValueNotifier<EditorDocumentState>(
      _document(3, selectedObject: 'object-2'),
    );
    final observer = RecordingLayerObserver();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: <Widget>[
                const RepaintBoundary(child: ColoredBox(color: Colors.white)),
                ValueListenableBuilder<EditorDocumentState>(
                  valueListenable: document,
                  builder: (context, value, _) => PageEditScene(
                    scene: scene,
                    document: value,
                    displaySize: const Size(300, 200),
                    cleanPatches: patches,
                    observer: observer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    observer.clear();

    document.value = _document(
      3,
      selectedObject: 'object-2',
      optimistic: const OptimisticTextEdit(
        commandId: 'command',
        objectId: 'object-2',
        range: EditorTextRange(start: 0, end: 6),
        replacement: 'Changed',
        baseRevision: 1,
      ),
    );
    await tester.pump();

    expect(observer.count('text-object', 'object-1'), 0);
    expect(observer.count('text-object', 'object-2'), greaterThan(0));
    expect(observer.count('text-object', 'object-3'), 0);
    expect(observer.count('clean-patch', 'object-1'), 0);
    expect(observer.count('clean-patch', 'object-2'), 0);

    document.dispose();
    for (final patch in patches.values) {
      patch.image.dispose();
    }
  });

  test(
    'hit testing chooses legal anchors and excludes read-only edit entry',
    () {
      final editable = _object(1);
      final readOnly = _object(2, capability: 'read_only');
      final index = EditorHitTestIndex(
        pageSize: const Size(100, 100),
        displaySize: const Size(100, 100),
        objects: <EditorObjectHitGeometry>[
          EditorObjectHitGeometry(
            object: editable,
            anchors: const <EditorGlyphAnchor>[
              EditorGlyphAnchor(
                bounds: EditorPdfBox(left: 9, bottom: 89, right: 11, top: 91),
                utf16Offset: 2,
              ),
            ],
          ),
          EditorObjectHitGeometry(
            object: readOnly,
            anchors: const <EditorGlyphAnchor>[
              EditorGlyphAnchor(
                bounds: EditorPdfBox(left: 19, bottom: 79, right: 21, top: 81),
                utf16Offset: 4,
              ),
              EditorGlyphAnchor(
                bounds: EditorPdfBox(left: 20, bottom: 80, right: 20, top: 80),
                utf16Offset: 3,
                legal: false,
              ),
            ],
          ),
        ],
      );

      expect(index.hitTest(const Offset(20, 20))?.objectId, 'object-1');
      expect(
        index.hitTest(const Offset(20, 20), forEditing: false)?.objectId,
        'object-2',
      );
    },
  );

  test('hit testing follows nonuniform imported character geometry', () {
    final object = EditorSceneObject(
      kind: EditorSceneObjectKind.text,
      objectId: 'geometry-object',
      pageId: 'page-1',
      text: 'AB',
      bounds: const EditorPdfBox(left: 0, bottom: 40, right: 100, top: 60),
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
      runs: const <EditorTextRun>[],
      characterBoxes: const <EditorTextCharacterBox>[
        EditorTextCharacterBox(
          start: 0,
          end: 1,
          bounds: EditorPdfBox(left: 0, bottom: 40, right: 90, top: 60),
        ),
        EditorTextCharacterBox(
          start: 1,
          end: 2,
          bounds: EditorPdfBox(left: 90, bottom: 40, right: 100, top: 60),
        ),
      ],
      layout: const EditorTextLayoutRecipe(
        baseline: 50,
        lineHeight: 20,
        characterSpacing: 0,
        horizontalScale: 1,
        direction: 'lefttoright',
      ),
    );
    final index = EditorHitTestIndex(
      pageSize: const Size(100, 100),
      displaySize: const Size(100, 100),
      objects: <EditorObjectHitGeometry>[
        EditorObjectHitGeometry.fromObject(object),
      ],
    );

    expect(index.hitTest(const Offset(80, 50))?.utf16Offset, 1);
    expect(index.hitTest(const Offset(98, 50))?.utf16Offset, 2);
  });

  testWidgets('higher-DPI patch replaces pixels without changing geometry', (
    tester,
  ) async {
    final low = (await tester.runAsync(() => _patch('object-1', dpi: 96)))!;
    final high = (await tester.runAsync(() => _patch('object-1', dpi: 192)))!;
    final patch = ValueNotifier<CleanPatchAsset>(low);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<CleanPatchAsset>(
          valueListenable: patch,
          builder: (context, value, _) => CleanPatchLayer(
            asset: value,
            pageSize: const Size(300, 200),
            displaySize: const Size(300, 200),
          ),
        ),
      ),
    );
    final before = tester.getRect(
      find.byKey(const ValueKey<String>('clean-patch-object-1')),
    );
    patch.value = high;
    await tester.pump();
    final after = tester.getRect(
      find.byKey(const ValueKey<String>('clean-patch-object-1')),
    );

    expect(after, before);
    patch.dispose();
    low.image.dispose();
    high.image.dispose();
  });
}

Widget _harness({
  required EditorPageScene scene,
  required EditorDocumentState document,
  required Map<String, CleanPatchAsset> patches,
  required EditorLayerObserver observer,
}) => MaterialApp(
  home: Center(
    child: PageEditScene(
      scene: scene,
      document: document,
      displaySize: const Size(300, 200),
      cleanPatches: patches,
      observer: observer,
    ),
  ),
);

Future<CleanPatchAsset> _patch(String objectId, {int dpi = 144}) =>
    CleanPatchDecoder.decodeRgba(
      handle: '$objectId-$dpi',
      objectId: objectId,
      bounds: _object(int.parse(objectId.split('-').last)).bounds,
      dpi: dpi,
      bleedPoints: 1,
      width: 2,
      height: 2,
      rgbaBytes: Uint8List.fromList(const <int>[
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
      ]),
    );

EditorPageScene _scene(int objectCount) => EditorPageScene(
  schemaVersion: 1,
  pageId: 'page-1',
  pageNumber: 1,
  width: 300,
  height: 200,
  revision: 1,
  objects: List<EditorSceneObject>.generate(
    objectCount,
    (index) => _object(index + 1),
  ),
);

EditorDocumentState _document(
  int objectCount, {
  required String selectedObject,
  OptimisticTextEdit? optimistic,
}) => EditorDocumentState(
  revision: 1,
  objects: <String, EditorObjectState>{
    for (var index = 1; index <= objectCount; index++)
      'object-$index': EditorObjectState(
        objectId: 'object-$index',
        pageId: 'page-1',
        acceptedText: 'Before',
        modifiedRevision: 1,
      ),
  },
  optimisticEdit: optimistic,
  selection: EditorSelection(
    objectId: selectedObject,
    range: const EditorTextRange(start: 3, end: 3),
  ),
);

EditorSceneObject _object(int index, {String capability = 'editable'}) {
  final left = 20.0 + (index - 1) * 85;
  return EditorSceneObject(
    kind: EditorSceneObjectKind.text,
    objectId: 'object-$index',
    pageId: 'page-1',
    text: 'Before',
    bounds: EditorPdfBox(left: left, bottom: 120, right: left + 70, top: 145),
    transform: const EditorAffineTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0),
    capability: capability,
    modifiedRevision: 1,
    runs: const <EditorTextRun>[
      EditorTextRun(
        start: 0,
        end: 6,
        style: EditorTextStyle(
          fontFamily: 'Arial',
          fontSize: 12,
          fontWeight: 400,
          italic: false,
          colorRgba: <int>[0, 0, 0, 255],
        ),
      ),
    ],
    layout: const EditorTextLayoutRecipe(
      baseline: 12,
      lineHeight: 14,
      characterSpacing: 0,
      horizontalScale: 1,
      direction: 'ltr',
    ),
  );
}

class RecordingLayerObserver implements EditorLayerObserver {
  final List<({String layer, String? objectId})> records =
      <({String layer, String? objectId})>[];

  List<String> get layers => records.map((record) => record.layer).toList();

  int count(String layer, String objectId) => records
      .where((record) => record.layer == layer && record.objectId == objectId)
      .length;

  void clear() => records.clear();

  @override
  void layerPainted(String layer, {String? objectId}) {
    records.add((layer: layer, objectId: objectId));
  }
}
