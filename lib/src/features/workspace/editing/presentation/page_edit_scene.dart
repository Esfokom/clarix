import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import '../domain/editor_document_state.dart';
import '../domain/editor_selection.dart';
import 'clean_patch_layer.dart';
import 'editor_text_painter.dart';
import 'native_text_editor.dart';

class EditorCompositionRange {
  const EditorCompositionRange({required this.objectId, required this.range});

  final String objectId;
  final EditorTextRange range;
}

class PageEditScene extends StatelessWidget {
  const PageEditScene({
    required this.scene,
    required this.document,
    required this.displaySize,
    this.cleanPatches = const <String, CleanPatchAsset>{},
    this.session,
    this.composition,
    this.observer,
    super.key,
  });

  final EditorPageScene scene;
  final EditorDocumentState document;
  final Size displaySize;
  final Map<String, CleanPatchAsset> cleanPatches;
  final EditorSessionController? session;
  final EditorCompositionRange? composition;
  final EditorLayerObserver? observer;

  @override
  Widget build(BuildContext context) {
    final pageSize = Size(scene.width, scene.height);
    final interactive = scene.objects
        .where((object) => object.capability == 'editable')
        .where((object) => cleanPatches.containsKey(object.objectId))
        .toList(growable: false);
    final selection = document.selection;
    final activeObject = session == null || selection == null
        ? null
        : interactive
              .where((object) => object.objectId == selection.objectId)
              .firstOrNull;
    final edited = scene.objects
        .where((object) => _isEdited(object.objectId))
        .where((object) => cleanPatches.containsKey(object.objectId))
        .toList(growable: false);
    final overlayObjects = <EditorSceneObject>[
      ...edited,
      if (activeObject != null &&
          !edited.any((object) => object.objectId == activeObject.objectId))
        activeObject,
    ];
    return KeyedSubtree(
      key: ValueKey<String>('${scene.pageId}:${scene.revision}'),
      child: SizedBox.fromSize(
        size: displaySize,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (final object in overlayObjects)
              CleanPatchLayer(
                asset: cleanPatches[object.objectId]!,
                pageSize: pageSize,
                displaySize: displaySize,
                observer: observer,
              ),
            for (final object in overlayObjects)
              if (object.objectId != activeObject?.objectId)
                EditorTextObjectLayer(
                  object: object,
                  text:
                      document.visibleText(object.objectId) ??
                      object.text ??
                      '',
                  pageSize: pageSize,
                  displaySize: displaySize,
                  observer: observer,
                ),
            if (session != null)
              for (final object in interactive)
                if (object.objectId != activeObject?.objectId)
                  Positioned.fromRect(
                    rect: EditorPageGeometry.rectForBox(
                      object.bounds,
                      pageSize: pageSize,
                      displaySize: displaySize,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final text =
                            document.visibleText(object.objectId) ??
                            object.text ??
                            '';
                        final width = math.max(1.0, details.localPosition.dx);
                        final boxWidth = EditorPageGeometry.rectForBox(
                          object.bounds,
                          pageSize: pageSize,
                          displaySize: displaySize,
                        ).width;
                        final offset =
                            (text.codeUnits.length * width / boxWidth)
                                .round()
                                .clamp(0, text.codeUnits.length);
                        session!.updateSelection(
                          EditorSelection(
                            objectId: object.objectId,
                            range: EditorTextRange(start: offset, end: offset),
                          ),
                        );
                      },
                    ),
                  ),
            if (activeObject != null && selection != null && session != null)
              Positioned.fromRect(
                rect: EditorPageGeometry.rectForBox(
                  activeObject.bounds,
                  pageSize: pageSize,
                  displaySize: displaySize,
                ),
                child: NativeTextEditor(
                  session: session!,
                  object: activeObject,
                  text:
                      document.visibleText(activeObject.objectId) ??
                      activeObject.text ??
                      '',
                  selection: selection,
                  scale: displaySize.width / pageSize.width,
                ),
              ),
            if (session == null)
              if (document.selection case final EditorSelection selection)
                if (edited.any(
                  (object) => object.objectId == selection.objectId,
                ))
                  RepaintBoundary(
                    key: ValueKey<String>('selection-${selection.objectId}'),
                    child: CustomPaint(
                      size: displaySize,
                      painter: _EditorChromePainter(
                        object: edited.firstWhere(
                          (object) => object.objectId == selection.objectId,
                        ),
                        selection: selection,
                        composition: composition,
                        pageSize: pageSize,
                        displaySize: displaySize,
                        observer: observer,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  bool _isEdited(String objectId) {
    final state = document.objects[objectId];
    return state != null &&
        (state.modifiedRevision > 0 ||
            document.optimisticEdit?.objectId == objectId ||
            document.queuedEdit?.objectId == objectId);
  }
}

class _EditorChromePainter extends CustomPainter {
  _EditorChromePainter({
    required this.object,
    required this.selection,
    required this.composition,
    required this.pageSize,
    required this.displaySize,
    required this.observer,
  });

  final EditorSceneObject object;
  final EditorSelection selection;
  final EditorCompositionRange? composition;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;

  @override
  void paint(Canvas canvas, Size size) {
    observer?.layerPainted('selection-chrome', objectId: object.objectId);
    final bounds = EditorPageGeometry.rectForBox(
      object.bounds,
      pageSize: pageSize,
      displaySize: displaySize,
    );
    final outline = Paint()
      ..color = const Color(0xff2f80ed)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(bounds, outline);
    final textLength = math.max(1, object.text?.codeUnits.length ?? 1);
    final caretFraction = selection.range.end.clamp(0, textLength) / textLength;
    final caretX = bounds.left + bounds.width * caretFraction;
    canvas.drawLine(
      Offset(caretX, bounds.top),
      Offset(caretX, bounds.bottom),
      outline..strokeWidth = 1.5,
    );
    if (composition?.objectId == object.objectId) {
      canvas.drawLine(
        Offset(bounds.left, bounds.bottom - 1),
        Offset(bounds.right, bounds.bottom - 1),
        outline..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorChromePainter oldDelegate) =>
      object.objectId != oldDelegate.object.objectId ||
      selection.range.start != oldDelegate.selection.range.start ||
      selection.range.end != oldDelegate.selection.range.end ||
      composition?.range.start != oldDelegate.composition?.range.start ||
      composition?.range.end != oldDelegate.composition?.range.end ||
      displaySize != oldDelegate.displaySize;
}
