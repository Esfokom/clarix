import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_document_state.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/workspace/editing/presentation/clean_patch_layer.dart';
import 'package:clarix/src/features/workspace/editing/presentation/page_edit_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'retained overlays cover DPI zoom rotation direction and chrome matrix',
    (tester) async {
      final image = (await tester.runAsync(_whitePatch))!;
      final scenarios = <({int dpi, double zoom, bool dark})>[
        (dpi: 96, zoom: .75, dark: false),
        (dpi: 144, zoom: 1, dark: false),
        (dpi: 192, zoom: 2, dark: false),
        (dpi: 96, zoom: .75, dark: true),
        (dpi: 144, zoom: 1, dark: true),
        (dpi: 192, zoom: 2, dark: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: const Color(0xff808080),
            child: Center(
              child: RepaintBoundary(
                key: const Key('page-edit-scene-golden'),
                child: SizedBox(
                  width: 840,
                  height: 360,
                  child: Wrap(
                    children: <Widget>[
                      for (final scenario in scenarios)
                        _scenario(
                          image: image,
                          dpi: scenario.dpi,
                          zoom: scenario.zoom,
                          dark: scenario.dark,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final previousComparator = goldenFileComparator;
      goldenFileComparator = _TolerantGoldenComparator(
        Uri.base.resolve(
          'test/workspace_editing/page_edit_scene_golden_test.dart',
        ),
        precisionTolerance: .01,
      );
      addTearDown(() => goldenFileComparator = previousComparator);

      await expectLater(
        find.byKey(const Key('page-edit-scene-golden')),
        matchesGoldenFile('goldens/page_edit_scene_matrix.png'),
      );
      image.dispose();
    },
  );
}

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(
    super.testFile, {
    required this._precisionTolerance,
  });

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final passed = result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Widget _scenario({
  required ui.Image image,
  required int dpi,
  required double zoom,
  required bool dark,
}) {
  final scene = _scene();
  final displaySize = Size(200 * zoom, 120 * zoom);
  return SizedBox(
    width: 280,
    height: 180,
    child: ColoredBox(
      color: dark ? const Color(0xff202124) : const Color(0xffe8eaed),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: ClipRect(
            child: PageEditScene(
              scene: scene,
              document: _document(),
              displaySize: displaySize,
              composition: const EditorCompositionRange(
                objectId: 'latin',
                range: EditorTextRange(start: 1, end: 4),
              ),
              cleanPatches: <String, CleanPatchAsset>{
                for (final object in scene.objects)
                  object.objectId: CleanPatchAsset(
                    handle: '${object.objectId}-$dpi',
                    objectId: object.objectId,
                    bounds: object.bounds,
                    dpi: dpi,
                    bleedPoints: 1,
                    image: image,
                  ),
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Future<ui.Image> _whitePatch() async {
  final asset = await CleanPatchDecoder.decodeRgba(
    handle: 'golden',
    objectId: 'golden',
    bounds: const EditorPdfBox(left: 0, bottom: 0, right: 1, top: 1),
    dpi: 144,
    bleedPoints: 0,
    width: 2,
    height: 2,
    rgbaBytes: Uint8List.fromList(List<int>.filled(16, 255)),
  );
  return asset.image;
}

EditorPageScene _scene() => EditorPageScene(
  schemaVersion: 1,
  pageId: 'golden-page',
  pageNumber: 1,
  width: 200,
  height: 120,
  revision: 1,
  objects: <EditorSceneObject>[
    _object(
      id: 'latin',
      text: 'Clarix',
      bounds: const EditorPdfBox(left: 16, bottom: 72, right: 95, top: 96),
      direction: 'ltr',
      transform: const EditorAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        e: 0,
        f: 0,
      ),
    ),
    _object(
      id: 'rtl',
      text: 'مرحبا',
      bounds: const EditorPdfBox(left: 105, bottom: 28, right: 184, top: 56),
      direction: 'rtl',
      transform: EditorAffineTransform(
        a: math.cos(.12),
        b: math.sin(.12),
        c: -math.sin(.12),
        d: math.cos(.12),
        e: 0,
        f: 0,
      ),
    ),
  ],
);

EditorSceneObject _object({
  required String id,
  required String text,
  required EditorPdfBox bounds,
  required String direction,
  required EditorAffineTransform transform,
}) => EditorSceneObject(
  kind: EditorSceneObjectKind.text,
  objectId: id,
  pageId: 'golden-page',
  text: text,
  bounds: bounds,
  transform: transform,
  capability: 'editable',
  modifiedRevision: 1,
  runs: <EditorTextRun>[
    EditorTextRun(
      start: 0,
      end: text.codeUnits.length,
      style: const EditorTextStyle(
        fontSize: 13,
        fontWeight: 400,
        italic: false,
        colorRgba: <int>[20, 20, 20, 255],
      ),
    ),
  ],
  layout: EditorTextLayoutRecipe(
    baseline: 13,
    lineHeight: 16,
    characterSpacing: 0,
    horizontalScale: 1,
    direction: direction,
  ),
);

EditorDocumentState _document() => EditorDocumentState(
  revision: 1,
  objects: const <String, EditorObjectState>{
    'latin': EditorObjectState(
      objectId: 'latin',
      pageId: 'golden-page',
      acceptedText: 'Clarix',
      modifiedRevision: 1,
    ),
    'rtl': EditorObjectState(
      objectId: 'rtl',
      pageId: 'golden-page',
      acceptedText: 'مرحبا',
      modifiedRevision: 1,
    ),
  },
  selection: const EditorSelection(
    objectId: 'latin',
    range: EditorTextRange(start: 3, end: 3),
  ),
);
