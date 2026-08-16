import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../domain/editor_selection.dart';
import 'editor_text_painter.dart';

class EditorGlyphAnchor {
  const EditorGlyphAnchor({
    required this.bounds,
    required this.utf16Offset,
    this.affinity = EditorSelectionAffinity.downstream,
    this.legal = true,
  });

  final EditorPdfBox bounds;
  final int utf16Offset;
  final EditorSelectionAffinity affinity;
  final bool legal;
}

class EditorObjectHitGeometry {
  const EditorObjectHitGeometry({required this.object, required this.anchors});

  factory EditorObjectHitGeometry.fromObject(EditorSceneObject object) {
    final direction = object.layout?.direction;
    final anchors = <EditorGlyphAnchor>[];
    for (final character in object.characterBoxes) {
      final bounds = character.bounds;
      switch (direction) {
        case 'righttoleft':
          anchors
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.right,
                  bottom: bounds.bottom,
                  right: bounds.right,
                  top: bounds.top,
                ),
                utf16Offset: character.start,
              ),
            )
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.left,
                  bottom: bounds.bottom,
                  right: bounds.left,
                  top: bounds.top,
                ),
                utf16Offset: character.end,
                affinity: EditorSelectionAffinity.upstream,
              ),
            );
        case 'toptobottom':
          anchors
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.left,
                  bottom: bounds.top,
                  right: bounds.right,
                  top: bounds.top,
                ),
                utf16Offset: character.start,
              ),
            )
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.left,
                  bottom: bounds.bottom,
                  right: bounds.right,
                  top: bounds.bottom,
                ),
                utf16Offset: character.end,
                affinity: EditorSelectionAffinity.upstream,
              ),
            );
        default:
          anchors
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.left,
                  bottom: bounds.bottom,
                  right: bounds.left,
                  top: bounds.top,
                ),
                utf16Offset: character.start,
              ),
            )
            ..add(
              EditorGlyphAnchor(
                bounds: EditorPdfBox(
                  left: bounds.right,
                  bottom: bounds.bottom,
                  right: bounds.right,
                  top: bounds.top,
                ),
                utf16Offset: character.end,
                affinity: EditorSelectionAffinity.upstream,
              ),
            );
      }
    }
    return EditorObjectHitGeometry(
      object: object,
      anchors: List<EditorGlyphAnchor>.unmodifiable(anchors),
    );
  }

  final EditorSceneObject object;
  final List<EditorGlyphAnchor> anchors;
}

class EditorHitTestResult {
  const EditorHitTestResult({
    required this.objectId,
    required this.utf16Offset,
    required this.affinity,
    required this.distanceSquared,
  });

  final String objectId;
  final int utf16Offset;
  final EditorSelectionAffinity affinity;
  final double distanceSquared;
}

class EditorHitTestIndex {
  EditorHitTestIndex({
    required this.pageSize,
    required this.displaySize,
    required Iterable<EditorObjectHitGeometry> objects,
  }) : _objects = List<EditorObjectHitGeometry>.unmodifiable(objects);

  final Size pageSize;
  final Size displaySize;
  final List<EditorObjectHitGeometry> _objects;

  EditorHitTestResult? hitTest(Offset localPosition, {bool forEditing = true}) {
    EditorHitTestResult? nearest;
    for (final geometry in _objects) {
      if (forEditing && geometry.object.capability != 'editable') continue;
      for (final anchor in geometry.anchors) {
        if (!anchor.legal) continue;
        final center = Offset(
          (anchor.bounds.left + anchor.bounds.right) / 2,
          (anchor.bounds.bottom + anchor.bounds.top) / 2,
        );
        final transformed = _transform(center, geometry.object.transform);
        final local = EditorPageGeometry.pointForPdf(
          transformed,
          pageSize: pageSize,
          displaySize: displaySize,
        );
        final dx = local.dx - localPosition.dx;
        final dy = local.dy - localPosition.dy;
        final distance = dx * dx + dy * dy;
        if (nearest == null || distance < nearest.distanceSquared) {
          nearest = EditorHitTestResult(
            objectId: geometry.object.objectId,
            utf16Offset: anchor.utf16Offset,
            affinity: anchor.affinity,
            distanceSquared: distance,
          );
        }
      }
    }
    return nearest;
  }
}

Offset _transform(Offset point, EditorAffineTransform transform) => Offset(
  transform.a * point.dx + transform.c * point.dy + transform.e,
  transform.b * point.dx + transform.d * point.dy + transform.f,
);
