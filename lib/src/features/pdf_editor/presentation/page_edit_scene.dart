import 'dart:async';

import 'package:flutter/gestures.dart';
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
import 'object_transform_handles.dart';
import 'overflow_indicator.dart';
import 'session_text_input.dart';

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
        .where((object) => object.kind == EditorSceneObjectKind.text || object.capability == 'editable')
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
    // Only use live tiles when they provide full-page coverage (every
    // editable object on this page has a corresponding tile). Partial
    // invalidation patches must not suppress the base PDF + clean-patch
    // path, otherwise the rest of the page goes blank.
    final editableObjectIds = interactive
        .map((object) => object.objectId)
        .toSet();
    final liveTileCoveredPages = <int>{
      for (final tile in liveTiles) tile.pageNumber,
    };
    final usesLivePdfiumTiles =
        liveTiles.isNotEmpty &&
        liveTileCoveredPages.contains(scene.pageNumber) &&
        liveTiles.length >= editableObjectIds.length;
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
    final bool isEditedOrEditing =
        editingEnabled || document.hasEdits || scene.revision > 0;
    if (!isEditedOrEditing && pageOverlay == null) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: ValueKey<String>('${scene.pageId}:${document.revision}:${document.hasEdits}:${scene.revision}'),
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
            if (cleanPatches.containsKey(object.objectId))
              CleanPatchLayer(
                asset: cleanPatches[object.objectId]!,
                pageSize: pageSize,
                displaySize: displaySize,
                observer: observer,
              )
            else if (_isEdited(object.objectId))
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
            if (object.objectId != activeObject?.objectId)
              EditorTextObjectLayer(
                object: object,
                text: _getVisibleText(object),
                pageSize: pageSize,
                displaySize: displaySize,
                observer: observer,
              ),
            if (activeSession != null)
              for (final object in interactive)
                Positioned.fromRect(
                  rect: EditorPageGeometry.rectForBox(
                    object.bounds,
                    pageSize: pageSize,
                    displaySize: displaySize,
                  ),
                  child: IgnorePointer(
                    child: Semantics(
                      label: 'Editable text region',
                      child: DecoratedBox(
                        key: ValueKey<String>(
                          'clarix-edit-target-${object.objectId}',
                        ),
                        decoration: BoxDecoration(
                          color: object.objectId == activeObject?.objectId
                              ? const Color(0x1A2563EB)
                              : const Color(0x0C2563EB),
                          border: Border.all(
                            color: object.objectId == activeObject?.objectId
                                ? const Color(0xFF2563EB)
                                : const Color(0x802563EB),
                            width: object.objectId == activeObject?.objectId ? 1.5 : 1.2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
            if (activeSession != null)
              for (final object in interactive)
                Positioned.fromRect(
                  rect: EditorPageGeometry.rectForBox(
                    object.bounds,
                    pageSize: pageSize,
                    displaySize: displaySize,
                  ),
                  child: _TapRegion(
                    onTap: (Offset localInBox) {
                      final objectRect = EditorPageGeometry.rectForBox(
                        object.bounds,
                        pageSize: pageSize,
                        displaySize: displaySize,
                      );
                      final hit = hitTestIndex.hitTest(
                        localInBox + objectRect.topLeft,
                      );
                      activeSession.updateSelection(
                        EditorSelection(
                          objectId: hit?.objectId ?? object.objectId,
                          range: EditorTextRange(
                            start: hit?.utf16Offset ?? 0,
                            end: hit?.utf16Offset ?? (object.text?.length ?? 0),
                          ),
                        ),
                      );
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      // The pdfrx region also dispatches the tap when its
                      // registration is current; both paths converge on the
                      // same selection.
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
                  ),
                ),
            if (activeObject != null &&
                selection != null &&
                activeSession != null) ...<Widget>[
              // The caret paints at scene level from PDF character geometry;
              // no text is overlaid — the page keeps rendering the real
              // content in its own fonts.
              Positioned.fill(
                child: IgnorePointer(
                  child: _ActiveObjectCaret(
                    object: activeObject,
                    selection: selection,
                    pageSize: pageSize,
                    displaySize: displaySize,
                    observer: observer,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: EditorPageGeometry.rectForBox(
                  activeObject.bounds,
                  pageSize: pageSize,
                  displaySize: displaySize,
                ),
                child: SessionTextInput(
                  session: activeSession,
                  object: activeObject,
                  text:
                      document.visibleText(activeObject.objectId) ??
                      activeObject.text ??
                      '',
                  selection: selection,
                  onSelectionChanged: (range) {
                    activeSession.updateSelection(
                      EditorSelection(
                        objectId: activeObject.objectId,
                        range: range,
                      ),
                    );
                  },
                  onUndo: activeSession.canUndo
                      ? () => unawaited(activeSession.undo())
                      : null,
                  onRedo: activeSession.canRedo
                      ? () => unawaited(activeSession.redo())
                      : null,
                ),
              ),
            ],
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
      );
  }

  bool _isEdited(String objectId) {
    if (document.optimisticEdit?.objectId == objectId ||
        document.queuedEdit?.objectId == objectId) {
      return true;
    }
    if (document.visibleText(objectId) != null) {
      return true;
    }
    final object =
        scene.objects.where((o) => o.objectId == objectId).firstOrNull;
    if (object != null && object.modifiedRevision > 0) {
      return true;
    }
    final state = document.objects[objectId];
    return state != null && state.modifiedRevision > 0;
  }

  String _getVisibleText(EditorSceneObject object) {
    if (document.optimisticEdit?.objectId == object.objectId) {
      final edit = document.optimisticEdit!;
      final baseText = object.text ?? '';
      final start = edit.range.start.clamp(0, baseText.length);
      final end = edit.range.end.clamp(start, baseText.length);
      return baseText.replaceRange(start, end, edit.replacement);
    }
    if (document.queuedEdit?.objectId == object.objectId) {
      final edit = document.queuedEdit!;
      final baseText = object.text ?? '';
      final start = edit.range.start.clamp(0, baseText.length);
      final end = edit.range.end.clamp(start, baseText.length);
      return baseText.replaceRange(start, end, edit.replacement);
    }
    return document.visibleText(object.objectId) ?? object.text ?? '';
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
    this.caretVisible = true,
    this.showOutline = true,
  });

  final EditorSceneObject object;
  final EditorSelection selection;
  final EditorCompositionRange? composition;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;
  final bool caretVisible;
  final bool showOutline;

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
    if (showOutline) {
      canvas.drawRect(bounds, outline);
    }
    if (caretVisible) {
      final caret = _caretSegment(object, selection.range.end);
      canvas.drawLine(caret.$1, caret.$2, outline..strokeWidth = 1.5);
    }
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
      caretVisible != oldDelegate.caretVisible ||
      showOutline != oldDelegate.showOutline ||
      displaySize != oldDelegate.displaySize;

  (Offset, Offset) _caretSegment(EditorSceneObject object, int utf16Offset) {
    // Live imports arrive without measured character boxes; synthesize
    // proportional ones so the caret lands at the clicked character.
    final characterBoxes = object.characterBoxes.isEmpty
        ? synthesizeCharacterBoxes(object)
        : object.characterBoxes;
    EditorTextCharacterBox? character;
    var useLeadingEdge = true;
    for (final candidate in characterBoxes) {
      if (candidate.start == utf16Offset) {
        character = candidate;
        break;
      }
    }
    if (character == null) {
      for (final candidate in characterBoxes.reversed) {
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

/// A blinking caret painted from PDF character geometry for the active
/// object. Paints nothing else — the PDF page keeps rendering the real
/// content underneath.
class _ActiveObjectCaret extends StatefulWidget {
  const _ActiveObjectCaret({
    required this.object,
    required this.selection,
    required this.pageSize,
    required this.displaySize,
    required this.observer,
  });

  final EditorSceneObject object;
  final EditorSelection selection;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;

  @override
  State<_ActiveObjectCaret> createState() => _ActiveObjectCaretState();
}

class _ActiveObjectCaretState extends State<_ActiveObjectCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1060),
        )
        ..addListener(() => setState(() {}))
        ..repeat();

  // TextField-style asymmetric blink: visible for the first ~53% of the cycle.
  bool get _caretVisible => _blink.value < 0.53;

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('session-caret'),
      size: widget.displaySize,
      painter: _EditorChromePainter(
        object: widget.object,
        selection: widget.selection,
        composition: null,
        pageSize: widget.pageSize,
        displaySize: widget.displaySize,
        observer: widget.observer,
        caretVisible: _caretVisible,
        showOutline: false,
      ),
    );
  }
}

/// A pan-safe tap detector that observes raw pointer events without competing
/// in the gesture arena, so the reader's pan/zoom keeps working while taps
/// still land. Complements the pdfrx overlay hit-tester dispatch, which can be
/// stale when the viewer rebuilds page overlays lazily.
class _TapRegion extends StatefulWidget {
  const _TapRegion({required this.onTap, required this.child});

  final ValueChanged<Offset> onTap;
  final Widget child;

  @override
  State<_TapRegion> createState() => _TapRegionState();
}

class _TapRegionState extends State<_TapRegion> {
  Offset? _downPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == kPrimaryButton) {
          _downPosition = event.localPosition;
        }
      },
      onPointerUp: (PointerUpEvent event) {
        final Offset? down = _downPosition;
        _downPosition = null;
        if (down == null) return;
        if ((event.localPosition - down).distance > kTouchSlop) return;
        widget.onTap(event.localPosition);
      },
      onPointerCancel: (PointerCancelEvent event) {
        _downPosition = null;
      },
      child: widget.child,
    );
  }
}
