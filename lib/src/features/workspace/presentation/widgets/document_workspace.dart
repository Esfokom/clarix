import 'dart:async';

import 'package:flutter/gestures.dart';
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

class DocumentWorkspace extends ConsumerWidget {
  const DocumentWorkspace({
    required this.state,
    required this.activeTab,
    super.key,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: <Widget>[
        _TabStrip(state: state, activeTab: activeTab),
        Expanded(
          child: _PdfViewerPane(
            tab: activeTab,
            documentRef: ref.watch(pdfDocumentRefProvider(activeTab.filePath)),
            annotations:
                state.documentMetadata[activeTab.documentId]?.annotations ??
                const <DocumentAnnotation>[],
          ),
        ),
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
    final DocumentMetadata? metadata =
        widget.state.documentMetadata[widget.activeTab.documentId];
    final bool bookmarked =
        metadata?.bookmarks.any(
          (DocumentBookmark item) =>
              item.pageNumber == widget.activeTab.currentPage,
        ) ??
        false;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 760;
        return Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: WorkspaceColors.canvasRaised,
            border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
          ),
          child: Row(
            children: <Widget>[
              Tooltip(
                message: 'Open PDF (Ctrl+O)',
                child: ShadIconButton.ghost(
                  width: 32,
                  height: 32,
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.folderOpen, size: 16),
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .pickAndOpenPdfs(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.state.session.tabs.length,
                  separatorBuilder: (_, int index) => const SizedBox(width: 4),
                  itemBuilder: (BuildContext context, int index) {
                    final DocumentTabState tab =
                        widget.state.session.tabs[index];
                    final bool selected = tab.id == widget.activeTab.id;
                    return GestureDetector(
                      onTap: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setActiveTab(tab.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? WorkspaceColors.panelRaised
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: selected
                                ? WorkspaceColors.accentBorder
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              tab.isMissingFile
                                  ? LucideIcons.triangleAlert
                                  : LucideIcons.fileText,
                              size: 13,
                              color: tab.isMissingFile
                                  ? WorkspaceColors.warning
                                  : WorkspaceColors.textMuted,
                            ),
                            const SizedBox(width: 7),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? 96 : 160,
                              ),
                              child: Text(
                                tab.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WorkspaceColors.textStrong,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => ref
                                  .read(workspaceNotifierProvider.notifier)
                                  .closeTab(tab.id),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 12,
                                  color: WorkspaceColors.textFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (!compact)
                SizedBox(
                  width: 190,
                  child: ShadInput(
                    controller: _searchController,
                    placeholder: const Text('Search document'),
                    leading: const Icon(LucideIcons.search, size: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onSubmitted: _submitSearch,
                  ),
                )
              else
                _ToolbarButton(
                  tooltip: 'Search document (Ctrl+F)',
                  icon: LucideIcons.search,
                  onPressed: _showSearchDialog,
                ),
              const SizedBox(width: 4),
              _ToolbarButton(
                tooltip: bookmarked
                    ? 'Remove page bookmark'
                    : 'Bookmark current page',
                icon: bookmarked
                    ? LucideIcons.bookmarkCheck
                    : LucideIcons.bookmark,
                active: bookmarked,
                onPressed: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .toggleBookmark(
                      widget.activeTab.id,
                      widget.activeTab.currentPage,
                    ),
              ),
              _ToolbarButton(
                tooltip: 'Add note to current page',
                icon: LucideIcons.stickyNote,
                onPressed: _showNoteDialog,
              ),
              _ToolbarButton(
                tooltip: widget.state.composerExpanded
                    ? 'Close AI assistant'
                    : 'Open local AI assistant',
                icon: LucideIcons.sparkles,
                active: widget.state.composerExpanded,
                onPressed: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .toggleComposerExpanded(),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 4),
                ShadBadge.secondary(
                  child: Text(
                    widget.activeTab.indexStatus.name,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _submitSearch(String value) {
    ref
        .read(workspaceNotifierProvider.notifier)
        .setSearchQuery(widget.activeTab.id, value.trim());
  }

  Future<void> _showSearchDialog() async {
    final String? query = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController controller = TextEditingController(
          text: _searchController.text,
        );
        return AlertDialog(
          backgroundColor: WorkspaceColors.panel,
          title: const Text(
            'Search document',
            style: TextStyle(color: WorkspaceColors.textStrong),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: WorkspaceColors.textStrong),
            onSubmitted: (String value) => Navigator.of(context).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    if (query != null) {
      _searchController.text = query;
      _submitSearch(query);
    }
  }

  Future<void> _showNoteDialog() async {
    final TextEditingController controller = TextEditingController();
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: WorkspaceColors.panel,
        title: Text(
          'Note on page ${widget.activeTab.currentPage}',
          style: const TextStyle(color: WorkspaceColors.textStrong),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: WorkspaceColors.textStrong),
          decoration: const InputDecoration(hintText: 'Write a local note'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note != null) {
      await ref
          .read(workspaceNotifierProvider.notifier)
          .addNote(
            tabId: widget.activeTab.id,
            pageNumber: widget.activeTab.currentPage,
            note: note,
          );
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        width: 32,
        height: 32,
        padding: EdgeInsets.zero,
        backgroundColor: active ? WorkspaceColors.accentSoft : null,
        icon: Icon(icon, size: 15),
        onPressed: onPressed,
      ),
    );
  }
}

class _PdfViewerPane extends ConsumerStatefulWidget {
  const _PdfViewerPane({
    required this.tab,
    required this.documentRef,
    required this.annotations,
  });

  final DocumentTabState tab;
  final PdfDocumentRefFile documentRef;
  final List<DocumentAnnotation> annotations;

  @override
  ConsumerState<_PdfViewerPane> createState() => _PdfViewerPaneState();
}

class _ReaderViewportMetrics {
  const _ReaderViewportMetrics({required this.page, required this.zoom});

  final int page;
  final double zoom;
}

class _PdfViewerPaneState extends ConsumerState<_PdfViewerPane> {
  late PdfViewerController _controller;
  late ValueNotifier<_ReaderViewportMetrics> _metrics;
  PdfTextSearcher? _searcher;
  VoidCallback? _searchListener;
  Timer? _viewerStateDebounce;
  Offset? _lastPointerGlobalPosition;

  int get _page => _metrics.value.page;
  double get _zoom => _metrics.value.zoom;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = PdfViewerController();
    _metrics = ValueNotifier<_ReaderViewportMetrics>(
      _ReaderViewportMetrics(
        page: widget.tab.currentPage,
        zoom: widget.tab.zoomScale,
      ),
    );
    _controller.addListener(_syncViewerMetrics);
  }

  @override
  void didUpdateWidget(covariant _PdfViewerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _disposeSearcher();
      _controller.removeListener(_syncViewerMetrics);
      _metrics.dispose();
      _viewerStateDebounce?.cancel();
      _lastPointerGlobalPosition = null;
      _createController();
      return;
    }

    if (!identical(oldWidget.annotations, widget.annotations) &&
        _controller.isReady) {
      _controller.invalidate();
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
    _viewerStateDebounce?.cancel();
    _disposeSearcher();
    _controller.removeListener(_syncViewerMetrics);
    _metrics.dispose();
    super.dispose();
  }

  void _disposeSearcher() {
    if (_searchListener != null) {
      _searcher?.removeListener(_searchListener!);
    }
    _searcher?.dispose();
    _searcher = null;
    _searchListener = null;
  }

  void _syncViewerMetrics() {
    if (!mounted || !_controller.isReady) {
      return;
    }
    final _ReaderViewportMetrics next = _ReaderViewportMetrics(
      page: _controller.pageNumber ?? widget.tab.currentPage,
      zoom: _controller.currentZoom,
    );
    if (next.page != _metrics.value.page || next.zoom != _metrics.value.zoom) {
      _metrics.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tab.isMissingFile) {
      return Center(
        child: SurfaceBlock(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                LucideIcons.fileQuestion,
                color: WorkspaceColors.warning,
                size: 24,
              ),
              const SizedBox(height: 10),
              Text(
                widget.tab.missingFileMessage ?? 'This file is missing.',
                style: const TextStyle(
                  color: WorkspaceColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .locateMissingFile(widget.tab.id),
                icon: const Icon(LucideIcons.folderSearch, size: 15),
                label: const Text('Locate file'),
              ),
            ],
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
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Listener(
                onPointerHover: _rememberPointerPosition,
                onPointerDown: _rememberPointerPosition,
                onPointerMove: _rememberPointerPosition,
                onPointerUp: _rememberPointerPosition,
                onPointerCancel: _rememberPointerPosition,
                onPointerPanZoomStart: _rememberTrackpadZoomStart,
                onPointerPanZoomUpdate: _rememberTrackpadZoomPosition,
                child: ReaderCursorLockedPdfRegion(
                  controller: _controller,
                  builder:
                      (BuildContext context, ReaderCursorLockedPdfInput input) {
                        return PdfViewer(
                          widget.documentRef,
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
                            limitRenderingCache: true,
                            maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
                            horizontalCacheExtent: 0.5,
                            verticalCacheExtent: 0.75,
                            panEnabled: true,
                            scaleEnabled: input.pdfrxScaleEnabled,
                            scaleByPointerScale: readerPointerZoomSensitivity,
                            textSelectionParams: const PdfTextSelectionParams(
                              enabled: true,
                            ),
                            interactionDelegateProvider:
                                input.interactionDelegateProvider,
                            onInteractionEnd: (_) => _persistViewerState(),
                            onPageChanged: _onPageChanged,
                            onViewerReady: _onViewerReady,
                            pagePaintCallbacks: <PdfViewerPagePaintCallback>[
                              _paintAnnotations,
                              if (_searcher != null)
                                _searcher!.pageTextMatchPaintCallback,
                            ],
                            viewerOverlayBuilder: _buildViewerOverlay,
                          ),
                        );
                      },
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: IgnorePointer(
                ignoring: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ValueListenableBuilder<_ReaderViewportMetrics>(
                    valueListenable: _metrics,
                    builder:
                        (
                          BuildContext context,
                          _ReaderViewportMetrics metrics,
                          Widget? child,
                        ) {
                          return _ViewerHud(
                            page: metrics.page,
                            pageCount: widget.tab.pageCountHint,
                            zoom: metrics.zoom,
                            onPreviousPage:
                                _controller.isReady && metrics.page > 1
                                ? () => _controller.goToPage(
                                    pageNumber: metrics.page - 1,
                                  )
                                : null,
                            onNextPage:
                                _controller.isReady &&
                                    (widget.tab.pageCountHint == null ||
                                        metrics.page <
                                            widget.tab.pageCountHint!)
                                ? () => _controller.goToPage(
                                    pageNumber: metrics.page + 1,
                                  )
                                : null,
                            onZoomOut: _controller.isReady
                                ? _zoomOutAtPointer
                                : null,
                            onZoomIn: _controller.isReady
                                ? _zoomInAtPointer
                                : null,
                            onSelectZoomPreset: _controller.isReady
                                ? _applyZoomPreset
                                : null,
                            onHighlightSelection: _controller.isReady
                                ? _highlightSelection
                                : null,
                          );
                        },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPageChanged(int? page) {
    if (page == null) {
      return;
    }
    _metrics.value = _ReaderViewportMetrics(
      page: page,
      zoom: _controller.isReady ? _controller.currentZoom : _zoom,
    );
    _queueViewerStatePersistence();
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
      setState(() => _searcher = searcher);
      _metrics.value = _ReaderViewportMetrics(
        page: controller.pageNumber ?? widget.tab.currentPage,
        zoom: controller.currentZoom,
      );
    } else {
      searcher.dispose();
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
    ];
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final DocumentAnnotation annotation in widget.annotations) {
      if (annotation.pageNumber != page.pageNumber ||
          annotation.kind != AnnotationKind.highlight) {
        continue;
      }
      final Paint paint = Paint()..color = Color(annotation.colorValue);
      for (final Rect stored in annotation.pageRects) {
        final PdfRect bounds = PdfRect(
          stored.left,
          stored.bottom,
          stored.right,
          stored.top,
        );
        final Rect rendered = bounds
            .toRect(page: page, scaledPageSize: pageRect.size)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRect(rendered, paint);
      }
    }
  }

  void _rememberPointerPosition(PointerEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  void _rememberTrackpadZoomStart(PointerPanZoomStartEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  void _rememberTrackpadZoomPosition(PointerPanZoomUpdateEvent event) {
    // PointerPanZoomUpdateEvent.position is the stationary mouse cursor.
    // event.pan is two-finger content translation, not cursor movement.
    _lastPointerGlobalPosition = event.position;
  }

  Future<void> _highlightSelection() async {
    final List<PdfPageTextRange> ranges = await _controller
        .textSelectionDelegate
        .getSelectedTextRanges();
    for (final PdfPageTextRange range in ranges) {
      final PdfRect bounds = range.bounds;
      await ref
          .read(workspaceNotifierProvider.notifier)
          .addHighlight(
            tabId: widget.tab.id,
            pageNumber: range.pageNumber,
            pageRect: Rect.fromLTRB(
              bounds.left,
              bounds.bottom,
              bounds.right,
              bounds.top,
            ),
            selectedText: range.text,
          );
    }
    await _controller.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _zoomInAtPointer() async {
    await _controller.zoomUpOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      duration: Duration.zero,
    );
    await _persistViewerState();
  }

  Future<void> _zoomOutAtPointer() async {
    await _controller.zoomDownOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      duration: Duration.zero,
    );
    await _persistViewerState();
  }

  Future<void> _applyZoomPreset(_ZoomPreset preset) async {
    if (!_controller.isReady) {
      return;
    }

    switch (preset) {
      case _ZoomPreset.fitWidth:
        await _controller.goTo(
          _controller.calcMatrixFitWidthForPage(pageNumber: _page),
          duration: const Duration(milliseconds: 120),
        );
        break;
      case _ZoomPreset.fitPage:
        await _controller.goTo(
          _controller.calcMatrixForFit(pageNumber: _page),
          duration: const Duration(milliseconds: 120),
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

    await _persistViewerState();
  }

  Future<void> _zoomOnPointer(double zoom) {
    return _controller.zoomOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      newZoom: _clampZoom(zoom),
      duration: Duration.zero,
    );
  }

  double _clampZoom(double zoom) {
    return zoom.clamp(_controller.minScale, _controller.maxScale).toDouble();
  }

  Offset? _trackedPointerAnchor() {
    if (!_controller.isReady) {
      return null;
    }
    final Offset? global = _lastPointerGlobalPosition;
    if (global == null) {
      return null;
    }
    final Offset? local = _controller.globalToLocal(global);
    if (local == null || !local.dx.isFinite || !local.dy.isFinite) {
      return null;
    }
    final Size size = _controller.viewSize;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > size.width ||
        local.dy > size.height) {
      return null;
    }
    return local;
  }

  Offset _lastPointerAnchor() {
    final Size size = _controller.viewSize;
    return _trackedPointerAnchor() ?? size.center(Offset.zero);
  }

  void _queueViewerStatePersistence() {
    _viewerStateDebounce?.cancel();
    _viewerStateDebounce = Timer(
      const Duration(milliseconds: 180),
      _persistViewerState,
    );
  }

  Future<void> _persistViewerState() async {
    _viewerStateDebounce?.cancel();
    if (!mounted || !_controller.isReady) {
      return;
    }
    _syncViewerMetrics();
    await ref
        .read(workspaceNotifierProvider.notifier)
        .updateViewerState(
          tabId: widget.tab.id,
          currentPage: _page,
          zoomScale: _zoom,
        );
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
            const SizedBox(width: 10),
            const _HudDivider(),
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
