import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/pdf_edit_intent.dart';
import '../../domain/pdf_edit_session.dart';
import '../../domain/pdf_native_edit_types.dart';
import '../../domain/pdf_page_object.dart';
import '../../domain/pdf_text_types.dart';
import 'pdf_native_text_input.dart';

typedef PdfTextBlockRectResolver = Rect Function(PdfTextBlock block);
typedef PdfBeginTextEditing =
    void Function(PdfTextBlockLocator locator, PdfTextRange range);

final class PdfTextEditorOverlay extends StatefulWidget {
  const PdfTextEditorOverlay({
    required this.mode,
    required this.blocks,
    required this.selection,
    required this.rectForBlock,
    required this.onSelect,
    this.interaction = PdfEditingInteraction.reading,
    this.onBeginTextEditing,
    this.pageObjects = const <PdfPageObject>[],
    this.onObjectPreview,
    this.loading = false,
    this.documentId,
    this.documentRevision,
    this.caseMatching = true,
    this.onIntent,
    this.onClearSelection,
    this.onUndo,
    this.onRedo,
    this.nativeProjection,
    this.onSelectionChanged,
    super.key,
  });

  final PdfEditingMode mode;
  final List<PdfTextBlock> blocks;
  final PdfTextSelection? selection;
  final PdfTextBlockRectResolver rectForBlock;
  final ValueChanged<PdfTextBlockLocator> onSelect;
  final PdfEditingInteraction interaction;
  final PdfBeginTextEditing? onBeginTextEditing;
  final List<PdfPageObject> pageObjects;
  final Future<void> Function(PdfPageObjectLocator, PdfTransform)?
  onObjectPreview;
  final bool loading;
  final String? documentId;
  final String? documentRevision;
  final bool caseMatching;
  final ValueChanged<PdfEditIntent>? onIntent;
  final VoidCallback? onClearSelection;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final PdfNativeProjectionResult? nativeProjection;
  final ValueChanged<PdfTextRange>? onSelectionChanged;

  @override
  State<PdfTextEditorOverlay> createState() => _PdfTextEditorOverlayState();
}

final class _PdfTextEditorOverlayState extends State<PdfTextEditorOverlay>
    with SingleTickerProviderStateMixin {
  PdfTextBlockLocator? _hovered;
  PdfTextBlockLocator? _editingLocator;
  String? _typingGroup;
  PdfBox? _previewBounds;
  double _previewRotation = 0;
  AnimationController? _caretController;

  @override
  void initState() {
    super.initState();
    _caretController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _caretController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == PdfEditingMode.reading) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final block in widget.blocks) _outline(block),
        if (widget.loading)
          const Positioned(
            top: 8,
            right: 8,
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      ],
    );
  }

  Widget _outline(PdfTextBlock block) {
    final selected = widget.selection?.locator == block.locator;
    final hovered = _hovered == block.locator;
    final readOnly = block.readOnlyReason != null;
    final Color color = block.overflow
        ? const Color(0xffd97706)
        : readOnly
        ? const Color(0xffa16207)
        : selected
        ? const Color(0xff2563eb)
        : hovered
        ? const Color(0xff64748b)
        : const Color(0x66718096);
    if (selected &&
        widget.interaction == PdfEditingInteraction.textEditing &&
        block.isEditable &&
        widget.onIntent != null) {
      return _inlineEditor(block);
    }
    return Positioned.fromRect(
      rect: widget.rectForBlock(block),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = block.locator),
        onExit: (_) {
          if (_hovered == block.locator) setState(() => _hovered = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => widget.onSelect(block.locator),
          onDoubleTap: block.isEditable
              ? () => widget.onBeginTextEditing?.call(
                  block.locator,
                  PdfTextRange(0, block.text.length),
                )
              : null,
          child: Container(
            key: const Key('pdf-text-block-outline'),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.06) : null,
              border: Border.all(color: color, width: selected ? 1.2 : 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
            child: readOnly
                ? Align(
                    key: const Key('pdf-text-block-read-only'),
                    alignment: Alignment.topRight,
                    child: Icon(Icons.lock_outline, size: 11, color: color),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _inlineEditor(PdfTextBlock block) {
    if (_editingLocator != block.locator) {
      _editingLocator = block.locator;
      _typingGroup = _newTypingGroup();
    }
    return Positioned.fromRect(
      rect: widget.rectForBlock(block),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (details) => _moveCaret(block, details.localPosition),
              child: Container(
                key: const Key('pdf-text-block-outline'),
                decoration: BoxDecoration(
                  color: const Color(0xff2563eb).withValues(alpha: 0.04),
                  border: Border.all(
                    color: const Color(0xff2563eb),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: PdfNativeTextInput(
                  block: block,
                  selection: widget.selection!,
                  onEscape: () {
                    _typingGroup = null;
                    widget.onClearSelection?.call();
                  },
                  onUndo: widget.onUndo,
                  onRedo: widget.onRedo,
                  onSelectionChanged: widget.onSelectionChanged,
                  onDelta: (delta) => widget.onIntent!(
                    ReplacePdfTextIntent(
                      documentId: widget.documentId!,
                      documentRevision: widget.documentRevision!,
                      locator: block.locator,
                      range: delta.replacedRange,
                      replacement: delta.insertedText,
                      caseMatching: widget.caseMatching,
                      coalescingKey: _typingGroup ??= _newTypingGroup(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ..._selectionChrome(block),
          _moveHandle(block),
          if (_pageObjectFor(block) case final object?)
            _textRotateHandle(object),
          _resizeHandle(block, 'north-west', -1, 1),
          _resizeHandle(block, 'north', 0, 1),
          _resizeHandle(block, 'north-east', 1, 1),
          _resizeHandle(block, 'east', 1, 0),
          _resizeHandle(block, 'south-east', 1, -1),
          _resizeHandle(block, 'south', 0, -1),
          _resizeHandle(block, 'south-west', -1, -1),
          _resizeHandle(block, 'west', -1, 0),
        ],
      ),
    );
  }

  void _moveCaret(PdfTextBlock block, Offset localPosition) {
    final projection = widget.nativeProjection;
    final callback = widget.onSelectionChanged;
    if (projection == null ||
        projection.characters.isEmpty ||
        callback == null) {
      return;
    }
    final rect = widget.rectForBlock(block);
    final x =
        block.bounds.left + localPosition.dx / rect.width * block.bounds.width;
    final y =
        block.bounds.top - localPosition.dy / rect.height * block.bounds.height;
    final offset = PdfNativeTextGeometry.offsetNearest(
      x,
      y,
      projection.characters,
    );
    callback(PdfTextRange(offset, offset));
  }

  List<Widget> _selectionChrome(PdfTextBlock block) {
    final projection = widget.nativeProjection;
    final selection = widget.selection;
    if (projection == null || selection == null) {
      return const <Widget>[];
    }
    if (projection.characters.isEmpty) {
      if (block.text.isNotEmpty) return const <Widget>[];
      final rect = widget.rectForBlock(block);
      return <Widget>[
        Positioned(
          key: const Key('pdf-native-caret'),
          left: 0,
          top: 0,
          width: 1.2,
          height: rect.height.clamp(1, double.infinity),
          child: FadeTransition(
            key: const Key('pdf-native-caret-blink'),
            opacity: Tween<double>(
              begin: 0.15,
              end: 1,
            ).animate(_caretController!),
            child: const ColoredBox(color: Color(0xff2563eb)),
          ),
        ),
      ];
    }
    final widgets = <Widget>[];
    for (final box in PdfNativeTextGeometry.boxesForRange(
      selection.range,
      projection.characters,
    )) {
      widgets.add(
        Positioned.fromRect(
          rect: _localRectForBox(block, box),
          child: IgnorePointer(
            child: ColoredBox(
              key: const Key('pdf-native-selection'),
              color: const Color(0x332563eb),
            ),
          ),
        ),
      );
    }
    final caret = PdfNativeTextGeometry.caretForOffset(
      selection.range.end,
      projection.characters,
    );
    final caretRect = _localRectForBox(block, caret);
    widgets.add(
      Positioned(
        key: const Key('pdf-native-caret'),
        left: caretRect.left,
        top: caretRect.top,
        width: 1.2,
        height: caretRect.height.clamp(1, double.infinity),
        child: FadeTransition(
          key: const Key('pdf-native-caret-blink'),
          opacity: Tween<double>(
            begin: 0.15,
            end: 1,
          ).animate(_caretController!),
          child: const ColoredBox(color: Color(0xff2563eb)),
        ),
      ),
    );
    return widgets;
  }

  Rect _localRectForBox(PdfTextBlock block, PdfBox box) {
    final rect = widget.rectForBlock(block);
    final scaleX = rect.width / block.bounds.width;
    final scaleY = rect.height / block.bounds.height;
    return Rect.fromLTRB(
      (box.left - block.bounds.left) * scaleX,
      (block.bounds.top - box.top) * scaleY,
      (box.right - block.bounds.left) * scaleX,
      (block.bounds.top - box.bottom) * scaleY,
    );
  }

  PdfPageObject? _pageObjectFor(PdfTextBlock block) {
    for (final object in widget.pageObjects) {
      if (object.locator.type == PdfPageObjectType.text &&
          _samePath(object.locator.objectPath, block.locator.objectPath)) {
        return object;
      }
    }
    return null;
  }

  Widget _textRotateHandle(PdfPageObject object) => Positioned(
    top: 2,
    right: 2,
    width: 16,
    height: 16,
    child: GestureDetector(
      key: const Key('pdf-text-rotate-handle'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _previewRotation = 0,
      onPanUpdate: (details) {
        _previewRotation += (details.delta.dx + details.delta.dy) * 0.01;
        final center = object.transform.transformPoint(
          Offset(
            (object.bounds.left + object.bounds.right) / 2,
            (object.bounds.bottom + object.bounds.top) / 2,
          ),
        );
        final next = object.transform.rotatedAround(
          radians: _previewRotation,
          center: center,
        );
        final preview = widget.onObjectPreview;
        if (preview != null) unawaited(preview(object.locator, next));
      },
      onPanEnd: (_) {
        if (_previewRotation == 0 || widget.onIntent == null) return;
        widget.onIntent!(
          RotatePdfPageObjectIntent(
            documentId: widget.documentId!,
            documentRevision: widget.documentRevision!,
            locator: object.locator,
            radians: _previewRotation,
          ),
        );
      },
      child: const Icon(Icons.rotate_right, size: 14),
    ),
  );

  Widget _moveHandle(PdfTextBlock block) => Positioned(
    top: 2,
    left: 24,
    right: 24,
    height: 8,
    child: GestureDetector(
      key: const Key('pdf-move-handle'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _startGeometry(block),
      onPanUpdate: (details) => _updateMove(block, details.delta),
      onPanEnd: (_) => _finishGeometry(block, resize: false),
      child: const MouseRegion(cursor: SystemMouseCursors.move),
    ),
  );

  Widget _resizeHandle(
    PdfTextBlock block,
    String name,
    int horizontal,
    int vertical,
  ) {
    const size = 10.0;
    return Positioned(
      left: horizontal <= 0 ? 0 : null,
      right: horizontal >= 0 ? 0 : null,
      top: vertical >= 0 ? 0 : null,
      bottom: vertical <= 0 ? 0 : null,
      width: horizontal == 0 ? null : size,
      height: vertical == 0 ? null : size,
      child: Align(
        alignment: Alignment(horizontal.toDouble(), -vertical.toDouble()),
        child: GestureDetector(
          key: Key('pdf-resize-$name'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _startGeometry(block),
          onPanUpdate: (details) =>
              _updateResize(block, details.delta, horizontal, vertical),
          onPanEnd: (_) => _finishGeometry(block, resize: true),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xff2563eb)),
            ),
          ),
        ),
      ),
    );
  }

  void _startGeometry(PdfTextBlock block) {
    _typingGroup = null;
    _previewBounds = block.bounds;
  }

  void _updateMove(PdfTextBlock block, Offset viewerDelta) {
    final scale = _viewerScale(block);
    final current = _previewBounds ?? block.bounds;
    final dx = viewerDelta.dx / scale.dx;
    final dy = -viewerDelta.dy / scale.dy;
    setState(
      () => _previewBounds = PdfBox(
        current.left + dx,
        current.bottom + dy,
        current.right + dx,
        current.top + dy,
      ),
    );
  }

  void _updateResize(
    PdfTextBlock block,
    Offset viewerDelta,
    int horizontal,
    int vertical,
  ) {
    final scale = _viewerScale(block);
    final current = _previewBounds ?? block.bounds;
    final dx = viewerDelta.dx / scale.dx;
    final dy = -viewerDelta.dy / scale.dy;
    var left = current.left;
    var right = current.right;
    var bottom = current.bottom;
    var top = current.top;
    if (horizontal < 0) {
      left = (left + dx).clamp(double.negativeInfinity, right - 4);
    }
    if (horizontal > 0) right = (right + dx).clamp(left + 4, double.infinity);
    if (vertical < 0) {
      bottom = (bottom + dy).clamp(double.negativeInfinity, top - 4);
    }
    if (vertical > 0) top = (top + dy).clamp(bottom + 4, double.infinity);
    setState(() => _previewBounds = PdfBox(left, bottom, right, top));
  }

  Offset _viewerScale(PdfTextBlock block) {
    final rect = widget.rectForBlock(block);
    return Offset(
      rect.width / block.bounds.width,
      rect.height / block.bounds.height,
    );
  }

  void _finishGeometry(PdfTextBlock block, {required bool resize}) {
    final bounds = _previewBounds;
    _previewBounds = null;
    if (bounds == null || bounds == block.bounds) return;
    widget.onIntent!(
      resize
          ? ResizePdfTextBlockIntent(
              documentId: widget.documentId!,
              documentRevision: widget.documentRevision!,
              locator: block.locator,
              bounds: bounds,
            )
          : MovePdfTextBlockIntent(
              documentId: widget.documentId!,
              documentRevision: widget.documentRevision!,
              locator: block.locator,
              bounds: bounds,
            ),
    );
  }

  String _newTypingGroup() =>
      'typing-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
}

bool _samePath(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
