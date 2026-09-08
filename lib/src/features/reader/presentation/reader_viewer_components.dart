part of 'reader_viewer_pane.dart';

class _DocumentSearchOverlay extends StatelessWidget {
  const _DocumentSearchOverlay({
    required this.query,
    required this.isSearching,
    required this.matchCount,
    required this.currentIndex,
    required this.onPrevious,
    required this.onNext,
    required this.colors,
  });

  final String query;
  final bool isSearching;
  final int matchCount;
  final int? currentIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final WorkspaceSurfaceTokens colors;

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
          color: colors.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: noMatches ? colors.warning : colors.border),
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
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colors.textMuted,
                ),
              )
            else
              Icon(
                noMatches ? LucideIcons.circleAlert : LucideIcons.search,
                color: noMatches ? colors.warning : colors.textMuted,
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
                  color: noMatches ? colors.textStrong : colors.textMuted,
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
                  color: colors.textStrong,
                  disabledColor: colors.textFaint,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Next match',
                child: IconButton(
                  key: const Key('search-next-match'),
                  onPressed: onNext,
                  icon: const Icon(LucideIcons.chevronDown, size: 16),
                  color: colors.textStrong,
                  disabledColor: colors.textFaint,
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
    required this.colors,
  });

  final PdfViewerController controller;
  final PdfScrollbarAxis axis;
  final Size viewportSize;
  final WorkspaceSurfaceTokens colors;

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
          colors: colors,
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
        colors: colors,
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
  const _PdfScrollbarTrack({
    required this.axis,
    required this.child,
    required this.colors,
  });

  final PdfScrollbarAxis axis;
  final Widget child;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(color: colors.border, width: 0.5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvasRaised,
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
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) =>
            _select(details.localPosition, _wheelSize(context)),
        onPanUpdate: (details) =>
            _select(details.localPosition, _wheelSize(context)),
        child: CustomPaint(painter: _ColourWheelPainter(hsv)),
      ),
    );
  }

  void _select(Offset point, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final Offset vector = point - center;
    final double distance = vector.distance;
    if (distance > radius) return;
    final double hue = (vector.direction * 180 / math.pi + 360) % 360;
    final double saturation = (distance / radius).clamp(0.0, 1.0);
    onChanged(HSVColor.fromAHSV(color.a, hue, saturation, 1).toColor());
  }

  Size _wheelSize(BuildContext context) =>
      (context.findRenderObject() as RenderBox?)?.size ?? const Size(176, 176);
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
      final double start = degrees * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.pi / 180,
        true,
        paint,
      );
    }
    final Offset marker =
        center +
        Offset.fromDirection(
          selected.hue * math.pi / 180,
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
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onSelectZoomPreset,
    required this.onHighlightSelection,
    required this.colors,
  });

  final int page;
  final int? pageCount;
  final double zoom;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final ValueChanged<_ZoomPreset>? onSelectZoomPreset;
  final VoidCallback? onHighlightSelection;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return SmoothClipRRect(
      smoothness: 0.9,
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.border),
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
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            _HudIcon(icon: LucideIcons.chevronRight, onPressed: onNextPage),
            const SizedBox(width: 10),
            _HudDivider(colors: colors),
            const SizedBox(width: 10),
            _HudIcon(icon: LucideIcons.minus, onPressed: onZoomOut),
            const SizedBox(width: 6),
            PopupMenuButton<_ZoomPreset>(
              enabled: onSelectZoomPreset != null,
              tooltip: 'Zoom presets',
              color: colors.panelRaised,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.border),
              ),
              onSelected: onSelectZoomPreset,
              itemBuilder: (BuildContext context) {
                return _ZoomPreset.values
                    .map((_ZoomPreset preset) {
                      return PopupMenuItem<_ZoomPreset>(
                        value: preset,
                        child: Text(
                          preset.label,
                          style: TextStyle(
                            color: colors.textStrong,
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
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HudIcon(icon: LucideIcons.plus, onPressed: onZoomIn),
            const SizedBox(width: 10),
            _HudDivider(colors: colors),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Highlight selected text',
              child: _HudIcon(
                icon: LucideIcons.highlighter,
                onPressed: onHighlightSelection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenTopBar extends StatelessWidget {
  const _FullscreenTopBar({
    required this.title,
    required this.onOpenSettings,
    required this.onExit,
    required this.colors,
  });

  final String title;
  final VoidCallback? onOpenSettings;
  final VoidCallback onExit;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.panelRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.fileText, size: 15, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onOpenSettings != null)
            Tooltip(
              message: 'Settings',
              child: _HudIcon(
                icon: LucideIcons.settings,
                onPressed: onOpenSettings,
              ),
            ),
          const SizedBox(width: 6),
          Tooltip(
            key: const Key('fullscreen-reader-exit'),
            message: 'Exit fullscreen (Escape)',
            child: _HudIcon(icon: LucideIcons.x, onPressed: onExit),
          ),
        ],
      ),
    );
  }
}

class _FullscreenBottomBar extends StatelessWidget {
  const _FullscreenBottomBar({
    required this.page,
    required this.pageCount,
    required this.zoom,
    required this.scrubPreviewPage,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onScrubChanged,
    required this.onScrubEnd,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onSelectZoomPreset,
    required this.onHighlightSelection,
    required this.readAloudStatus,
    required this.onReadAloudPressed,
    required this.colors,
  });

  final int page;
  final int? pageCount;
  final double zoom;
  final double? scrubPreviewPage;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<double>? onScrubChanged;
  final ValueChanged<double>? onScrubEnd;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final ValueChanged<_ZoomPreset>? onSelectZoomPreset;
  final VoidCallback? onHighlightSelection;
  final TtsPlaybackStatus readAloudStatus;
  final VoidCallback? onReadAloudPressed;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final int displayPage = (scrubPreviewPage ?? page.toDouble()).round();
    final bool canScrub = pageCount != null && pageCount! > 1;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.panelRaised,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: <Widget>[
          _HudIcon(icon: LucideIcons.chevronLeft, onPressed: onPreviousPage),
          const SizedBox(width: 8),
          Text(
            pageCount == null
                ? 'p.$displayPage'
                : 'p.$displayPage / $pageCount',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          _HudIcon(icon: LucideIcons.chevronRight, onPressed: onNextPage),
          const SizedBox(width: 14),
          Expanded(
            child: canScrub
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: colors.accent,
                      inactiveTrackColor: colors.border,
                      thumbColor: colors.accent,
                    ),
                    child: Slider(
                      min: 1,
                      max: pageCount!.toDouble(),
                      value: (scrubPreviewPage ?? page.toDouble()).clamp(
                        1,
                        pageCount!.toDouble(),
                      ),
                      onChanged: onScrubChanged,
                      onChangeEnd: onScrubEnd,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 14),
          _HudDivider(colors: colors),
          const SizedBox(width: 10),
          _HudIcon(icon: LucideIcons.minus, onPressed: onZoomOut),
          const SizedBox(width: 6),
          PopupMenuButton<_ZoomPreset>(
            enabled: onSelectZoomPreset != null,
            tooltip: 'Zoom presets',
            color: colors.panelRaised,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
            onSelected: onSelectZoomPreset,
            itemBuilder: (BuildContext context) {
              return _ZoomPreset.values
                  .map((_ZoomPreset preset) {
                    return PopupMenuItem<_ZoomPreset>(
                      value: preset,
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          color: colors.textStrong,
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
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _HudIcon(icon: LucideIcons.plus, onPressed: onZoomIn),
          const SizedBox(width: 10),
          _HudDivider(colors: colors),
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
            message: readAloudStatus == TtsPlaybackStatus.speaking
                ? 'Pause reading'
                : 'Read this page aloud',
            child: readAloudStatus == TtsPlaybackStatus.preparing
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                  )
                : _HudIcon(
                    icon: readAloudStatus == TtsPlaybackStatus.speaking
                        ? LucideIcons.pause
                        : LucideIcons.headphones,
                    onPressed: onReadAloudPressed,
                  ),
          ),
        ],
      ),
    );
  }
}

enum _ZoomPreset {
  fitWidth('Fit width'),
  fitPage('Fit page'),
  percent50('50%'),
  percent75('75%'),
  percent100('100%'),
  percent125('125%'),
  percent150('150%'),
  percent200('200%');

  const _ZoomPreset(this.label);

  final String label;
}

class _HudIcon extends StatelessWidget {
  const _HudIcon({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ShadIconButton.ghost(
      width: 24,
      height: 24,
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 12),
      onPressed: onPressed,
    );
  }
}

class _HudDivider extends StatelessWidget {
  const _HudDivider({required this.colors});

  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 16, color: colors.border);
  }
}

// reader-components-anchor
