import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../../../../core/agent/agent_bridge_types.dart';
import '../application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'clean_patch_layer.dart';
import 'editor_hit_test.dart';
import 'editor_text_painter.dart';
import 'font_fallback_dialog.dart';
import 'native_text_editor.dart';
import 'object_transform_handles.dart';
import 'overflow_indicator.dart';
import '../../agent/presentation/selection_ai_toolbar.dart';
import '../../agent/presentation/agent_diff_overlay.dart';

typedef PageSelectionAiCallback =
    void Function(
      SelectionAiAction action,
      EditorSelection selection,
      EditorSceneObject object,
      int pageNumber,
    );

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
    this.onSelectionAiAction,
    this.selectionAiSharingEnabled = true,
    this.agentProposal,
    super.key,
  });

  final EditorPageScene scene;
  final EditorDocumentState document;
  final Size displaySize;
  final Map<String, CleanPatchAsset> cleanPatches;
  final EditorSessionController? session;
  final EditorCompositionRange? composition;
  final EditorLayerObserver? observer;
  final PageSelectionAiCallback? onSelectionAiAction;
  final bool selectionAiSharingEnabled;
  final AgentProposal? agentProposal;

  @override
  Widget build(BuildContext context) {
    final pageSize = Size(scene.width, scene.height);
    final interactive = scene.objects
        .where((object) => object.capability == 'editable')
        .where((object) => cleanPatches.containsKey(object.objectId))
        .toList(growable: false);
    final hitTestIndex = EditorHitTestIndex(
      pageSize: pageSize,
      displaySize: displaySize,
      objects: interactive.map(EditorObjectHitGeometry.fromObject),
    );
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
    final fallbackProposal = document.fontFallbackProposal;
    final showFallbackProposal =
        session != null &&
        fallbackProposal != null &&
        scene.objects.any(
          (object) => object.objectId == fallbackProposal.objectId,
        );
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
                        final objectRect = EditorPageGeometry.rectForBox(
                          object.bounds,
                          pageSize: pageSize,
                          displaySize: displaySize,
                        );
                        final hit = hitTestIndex.hitTest(
                          details.localPosition + objectRect.topLeft,
                        );
                        if (hit == null) return;
                        session!.updateSelection(
                          EditorSelection(
                            objectId: hit.objectId,
                            range: EditorTextRange(
                              start: hit.utf16Offset,
                              end: hit.utf16Offset,
                            ),
                            affinity: hit.affinity,
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
                  onUndo: session!.canUndo
                      ? () => unawaited(session!.undo())
                      : null,
                  onRedo: session!.canRedo
                      ? () => unawaited(session!.redo())
                      : null,
                ),
              ),
            if (activeObject != null && session != null)
              ObjectTransformHandles(
                session: session!,
                object: activeObject,
                pageSize: pageSize,
                displaySize: displaySize,
              ),
            if (activeObject != null &&
                selection != null &&
                selection.range.end > selection.range.start &&
                onSelectionAiAction != null)
              Align(
                alignment: Alignment.topCenter,
                child: SelectionAiToolbar(
                  hasValidatedSelection: true,
                  sharingEnabled: selectionAiSharingEnabled,
                  onAction: (action) => onSelectionAiAction!(
                    action,
                    selection,
                    activeObject,
                    scene.pageNumber,
                  ),
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
            if (session != null &&
                document.errorCode == 'text_overflow' &&
                activeObject != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Semantics(
                  liveRegion: true,
                  child: OverflowIndicator(
                    message:
                        'Text does not fit this object. Shorten it or cancel the edit.',
                    canIncreaseBounds: false,
                    onCancel: session!.clearError,
                  ),
                ),
              ),
            if (showFallbackProposal)
              Center(
                child: FontFallbackDialog(
                  proposal: fallbackProposal,
                  onApprove: (token) =>
                      unawaited(session!.approveFontFallback(token)),
                  onReject: session!.rejectFontFallback,
                ),
              ),
            if (agentProposal case final proposal?)
              if (proposal.targets.any(
                (target) => target.pageNumber == scene.pageNumber,
              ))
                Align(
                  alignment: Alignment.topRight,
                  child: AgentDiffOverlay(proposal: proposal),
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
    final caret = _caretSegment(object, selection.range.end);
    canvas.drawLine(caret.$1, caret.$2, outline..strokeWidth = 1.5);
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

  (Offset, Offset) _caretSegment(EditorSceneObject object, int utf16Offset) {
    EditorTextCharacterBox? character;
    var useLeadingEdge = true;
    for (final candidate in object.characterBoxes) {
      if (candidate.start == utf16Offset) {
        character = candidate;
        break;
      }
    }
    if (character == null) {
      for (final candidate in object.characterBoxes.reversed) {
        if (candidate.end == utf16Offset) {
          character = candidate;
          useLeadingEdge = false;
          break;
        }
      }
    }
    final box = character?.bounds ?? object.bounds;
    final direction = object.layout?.direction;
    final (pdfStart, pdfEnd) = switch (direction) {
      'righttoleft' => (
        Offset(useLeadingEdge ? box.right : box.left, box.bottom),
        Offset(useLeadingEdge ? box.right : box.left, box.top),
      ),
      'toptobottom' => (
        Offset(box.left, useLeadingEdge ? box.top : box.bottom),
        Offset(box.right, useLeadingEdge ? box.top : box.bottom),
      ),
      _ => (
        Offset(useLeadingEdge ? box.left : box.right, box.bottom),
        Offset(useLeadingEdge ? box.left : box.right, box.top),
      ),
    };
    return (
      EditorPageGeometry.pointForPdf(
        _transformPoint(pdfStart, object.transform),
        pageSize: pageSize,
        displaySize: displaySize,
      ),
      EditorPageGeometry.pointForPdf(
        _transformPoint(pdfEnd, object.transform),
        pageSize: pageSize,
        displaySize: displaySize,
      ),
    );
  }
}

Offset _transformPoint(Offset point, EditorAffineTransform transform) => Offset(
  transform.a * point.dx + transform.c * point.dy + transform.e,
  transform.b * point.dx + transform.d * point.dy + transform.f,
);
