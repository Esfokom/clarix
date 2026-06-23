import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'pdf_viewer_interaction_math.dart';
import 'workspace_common.dart';

class DocumentWorkspace extends StatelessWidget {
  const DocumentWorkspace({
    required this.state,
    required this.activeTab,
    super.key,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _TabStrip(state: state, activeTab: activeTab),
        Expanded(child: _PdfViewerPane(tab: activeTab)),
      ],
    );
  }
}

class _TabStrip extends ConsumerStatefulWidget {
  const _TabStrip({required this.state, required this.activeTab});

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;

  @override
  ConsumerState<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<_TabStrip> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.activeTab.searchQuery,
    );
  }

  @override
  void didUpdateWidget(covariant _TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab.id != widget.activeTab.id ||
        oldWidget.activeTab.searchQuery != widget.activeTab.searchQuery) {
      _searchController.text = widget.activeTab.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: WorkspaceColors.canvasRaised,
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.state.session.tabs.length,
              separatorBuilder: (_, int index) => const SizedBox(width: 6),
              itemBuilder: (BuildContext context, int index) {
                final DocumentTabState tab = widget.state.session.tabs[index];
                final bool selected = tab.id == widget.activeTab.id;
                return GestureDetector(
                  onTap: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .setActiveTab(tab.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? WorkspaceColors.panelRaised
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? WorkspaceColors.accentBorder
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          LucideIcons.fileText,
                          size: 13,
                          color: WorkspaceColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: WorkspaceColors.textStrong,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref
                              .read(workspaceNotifierProvider.notifier)
                              .closeTab(tab.id),
                          child: const Icon(
                            LucideIcons.x,
                            size: 12,
                            color: WorkspaceColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            child: ShadInput(
              controller: _searchController,
              placeholder: const Text('Search PDF'),
              leading: const Icon(LucideIcons.search, size: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onSubmitted: (String value) => ref
                  .read(workspaceNotifierProvider.notifier)
                  .setSearchQuery(widget.activeTab.id, value.trim()),
            ),
          ),
          const SizedBox(width: 8),
          ShadBadge.secondary(
            child: Text(
              widget.activeTab.indexStatus.name,
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfViewerPane extends ConsumerStatefulWidget {
  const _PdfViewerPane({required this.tab});

  final DocumentTabState tab;

  @override
  ConsumerState<_PdfViewerPane> createState() => _PdfViewerPaneState();
}

class _PdfViewerPaneState extends ConsumerState<_PdfViewerPane> {
  late PdfViewerController _controller;
  PdfTextSearcher? _searcher;
  VoidCallback? _searchListener;
  double _zoom = 1;
  int _page = 1;
  Offset? _lastPointerLocalPosition;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = PdfViewerController();
    _zoom = widget.tab.zoomScale;
    _page = widget.tab.currentPage;
    _controller.addListener(_syncViewerMetrics);
  }

  @override
  void didUpdateWidget(covariant _PdfViewerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _disposeSearcher();
      _controller.removeListener(_syncViewerMetrics);
      _createController();
      return;
    }

    if (oldWidget.tab.currentPage != widget.tab.currentPage &&
        _controller.isReady &&
        _controller.pageNumber != widget.tab.currentPage) {
      unawaited(_controller.goToPage(pageNumber: widget.tab.currentPage));
    }

    if (oldWidget.tab.searchQuery != widget.tab.searchQuery &&
        _searcher != null) {
      _searcher!.startTextSearch(
        widget.tab.searchQuery,
        searchImmediately: widget.tab.searchQuery.trim().isNotEmpty,
      );
    }
  }

  @override
  void dispose() {
    _disposeSearcher();
    _controller.removeListener(_syncViewerMetrics);
    super.dispose();
  }

  void _disposeSearcher() {
    if (_searchListener != null) {
      _searcher?.removeListener(_searchListener!);
    }
    _searcher?.dispose();
    _searchListener = null;
  }

  void _syncViewerMetrics() {
    if (!mounted || !_controller.isReady) {
      return;
    }
    setState(() {
      _zoom = _controller.currentZoom;
      _page = _controller.pageNumber ?? widget.tab.currentPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tab.isMissingFile) {
      return Center(
        child: SurfaceBlock(
          padding: const EdgeInsets.all(18),
          child: Text(
            widget.tab.missingFileMessage ?? 'This file is missing.',
            style: const TextStyle(
              color: WorkspaceColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: WorkspaceColors.canvas),
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: const TextSelectionThemeData(
            selectionColor: WorkspaceColors.selection,
          ),
        ),
        child: Listener(
          onPointerHover: _rememberPointerPosition,
          onPointerDown: _rememberPointerPosition,
          onPointerMove: _rememberPointerPosition,
          onPointerUp: _rememberPointerPosition,
          onPointerCancel: _rememberPointerPosition,
          child: PdfViewer.file(
            widget.tab.filePath,
            controller: _controller,
            initialPageNumber: widget.tab.currentPage,
            params: PdfViewerParams(
              backgroundColor: WorkspaceColors.viewerBackground,
              margin: 14,
              pageDropShadow: const BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
              maxImageBytesCachedOnMemory: 48 * 1024 * 1024,
              panEnabled: false,
              scaleEnabled: true,
              textSelectionParams: const PdfTextSelectionParams(
                enabled: true,
              ),
              interactionDelegateProvider: const PdfViewerScrollInteractionDelegateProviderPhysics(),
              onPageChanged: _onPageChanged,
              onViewerReady: _onViewerReady,
              pagePaintCallbacks: _searcher == null
                  ? const <PdfViewerPagePaintCallback>[]
                  : <PdfViewerPagePaintCallback>[
                      _searcher!.pageTextMatchPaintCallback,
                    ],
              viewerOverlayBuilder: _buildViewerOverlay,
            ),
          ),
        ),
      ),
    );
  }

  void _onPageChanged(int? page) {
    if (page == null) {
      return;
    }
    _page = page;
    unawaited(
      ref
          .read(workspaceNotifierProvider.notifier)
          .updateViewerState(
            tabId: widget.tab.id,
            currentPage: page,
            zoomScale: _controller.isReady
                ? _controller.currentZoom
                : widget.tab.zoomScale,
          ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    final PdfTextSearcher searcher = PdfTextSearcher(controller);
    if (widget.tab.searchQuery.trim().isNotEmpty) {
      searcher.startTextSearch(widget.tab.searchQuery, searchImmediately: true);
    }
    _searchListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    searcher.addListener(_searchListener!);
    final List<PdfOutlineNode> outline = await document.loadOutline();
    await ref
        .read(workspaceNotifierProvider.notifier)
        .setOutline(
          widget.tab.id,
          outline.map(_mapOutline).toList(growable: false),
        );
    await ref
        .read(workspaceNotifierProvider.notifier)
        .updateViewerState(
          tabId: widget.tab.id,
          pageCountHint: document.pages.length,
          zoomScale: controller.currentZoom,
        );
    if (mounted) {
      setState(() {
        _searcher = searcher;
        _zoom = controller.currentZoom;
        _page = controller.pageNumber ?? widget.tab.currentPage;
      });
    }
  }

  List<Widget> _buildViewerOverlay(
    BuildContext context,
    Size size,
    PdfViewerHandleLinkTap handleLinkTap,
  ) {
    return <Widget>[
      _PdfEdgeScrollbar(
        controller: _controller,
        axis: PdfScrollbarAxis.vertical,
        viewportSize: size,
      ),
      _PdfEdgeScrollbar(
        controller: _controller,
        axis: PdfScrollbarAxis.horizontal,
        viewportSize: size,
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 14,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _ViewerHud(
            page: _page,
            pageCount: widget.tab.pageCountHint,
            zoom: _zoom,
            onPreviousPage: _controller.isReady && _page > 1
                ? () => _controller.goToPage(pageNumber: _page - 1)
                : null,
            onNextPage:
                _controller.isReady &&
                    (widget.tab.pageCountHint == null ||
                        _page < widget.tab.pageCountHint!)
                ? () => _controller.goToPage(pageNumber: _page + 1)
                : null,
            onZoomOut: _controller.isReady ? _zoomOutAtPointer : null,
            onZoomIn: _controller.isReady ? _zoomInAtPointer : null,
            onSelectZoomPreset: _controller.isReady ? _applyZoomPreset : null,
          ),
        ),
      ),
    ];
  }

  void _rememberPointerPosition(PointerEvent event) {
    _lastPointerLocalPosition = event.localPosition;
  }

  Future<void> _zoomInAtPointer() async {
    await _controller.zoomUpOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      duration: const Duration(milliseconds: 180),
    );
    if (mounted) {
      setState(() => _zoom = _controller.currentZoom);
    }
  }

  Future<void> _zoomOutAtPointer() async {
    await _controller.zoomDownOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      duration: const Duration(milliseconds: 180),
    );
    if (mounted) {
      setState(() => _zoom = _controller.currentZoom);
    }
  }

  Future<void> _applyZoomPreset(_ZoomPreset preset) async {
    if (!_controller.isReady) {
      return;
    }

    switch (preset) {
      case _ZoomPreset.fitWidth:
        await _controller.goTo(
          _controller.calcMatrixFitWidthForPage(pageNumber: _page),
          duration: const Duration(milliseconds: 180),
        );
        break;
      case _ZoomPreset.fitPage:
        await _controller.goTo(
          _controller.calcMatrixForFit(pageNumber: _page),
          duration: const Duration(milliseconds: 180),
        );
        break;
      case _ZoomPreset.percent50:
        await _zoomOnPointer(0.5);
        break;
      case _ZoomPreset.percent75:
        await _zoomOnPointer(0.75);
        break;
      case _ZoomPreset.percent100:
        await _zoomOnPointer(1);
        break;
      case _ZoomPreset.percent125:
        await _zoomOnPointer(1.25);
        break;
      case _ZoomPreset.percent150:
        await _zoomOnPointer(1.5);
        break;
      case _ZoomPreset.percent200:
        await _zoomOnPointer(2);
        break;
    }

    if (mounted) {
      setState(() => _zoom = _controller.currentZoom);
    }
  }

  Future<void> _zoomOnPointer(double zoom) {
    return _controller.zoomOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      newZoom: _clampZoom(zoom),
      duration: const Duration(milliseconds: 180),
    );
  }

  double _clampZoom(double zoom) {
    return zoom.clamp(_controller.minScale, _controller.maxScale).toDouble();
  }

  Offset _lastPointerAnchor() {
    if (_lastPointerLocalPosition != null) {
      return _lastPointerLocalPosition!;
    }
    final Size size = _controller.viewSize;
    return Offset(size.width / 2, size.height / 2);
  }

  OutlineNodeState _mapOutline(PdfOutlineNode node) {
    return OutlineNodeState(
      title: node.title,
      pageNumber: node.dest?.pageNumber,
      children: node.children.map(_mapOutline).toList(growable: false),
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
    final borderSide = const BorderSide(color: WorkspaceColors.border, width: 0.5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WorkspaceColors.canvasRaised,
        border: Border(
          left: axis == PdfScrollbarAxis.vertical ? borderSide : BorderSide.none,
          top: axis == PdfScrollbarAxis.horizontal ? borderSide : BorderSide.none,
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
  });

  final int page;
  final int? pageCount;
  final double zoom;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final ValueChanged<_ZoomPreset>? onSelectZoomPreset;

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
            const SizedBox(width: 10),
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
          ],
        ),
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
  const _HudDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 16, color: WorkspaceColors.border);
  }
}
