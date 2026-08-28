import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/presentation/editor_hit_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

EditorSceneObject _object({
  required String text,
  required EditorPdfBox bounds,
  List<EditorTextCharacterBox> characterBoxes = const <EditorTextCharacterBox>[],
}) => EditorSceneObject(
  kind: EditorSceneObjectKind.text,
  objectId: 'object-1',
  pageId: 'page-1',
  text: text,
  bounds: bounds,
  transform: const EditorAffineTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0),
  capability: 'editable',
  modifiedRevision: 0,
  runs: const <EditorTextRun>[],
  characterBoxes: characterBoxes,
);

void main() {
  test('synthesizes proportional anchors when character boxes are missing', () {
    final geometry = EditorObjectHitGeometry.fromObject(
      _object(
        text: 'Abc',
        bounds: const EditorPdfBox(left: 0, bottom: 0, right: 120, top: 20),
      ),
    );
    final index = EditorHitTestIndex(
      pageSize: const Size(120, 20),
      displaySize: const Size(120, 20),
      objects: <EditorObjectHitGeometry>[geometry],
    );

    final first = index.hitTest(const Offset(20, 10));
    final middle = index.hitTest(const Offset(60, 10));
    final last = index.hitTest(const Offset(100, 10));

    expect(first, isNotNull);
    expect(first!.utf16Offset, 0);
    expect(middle!.utf16Offset, 1);
    expect(last!.utf16Offset, 2);
  });

  test('skips newline characters when synthesizing anchors', () {
    final geometry = EditorObjectHitGeometry.fromObject(
      _object(
        text: 'a\nb',
        bounds: const EditorPdfBox(left: 0, bottom: 0, right: 100, top: 20),
      ),
    );
    final index = EditorHitTestIndex(
      pageSize: const Size(100, 20),
      displaySize: const Size(100, 20),
      objects: <EditorObjectHitGeometry>[geometry],
    );

    // The newline consumes no width: the box for 'b' (offset 2) starts at the
    // halfway point, and every boundary offset of the visible characters is
    // represented.
    final startOfB = geometry.anchors.firstWhere(
      (anchor) => anchor.utf16Offset == 2,
    );
    expect(startOfB.bounds.left, 50);
    final offsets = geometry.anchors
        .map((anchor) => anchor.utf16Offset)
        .toSet();
    expect(offsets, containsAll(<int>[0, 1, 2, 3]));

    final first = index.hitTest(const Offset(10, 10));
    final endOfB = index.hitTest(const Offset(90, 10));
    expect(first!.utf16Offset, 0);
    expect(endOfB!.utf16Offset, 3);
  });

  test('leaves objects with real character boxes unchanged', () {
    final geometry = EditorObjectHitGeometry.fromObject(
      _object(
        text: 'Abc',
        bounds: const EditorPdfBox(left: 0, bottom: 0, right: 120, top: 20),
        characterBoxes: const <EditorTextCharacterBox>[
          EditorTextCharacterBox(
            start: 0,
            end: 1,
            bounds: EditorPdfBox(left: 0, bottom: 0, right: 40, top: 20),
          ),
        ],
      ),
    );

    // Only the single real box contributes anchors (start + end), not a
    // synthesized box per character.
    expect(geometry.anchors, hasLength(2));
  });

  test('an empty object produces no anchors', () {
    final geometry = EditorObjectHitGeometry.fromObject(
      _object(
        text: '',
        bounds: const EditorPdfBox(left: 0, bottom: 0, right: 120, top: 20),
      ),
    );

    expect(geometry.anchors, isEmpty);
  });
}
