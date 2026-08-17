import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';

typedef PdfPageObjectRectResolver = Rect Function(PdfPageObject object);
typedef PdfObjectPreviewCallback =
    Future<void> Function(PdfPageObjectLocator locator, PdfTransform transform);

final class PdfObjectTransformOverlay extends StatefulWidget {
  const PdfObjectTransformOverlay({
    required this.objects,
    required this.rectForObject,
    required this.documentId,
    required this.documentRevision,
    required this.onIntent,
    required this.onPreview,
    super.key,
  });

  final List<PdfPageObject> objects;
  final PdfPageObjectRectResolver rectForObject;
  final String documentId;
  final String documentRevision;
  final ValueChanged<PdfEditIntent> onIntent;
  final PdfObjectPreviewCallback onPreview;

  @override
  State<PdfObjectTransformOverlay> createState() =>
      _PdfObjectTransformOverlayState();
}

final class _PdfObjectTransformOverlayState
    extends State<PdfObjectTransformOverlay> {
  PdfPageObjectLocator? _selected;
  PdfTransform? _preview;
  Offset? _rotationCenter;
  double? _rotationStart;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: widget.objects.map(_objectOverlay).toList(growable: false),
  );

  Widget _objectOverlay(PdfPageObject object) {
    final rect = widget.rectForObject(object);
    final selected = _selected == object.locator;
    final locked = object.readOnlyReason != null;
    final angle = math.atan2(object.transform.b, object.transform.a);
    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() {
            _selected = object.locator;
            _preview = object.transform;
          }),
          onPanUpdate: selected && !locked
              ? (details) => _move(object, rect, details.delta)
              : null,
          onPanEnd: selected && !locked ? (_) => _commitMove(object) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  key: const Key('pdf-page-object-outline'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: locked
                          ? const Color(0xffa16207)
                          : selected
                          ? const Color(0xff2563eb)
                          : const Color(0x55718096),
                      width: selected ? 1.2 : 0.7,
                    ),
                  ),
                ),
              ),
              if (locked && selected)
                const Positioned(
                  key: Key('pdf-object-locked'),
                  right: 2,
                  top: 2,
                  child: Icon(Icons.lock_outline, size: 12),
                ),
              if (selected && !locked) ...<Widget>[
                _resizeHandle(object, rect),
                _rotateHandle(object, rect),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resizeHandle(PdfPageObject object, Rect rect) => Positioned(
    right: -5,
    bottom: -5,
    width: 11,
    height: 11,
    child: GestureDetector(
      key: const Key('pdf-resize-handle'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        final current = _preview ?? object.transform;
        final scaleX = (1 + details.delta.dx / rect.width).clamp(0.05, 20.0);
        final scaleY = (1 + details.delta.dy / rect.height).clamp(0.05, 20.0);
        final center = current.transformPoint(
          Offset(
            (object.bounds.left + object.bounds.right) / 2,
            (object.bounds.bottom + object.bounds.top) / 2,
          ),
        );
        final next = current.scaledAround(
          scaleX: scaleX,
          scaleY: scaleY,
          center: center,
        );
        _preview = next;
        unawaited(widget.onPreview(object.locator, next));
      },
      onPanEnd: (_) {
        final next = _preview;
        if (next != null) {
          widget.onIntent(
            ResizePdfPageObjectIntent(
              documentId: widget.documentId,
              documentRevision: widget.documentRevision,
              locator: object.locator,
              transform: next,
            ),
          );
        }
      },
      child: const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    ),
  );

  Widget _rotateHandle(PdfPageObject object, Rect rect) => Positioned(
    top: 2,
    left: rect.width / 2 - 7,
    width: 14,
    height: 14,
    child: GestureDetector(
      key: const Key('pdf-rotate-handle'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        final box = context.findRenderObject()! as RenderBox;
        _rotationCenter = box.localToGlobal(rect.center);
        final delta = details.globalPosition - _rotationCenter!;
        _rotationStart = math.atan2(delta.dy, delta.dx);
      },
      onPanUpdate: (details) {
        final center = _rotationCenter;
        final start = _rotationStart;
        if (center == null || start == null) return;
        final delta = details.globalPosition - center;
        var radians = math.atan2(delta.dy, delta.dx) - start;
        if (HardwareKeyboard.instance.isShiftPressed) {
          const snap = math.pi / 12;
          radians = (radians / snap).round() * snap;
        }
        final next = object.transform.rotatedAround(
          radians: radians,
          center: object.transform.transformPoint(
            Offset(
              (object.bounds.left + object.bounds.right) / 2,
              (object.bounds.bottom + object.bounds.top) / 2,
            ),
          ),
        );
        _preview = next;
        unawaited(widget.onPreview(object.locator, next));
      },
      onPanEnd: (_) {
        final next = _preview;
        if (next == null) return;
        final beforeAngle = math.atan2(object.transform.b, object.transform.a);
        final afterAngle = math.atan2(next.b, next.a);
        widget.onIntent(
          RotatePdfPageObjectIntent(
            documentId: widget.documentId,
            documentRevision: widget.documentRevision,
            locator: object.locator,
            radians: afterAngle - beforeAngle,
          ),
        );
      },
      child: const Icon(Icons.rotate_right, size: 14),
    ),
  );

  void _move(PdfPageObject object, Rect rect, Offset delta) {
    final current = _preview ?? object.transform;
    final next = current.translated(
      dx: delta.dx * object.bounds.width / rect.width,
      dy: -delta.dy * object.bounds.height / rect.height,
    );
    _preview = next;
    unawaited(widget.onPreview(object.locator, next));
  }

  void _commitMove(PdfPageObject object) {
    final next = _preview;
    if (next == null) return;
    widget.onIntent(
      MovePdfPageObjectIntent(
        documentId: widget.documentId,
        documentRevision: widget.documentRevision,
        locator: object.locator,
        transform: next,
      ),
    );
  }
}
