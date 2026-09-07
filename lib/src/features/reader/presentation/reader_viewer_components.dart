part of 'reader_viewer_pane.dart';
class _DocumentSearchOverlay extends StatelessWidget {
  const _DocumentSearchOverlay({
    required this.query,
    required this.isSearching,
    required this.matchCount,
    required this.currentIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final String query;
  final bool isSearching;
  final int matchCount;
  final int? currentIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final bool noMatches = !isSearching && matchCount == 0;
    final String status = noMatches
        ? 'No matches found'
        : isSearching
        ? '${matchCount == 0 ? 'Searching' : '$matchCount match${matchCount == 1 ? '' : 'es'} found'}…'
        : '${(currentIndex ?? 0) + 1} of $matchCount';

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('document-search-overlay'),
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(
          color: WorkspaceColors.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: noMatches ? WorkspaceColors.warning : WorkspaceColors.border,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSearching)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: WorkspaceColors.textMuted,
                ),
              )
            else
              Icon(
                noMatches ? LucideIcons.circleAlert : LucideIcons.search,
                color: noMatches
                    ? WorkspaceColors.warning
                    : WorkspaceColors.textMuted,
                size: 14,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status,
                key: Key(
                  noMatches ? 'search-no-matches' : 'search-match-count',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: noMatches
                      ? WorkspaceColors.textStrong
                      : WorkspaceColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!noMatches) ...<Widget>[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Previous match',
                child: IconButton(
                  key: const Key('search-previous-match'),
                  onPressed: onPrevious,
                  icon: const Icon(LucideIcons.chevronUp, size: 16),
                  color: WorkspaceColors.textStrong,
                  disabledColor: WorkspaceColors.textFaint,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Next match',
                child: IconButton(
                  key: const Key('search-next-match'),
                  onPressed: onNext,
                  icon: const Icon(LucideIcons.chevronDown, size: 16),
                  color: WorkspaceColors.textStrong,
                  disabledColor: WorkspaceColors.textFaint,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PdfEdgeScrollbar extends StatelessWidget {
  const _PdfEdgeScrollbar({
    required this.controller,
    required this.axis,
    required this.viewportSize,
  });

  final PdfViewerController controller;
  final PdfScrollbarAxis axis;
  final Size viewportSize;

  @override
  Widget build(BuildContext context) {
    if (!controller.isReady) {
      return const SizedBox.shrink();
    }

    final PdfScrollbarGeometry? geometry = calculatePdfScrollbarGeometry(
      axis: axis,
      viewportSize: viewportSize,
      visibleRect: controller.visibleRect,
      documentSize: controller.documentSize,
      minThumbExtent: 34,
    );
    if (geometry == null) {
      return const SizedBox.shrink();
    }

    // Determine if the other scrollbar is also visible to prevent overlap in the corner
    final PdfScrollbarAxis otherAxis = axis == PdfScrollbarAxis.vertical
        ? PdfScrollbarAxis.horizontal
        : PdfScrollbarAxis.vertical;
    final PdfScrollbarGeometry? otherGeometry = calculatePdfScrollbarGeometry(
      axis: otherAxis,
      viewportSize: viewportSize,
      visibleRect: controller.visibleRect,
      documentSize: controller.documentSize,
      minThumbExtent: 34,
    );
    final bool isOtherVisible = otherGeometry != null;

    if (axis == PdfScrollbarAxis.vertical) {
      return Positioned(
        top: 0,
        right: 0,
        bottom: isOtherVisible ? 12 : 0,
        width: 12,
        child: _PdfScrollbarTrack(
          axis: axis,
          child: Stack(
            children: <Widget>[
              Positioned(
                top: geometry.thumbLeading,
                left: 3,
                right: 3,
                height: geometry.thumbExtent,
                child: _PdfScrollbarThumb(
                  onDragUpdate: (DragUpdateDetails details) {
                    _setVisibleLeading(
                      geometry.visibleLeadingForThumbDrag(details.delta.dy),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: isOtherVisible ? 12 : 0,
      bottom: 0,
      height: 12,
      child: _PdfScrollbarTrack(
        axis: axis,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: geometry.thumbLeading,
              top: 3,
              bottom: 3,
              width: geometry.thumbExtent,
              child: _PdfScrollbarThumb(
                onDragUpdate: (DragUpdateDetails details) {
                  _setVisibleLeading(
                    geometry.visibleLeadingForThumbDrag(details.delta.dx),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setVisibleLeading(double visibleLeading) {
    final Matrix4 matrix = controller.value.clone();
    if (axis == PdfScrollbarAxis.vertical) {
      matrix.y = -visibleLeading;
    } else {
      matrix.x = -visibleLeading;
    }
    controller.value = matrix;
  }
}

class _PdfScrollbarTrack extends StatelessWidget {
  const _PdfScrollbarTrack({required this.axis, required this.child});

  final PdfScrollbarAxis axis;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderSide = const BorderSide(
      color: WorkspaceColors.border,
      width: 0.5,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WorkspaceColors.canvasRaised,
        border: Border(
          left: axis == PdfScrollbarAxis.vertical
              ? borderSide
              : BorderSide.none,
          top: axis == PdfScrollbarAxis.horizontal
              ? borderSide
              : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

class _PdfScrollbarThumb extends StatefulWidget {
  const _PdfScrollbarThumb({required this.onDragUpdate});

  final GestureDragUpdateCallback onDragUpdate;

  @override
  State<_PdfScrollbarThumb> createState() => _PdfScrollbarThumbState();
}

class _QuickSelectionMenu extends StatelessWidget {
  const _QuickSelectionMenu({
    required this.colors,
    required this.onCopy,
    required this.onBookmark,
    required this.onHighlight,
    required this.onDismiss,
  });

  final WorkspaceSurfaceTokens colors;
  final Future<void> Function() onCopy;
  final Future<void> Function() onBookmark;
  final Future<void> Function(int color) onHighlight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: colors.panelRaised,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextButton.icon(
            onPressed: () async {
              await onCopy();
              onDismiss();
            },
            icon: const Icon(LucideIcons.copy, size: 14),
            label: const Text('Copy'),
          ),
          TextButton.icon(
            onPressed: () async {
              await onBookmark();
              onDismiss();
            },
            icon: const Icon(LucideIcons.bookmarkPlus, size: 14),
            label: const Text('Bookmark'),
          ),
          for (final color in const <int>[0x66FFD54F, 0x6686EFAC, 0x668EC5FF])
            IconButton(
              tooltip: 'Highlight',
              onPressed: () async {
                await onHighlight(color);
                onDismiss();
              },
              icon: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ColourWheel extends StatelessWidget {
  const _ColourWheel({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final HSVColor hsv = HSVColor.fromColor(color);
    return SizedBox(
      width: 176,
      height: 176,
      child: GestureDetector(
        key: const Key('highlight-colour-wheel'),
        onPanDown: (details) => _select(details.localPosition),
        onPanUpdate: (details) => _select(details.localPosition),
        child: CustomPaint(painter: _ColourWheelPainter(hsv)),
      ),
    );
  }

  void _select(Offset point) {
    const double radius = 88;
    final Offset vector = point - const Offset(radius, radius);
    final double distance = vector.distance;
    if (distance > radius) return;
    final double hue = (vector.direction * 180 / 3.141592653589793 + 360) % 360;
    final double saturation = (distance / radius).clamp(0.0, 1.0);
    onChanged(HSVColor.fromAHSV(color.a, hue, saturation, 1).toColor());
  }
}

class _ColourWheelPainter extends CustomPainter {
  const _ColourWheelPainter(this.selected);
  final HSVColor selected;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final Paint paint = Paint();
    for (int degrees = 0; degrees < 360; degrees++) {
      paint.color = HSVColor.fromAHSV(1, degrees.toDouble(), 1, 1).toColor();
      final double start = degrees * 3.141592653589793 / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        0.025,
        true,
        paint,
      );
    }
    final Offset marker =
        center +
        Offset.fromDirection(
          selected.hue * 3.141592653589793 / 180,
          selected.saturation * radius,
        );
    canvas.drawCircle(marker, 7, Paint()..color = Colors.white);
    canvas.drawCircle(marker, 4, Paint()..color = selected.toColor());
  }

  @override
  bool shouldRepaint(covariant _ColourWheelPainter oldDelegate) =>
      oldDelegate.selected != selected;
}

class _PdfScrollbarThumbState extends State<_PdfScrollbarThumb> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final Color thumbColor = _isDragging
        ? const Color(0xFF71717A)
        : _isHovered
        ? const Color(0xFF52525B)
        : const Color(0xFF3F3F46);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: widget.onDragUpdate,
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: thumbColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

class _ViewerHud extends StatelessWidget {
  const _ViewerHud({
    required this.page,
    required this.pageCount,
    required this.zoom,
    required this.documentId,
    required this.filePath,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onSelectZoomPreset,
    required this.onHighlightSelection,
    required this.textEditing,
    required this.onToggleTextEditing,
    this.onRefreshCanvas,
    this.onUndo,
    this.onRedo,
    this.onSave,
    this.scanning = false,
    this.nightMode = PdfNightMode.off,
    this.onNightModeChanged,
  });

  final int page;
  final int? pageCount;
  final double zoom;
  final String documentId;
  final String filePath;
  final PdfNightMode nightMode;
  final ValueChanged<PdfNightMode>? onNightModeChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final ValueChanged<_ZoomPreset>? onSelectZoomPreset;
  final VoidCallback? onHighlightSelection;
  final bool textEditing;
  final VoidCallback? onToggleTextEditing;
  final VoidCallback? onRefreshCanvas;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return SmoothClipRRect(
      smoothness: 0.9,
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: WorkspaceColors.border),
      child: Container(
        color: const Color(0xE6121214),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HudIcon(icon: LucideIcons.chevronLeft, onPressed: onPreviousPage),
            const SizedBox(width: 6),
            Text(
              pageCount == null ? 'p.$page' : 'p.$page / $pageCount',
              style: const TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            _HudIcon(icon: LucideIcons.chevronRight, onPressed: onNextPage),
            const SizedBox(width: 8),
            ReadingVelocityPill(
              documentId: documentId,
              currentPage: page,
              totalPages: pageCount ?? 1,
            ),
            const SizedBox(width: 8),
            const _HudDivider(),
            const SizedBox(width: 10),
            _HudIcon(icon: LucideIcons.minus, onPressed: onZoomOut),
            const SizedBox(width: 6),
            PopupMenuButton<_ZoomPreset>(
              enabled: onSelectZoomPreset != null,
              tooltip: 'Zoom presets',
              color: WorkspaceColors.panelRaised,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: WorkspaceColors.border),
              ),
              onSelected: onSelectZoomPreset,
              itemBuilder: (BuildContext context) {
                return _ZoomPreset.values
                    .map((_ZoomPreset preset) {
                      return PopupMenuItem<_ZoomPreset>(
                        value: preset,
                        child: Text(
                          preset.label,
                          style: const TextStyle(
                            color: WorkspaceColors.textStrong,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    })
                    .toList(growable: false);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  '${(zoom * 100).round()}%',
                  style: const TextStyle(
                    color: WorkspaceColors.textStrong,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HudIcon(icon: LucideIcons.plus, onPressed: onZoomIn),
            const SizedBox(width: 10),
            const _HudDivider(),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Copy Deep Link to Page $page (clarix://open)',
              child: _HudIcon(
                icon: LucideIcons.link,
                onPressed: () {
                  final link = const DeepLinkService().generateDeepLink(
                    filePath: filePath,
                    page: page,
                  );
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied deep link: $link'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<PdfNightMode>(
              key: const Key('pdf-night-mode-btn'),
              tooltip: 'Night Mode / Smart Dark Mode',
              color: WorkspaceColors.panelRaised,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: WorkspaceColors.border),
              ),
              onSelected: onNightModeChanged,
              itemBuilder: (BuildContext context) {
                return PdfNightMode.values.map((PdfNightMode mode) {
                  return PopupMenuItem<PdfNightMode>(
                    value: mode,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          mode.icon,
                          size: 14,
                          color: mode == nightMode
                              ? WorkspaceColors.accent
                              : WorkspaceColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: mode == nightMode
                                ? WorkspaceColors.textStrong
                                : WorkspaceColors.textMuted,
                            fontSize: 11.5,
                            fontWeight:
                                mode == nightMode ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(growable: false);
              },
              child: _HudIcon(
                icon: nightMode.icon,
                active: nightMode != PdfNightMode.off,
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Highlight selected text',
              child: _HudIcon(
                icon: LucideIcons.highlighter,
                onPressed: onHighlightSelection,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: textEditing
                  ? 'Exit manual text editing'
                  : 'Enter manual text editing (Adobe bounding boxes)',
              child: _HudIcon(
                key: const Key('pdf-text-edit-toggle'),
                icon: LucideIcons.squarePen,
                onPressed: onToggleTextEditing,
                active: textEditing,
              ),
            ),

            if (textEditing) ...<Widget>[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Undo edit (Ctrl+Z)',
                child: _HudIcon(
                  icon: LucideIcons.undo2,
                  onPressed: onUndo,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Redo edit (Ctrl+Y)',
                child: _HudIcon(
                  icon: LucideIcons.redo2,
                  onPressed: onRedo,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Save PDF edits (Ctrl+S)',
                child: _HudIcon(
                  icon: LucideIcons.save,
                  onPressed: onSave,
                ),
              ),
            ],
            if (textEditing && scanning) ...<Widget>[
              const SizedBox(width: 10),
              const _HudDivider(),
              const SizedBox(width: 10),
              const IgnorePointer(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: WorkspaceColors.textMuted,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Scanning…',
                      style: TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ZoomPreset {
  fitWidth('Fit width'),
  fitPage('Fit page'),
  percent25('25%'),
  percent50('50%'),
  percent75('75%'),
  percent100('100%'),
  percent125('125%'),
  percent150('150%'),
  percent200('200%'),
  percent300('300%');

  const _ZoomPreset(this.label);

  final String label;
}

class _HudIcon extends StatelessWidget {
  const _HudIcon({
    required this.icon,
    required this.onPressed,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ShadIconButton.ghost(
      width: 24,
      height: 24,
      padding: EdgeInsets.zero,
      backgroundColor: active ? WorkspaceColors.accentSoft : null,
      icon: Icon(icon, size: 12),
      onPressed: onPressed,
    );
  }
}

class _HudDivider extends StatelessWidget {
  const _HudDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 16, color: WorkspaceColors.border);
  }
}

PdfTextSelectionParams textSelectionParamsFor(
  PdfEditingInteraction interaction,
) => const PdfTextSelectionParams(
  enabled: true,
  showContextMenuAutomatically: true,
);

PdfViewerOnKeyCallback viewerKeyHandlerFor(PdfEditingInteraction interaction) =>
    (_, _, _) => interaction == PdfEditingInteraction.textEditing ? true : null;
// reader-components-anchor
