import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import '../application/editor_session_presentation_state.dart';
import '../domain/editor_document_state.dart';
import '../domain/editor_selection.dart';
import 'clean_patch_layer.dart';
import 'editor_hit_test.dart';
import 'editor_text_painter.dart';
import 'font_fallback_dialog.dart';
import 'live_pdfium_tile_layer.dart';
import 'native_text_editor.dart';
import 'object_transform_handles.dart';
import 'overflow_indicator.dart';

typedef PageSelectionActionsBuilder =
    Widget Function(
      BuildContext context,
      EditorSelection selection,
      EditorSceneObject object,
      int pageNumber,
    );

typedef PageOverlayBuilder =
    Widget? Function(BuildContext context, int pageNumber);

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
    this.liveTiles = const <LivePdfiumTileAsset>[],
    this.session,
    this.editingEnabled = false,
    this.composition,
    this.observer,
    this.selectionActionsBuilder,
    this.pageOverlayBuilder,
    super.key,
  });

  final EditorPageScene scene;
  final EditorDocumentState document;
  final Size displaySize;
  final Map<String, CleanPatchAsset> cleanPatches;
  final List<LivePdfiumTileAsset> liveTiles;
  final EditorSessionController? session;

  /// The native session may have already inspected the PDF.  It must not
  /// capture the page or expose editable controls until the user enters text
  /// editing mode.
  final bool editingEnabled;
  final EditorCompositionRange? composition;
  final EditorLayerObserver? observer;
  final PageSelectionActionsBuilder? selectionActionsBuilder;
  final PageOverlayBuilder? pageOverlayBuilder;

  @override
  Widget build(BuildContext context) {
    final activeSession = editingEnabled ? session : null;
    final pageSize = Size(scene.width, scene.height);
    final interactive = scene.objects
        .where((object) => object.capability == 'editable')
        .toList(growable: false);
    final hitTestIndex = EditorHitTestIndex(
      pageSize: pageSize,
      displaySize: displaySize,
      objects: interactive.map(EditorObjectHitGeometry.fromObject),
    );
    final selection = document.selection;
    final activeObject = activeSession == null || selection == null
        ? null
        : interactive
              .where((object) => object.objectId == selection.objectId)
              .firstOrNull;
    final edited = scene.objects
        .where((object) => _isEdited(object.objectId))
        .toList(growable: false);
    final overlayObjects = <EditorSceneObject>[
      ...edited,
      if (activeObject != null &&
          !edited.any((object) => object.objectId == activeObject.objectId))
        activeObject,
    ];
    final usesLivePdfiumTiles = liveTiles.isNotEmpty;
    final fallbackProposal = document.fontFallbackProposal;
    final showFallbackProposal =
        activeSession != null &&
        fallbackProposal != null &&
        scene.objects.any(
          (object) => object.objectId == fallbackProposal.objectId,
        );
    final Widget? selectionActions =
        activeObject != null &&
            selection != null &&
            selection.range.end > selection.range.start
        ? selectionActionsBuilder?.call(
            context,
            selection,
            activeObject,
            scene.pageNumber,
          )
        : null;
    final Widget? pageOverlay = pageOverlayBuilder?.call(
      context,
      scene.pageNumber,
    );
    return KeyedSubtree(
      key: ValueKey<String>('${scene.pageId}:${scene.revision}'),
      child: SizedBox.fromSize(
        size: displaySize,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (usesLivePdfiumTiles)
              LivePdfiumTileLayer(
                tiles: liveTiles,
                pageSize: pageSize,
                displaySize: displaySize,
              ),
            for (final object in overlayObjects)
              if (!usesLivePdfiumTiles)
                if (cleanPatches.containsKey(object.objectId))
                  CleanPatchLayer(
                    asset: cleanPatches[object.objectId]!,
                    pageSize: pageSize,
                    displaySize: displaySize,
                    observer: observer,
                  )
                else
                  Positioned.fromRect(
                    rect: EditorPageGeometry.rectForBox(
                      object.bounds,
                      pageSize: pageSize,
                      displaySize: displaySize,
                      bleedPoints: 1.0,
                    ),
                    child: const ColoredBox(color: Color(0xFFFFFFFF)),
                  ),
            for (final object in overlayObjects)
              if (!usesLivePdfiumTiles)
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
            if (activeSession != null)
              for (final object in interactive)
                if (object.objectId != activeObject?.objectId)
                  Positioned.fromRect(
                    rect: EditorPageGeometry.rectForBox(
                      object.bounds,
                      pageSize: pageSize,
                      displaySize: displaySize,
                    ),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0x332F80ED),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
            if (activeSession != null)
              for (final object in interactive)
                if (object.objectId != activeObject?.objectId)
                  Positioned.fromRect(
                    rect: EditorPageGeometry.rectForBox(
                      object.bounds,
                      pageSize: pageSize,
                      displaySize: displaySize,
                    ),
                    child: PdfOverlayInteractionRegion(
                      onTap: (details) {
                        final objectRect = EditorPageGeometry.rectForBox(
                          object.bounds,
                          pageSize: pageSize,
                          displaySize: displaySize,
                        );
                        final hit = hitTestIndex.hitTest(
                          details.localPosition + objectRect.topLeft,
                        );
                        if (hit == null) return false;
                        activeSession.updateSelection(
                          EditorSelection(
                            objectId: hit.objectId,
                            range: EditorTextRange(
                              start: hit.utf16Offset,
                              end: hit.utf16Offset,
                            ),
                            affinity: hit.affinity,
                          ),
                        );
                        return true;
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
            if (activeObject != null &&
                selection != null &&
                activeSession != null)
              Positioned.fromRect(
                rect: EditorPageGeometry.rectForBox(
                  activeObject.bounds,
                  pageSize: pageSize,
                  displaySize: displaySize,
                ),
                child: NativeTextEditor(
                  session: activeSession,
                  object: activeObject,
                  text:
                      document.visibleText(activeObject.objectId) ??
                      activeObject.text ??
                      '',
                  selection: selection,
                  scale: displaySize.width / pageSize.width,
                  onUndo: activeSession.canUndo
                      ? () => unawaited(activeSession.undo())
                      : null,
                  onRedo: activeSession.canRedo
                      ? () => unawaited(activeSession.redo())
                      : null,
                ),
              ),
            if (activeObject != null && activeSession != null)
              ObjectTransformHandles(
                session: activeSession,
                object: activeObject,
                pageSize: pageSize,
                displaySize: displaySize,
              ),
            if (selectionActions != null)
              Align(alignment: Alignment.topCenter, child: selectionActions),
            if (activeSession == null)
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
            if (activeSession != null &&
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
                    onCancel: activeSession.clearError,
                  ),
                ),
              ),
            if (showFallbackProposal)
              Center(
                child: FontFallbackDialog(
                  proposal: fallbackProposal,
                  onApprove: (token) =>
                      unawaited(activeSession.approveFontFallback(token)),
                  onReject: activeSession.rejectFontFallback,
                ),
              ),
            if (pageOverlay != null)
              Align(alignment: Alignment.topRight, child: pageOverlay),
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
