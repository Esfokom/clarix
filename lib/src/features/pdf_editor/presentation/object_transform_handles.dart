import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import 'editor_text_painter.dart';

class ObjectTransformHandles extends StatefulWidget {
  const ObjectTransformHandles({
    required this.session,
    required this.object,
    required this.pageSize,
    required this.displaySize,
    super.key,
  });

  final EditorSessionController session;
  final EditorSceneObject object;
  final Size pageSize;
  final Size displaySize;

  @override
  State<ObjectTransformHandles> createState() => _ObjectTransformHandlesState();
}

class _ObjectTransformHandlesState extends State<ObjectTransformHandles> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Clarix object transform handles',
  );
  FocusNode? _previousFocus;
  Offset _movePreview = Offset.zero;
  Offset _resizePreview = Offset.zero;
  double _rotationPreview = 0;
  double? _rotationStart;
  bool _gestureCancelled = false;

  double get _scaleX => widget.displaySize.width / widget.pageSize.width;
  double get _scaleY => widget.displaySize.height / widget.pageSize.height;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = EditorPageGeometry.rectForBox(
      widget.object.bounds,
      transform: widget.object.transform,
      pageSize: widget.pageSize,
      displaySize: widget.displaySize,
    );
    final previewRect = Rect.fromLTWH(
      rect.left + _movePreview.dx,
      rect.top + _movePreview.dy,
      math.max(8, rect.width + _resizePreview.dx),
      math.max(8, rect.height + _resizePreview.dy),
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _resetPreview(cancelGesture: true),
      },
      child: Focus(
        focusNode: _focusNode,
        child: Stack(
          children: <Widget>[
            // Selection border
            Positioned.fromRect(
              rect: previewRect,
              child: Transform.rotate(
                angle: _rotationPreview,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF2F80ED),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Move bar along top
            Positioned(
              left: previewRect.left + 20,
              top: math.max(0, previewRect.top - 6),
              width: math.max(20, previewRect.width - 40),
              height: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  key: const Key('move-object-handle'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _beginGesture(),
                  onPanUpdate: (details) =>
                      setState(() => _movePreview += details.delta),
                  onPanEnd: (_) => _commitMove(),
                  onPanCancel: () => _resetPreview(cancelGesture: true),
                ),
              ),
            ),
            // Top Center Rotation Stem (vertical line + circular handle)
            Positioned(
              left: previewRect.center.dx - 0.75,
              top: math.max(0, previewRect.top - 20),
              width: 1.5,
              height: 20,
              child: const IgnorePointer(
                child: ColoredBox(color: Color(0xFF2F80ED)),
              ),
            ),
            Positioned(
              left: previewRect.left,
              top: math.max(0, previewRect.top - 30),
              width: 20,
              height: 20,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: const Key('rotate-object-handle'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    _beginGesture();
                    _rotationStart = _angle(
                      _local(details.globalPosition),
                      previewRect,
                    );
                  },
                  onPanUpdate: (details) {
                    final start = _rotationStart;
                    if (start == null) return;
                    setState(() {
                      _rotationPreview =
                          _angle(_local(details.globalPosition), previewRect) -
                          start;
                    });
                  },
                  onPanEnd: (_) => _commitRotation(rect),
                  onPanCancel: () => _resetPreview(cancelGesture: true),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF2F80ED),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 11,
                      color: Color(0xFF2F80ED),
                    ),
                  ),
                ),
              ),
            ),
            // Corner & Edge Resize Handles
            // Top-Left
            Positioned(
              left: previewRect.left - 4,
              top: previewRect.top - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Top-Right
            Positioned(
              left: previewRect.right - 4,
              top: previewRect.top - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Bottom-Left
            Positioned(
              left: previewRect.left - 4,
              top: previewRect.bottom - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Bottom-Right (Interactive Resize Handle)
            Positioned(
              left: previewRect.right - 8,
              top: previewRect.bottom - 8,
              width: 16,
              height: 16,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  key: const Key('resize-object-handle'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _beginGesture(),
                  onPanUpdate: (details) =>
                      setState(() => _resizePreview += details.delta),
                  onPanEnd: (_) => _commitResize(),
                  onPanCancel: () => _resetPreview(cancelGesture: true),
                  child: const Center(child: _HandleDot()),
                ),
              ),
            ),
            // Top-Center
            Positioned(
              left: previewRect.center.dx - 4,
              top: previewRect.top - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Bottom-Center
            Positioned(
              left: previewRect.center.dx - 4,
              top: previewRect.bottom - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Left-Center
            Positioned(
              left: previewRect.left - 4,
              top: previewRect.center.dy - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
            // Right-Center
            Positioned(
              left: previewRect.right - 4,
              top: previewRect.center.dy - 4,
              width: 8,
              height: 8,
              child: const _HandleDot(),
            ),
          ],
        ),
      ),
    );
  }

  double _angle(Offset local, Rect rect) =>
      math.atan2(local.dy - rect.center.dy, local.dx - rect.center.dx);

  Offset _local(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  void _commitMove() {
    if (_takeCancellation()) return;
    final source = widget.object.transform;
    final command = EditorCommand(
      kind: EditorCommandKind.moveObject,
      objectId: widget.object.objectId,
      transform: EditorAffineTransform(
        a: source.a,
        b: source.b,
        c: source.c,
        d: source.d,
        e: source.e + _movePreview.dx / _scaleX,
        f: source.f - _movePreview.dy / _scaleY,
      ),
    );
    _resetPreview();
    widget.session.dispatchCommand(command);
    _restoreFocus();
  }

  void _commitResize() {
    if (_takeCancellation()) return;
    final source = widget.object.bounds;
    final command = EditorCommand(
      kind: EditorCommandKind.resizeObject,
      objectId: widget.object.objectId,
      bounds: EditorPdfBox(
        left: source.left,
        bottom: source.bottom - _resizePreview.dy / _scaleY,
        right: source.right + _resizePreview.dx / _scaleX,
        top: source.top,
      ),
    );
    _resetPreview();
    widget.session.dispatchCommand(command);
    _restoreFocus();
  }

  void _commitRotation(Rect rect) {
    if (_takeCancellation()) return;
    final center = EditorPageGeometry.pdfPointForDisplay(
      rect.center,
      pageSize: widget.pageSize,
      displaySize: widget.displaySize,
    );
    final command = EditorCommand(
      kind: EditorCommandKind.rotateObject,
      objectId: widget.object.objectId,
      radians: -_rotationPreview,
      centerX: center.dx,
      centerY: center.dy,
    );
    _resetPreview();
    widget.session.dispatchCommand(command);
    _restoreFocus();
  }

  bool _takeCancellation() {
    if (!_gestureCancelled) return false;
    _gestureCancelled = false;
    return true;
  }

  void _beginGesture() {
    _gestureCancelled = false;
    _previousFocus = FocusManager.instance.primaryFocus;
    _focusNode.requestFocus();
  }

  void _restoreFocus() {
    final previous = _previousFocus;
    _previousFocus = null;
    if (previous != null && previous.canRequestFocus) previous.requestFocus();
  }

  void _resetPreview({bool cancelGesture = false}) {
    if (!mounted) return;
    setState(() {
      _gestureCancelled = cancelGesture;
      _movePreview = Offset.zero;
      _resizePreview = Offset.zero;
      _rotationPreview = 0;
      _rotationStart = null;
    });
    if (cancelGesture) _restoreFocus();
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(1.5),
      border: Border.all(color: const Color(0xFF2F80ED), width: 1.2),
    ),
  );
}
