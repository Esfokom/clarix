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
            Positioned.fromRect(
              rect: previewRect,
              child: Transform.rotate(
                angle: _rotationPreview,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: previewRect.left + 20,
              top: math.max(0, previewRect.top - 6),
              width: math.max(20, previewRect.width - 40),
              height: 12,
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
            Positioned(
              left: previewRect.right - 10,
              top: previewRect.bottom - 10,
              width: 20,
              height: 20,
              child: GestureDetector(
                key: const Key('resize-object-handle'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _beginGesture(),
                onPanUpdate: (details) =>
                    setState(() => _resizePreview += details.delta),
                onPanEnd: (_) => _commitResize(),
                onPanCancel: () => _resetPreview(cancelGesture: true),
                child: const _HandleDot(),
              ),
            ),
            Positioned(
              left: previewRect.left,
              top: math.max(0, previewRect.top - 30),
              width: 20,
              height: 20,
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
                child: const Icon(Icons.rotate_right, size: 18),
              ),
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
      radians: _rotationPreview,
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
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.surface),
    ),
  );
}
