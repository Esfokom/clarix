part of 'reader_viewer_pane.dart';

bool annotationHitAreaContains(Iterable<Rect> areas, Offset documentPosition) =>
    areas.any((Rect area) => area.inflate(3).contains(documentPosition));

extension _ReaderViewerInteractions on _PdfViewerPaneState {
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
    _pageSurface.refresh();
    final PdfTextSearcher searcher = PdfTextSearcher(controller);
    if (widget.tab.searchQuery.trim().isNotEmpty) {
      _pendingSearchQuery = widget.tab.searchQuery;
      searcher.startTextSearch(widget.tab.searchQuery, searchImmediately: true);
    }
    _searchListener = () {
      _updateState(() {
        if (!searcher.isSearching) {
          _pendingSearchQuery = null;
        }
      });
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
      _updateState(() => _searcher = searcher);
      _metrics.value = _ReaderViewportMetrics(
        page: controller.pageNumber ?? widget.tab.currentPage,
        zoom: controller.currentZoom,
      );
    } else {
      searcher.dispose();
    }
  }

  Future<EditorSessionController?> _openNativeEditor(
    String tabId,
    String sourcePath,
  ) async {
    try {
      final controller = await ref
          .read(editorSessionRegistryProvider)
          .open(tabId: tabId, sourcePath: sourcePath);
      if (!mounted || widget.tab.id != tabId) {
        await ref.read(editorSessionRegistryProvider).close(tabId);
        return null;
      }
      _pageSceneLifecycle?.dispose();
      _pageSceneLifecycle = PageSceneLifecycle(
        surface: _pageSurface,
        controller: controller,
      )..start();
      _updateState();
      return controller;
    } catch (error) {
      ref.read(workspaceNotifierProvider.notifier).reportPdfEditFailure(error);
      return null;
    }
  }

  Future<void> _toggleTextEditing() async {
    final notifier = ref.read(workspaceNotifierProvider.notifier);
    final currentTool = ref
        .read(workspaceNotifierProvider)
        .value
        ?.session
        .rightToolWindow;
    final isCurrentlyEditing = currentTool == RightToolWindow.textFormat;

    if (!isCurrentlyEditing) {
      final controller =
          ref.read(editorSessionRegistryProvider)[widget.tab.id] ??
          await _openNativeEditor(widget.tab.id, widget.tab.filePath);
      if (controller == null) return;
      await notifier.selectRightToolWindow(RightToolWindow.textFormat);
    } else {
      final controller = ref.read(editorSessionRegistryProvider)[widget.tab.id];
      if (controller != null && controller.state.selection != null) {
        controller.updateSelection(null);
      }
      await notifier.selectRightToolWindow(RightToolWindow.document);
    }
    _updateState();
  }

  bool get _shouldShowSearchOverlay =>
      widget.tab.searchQuery.trim().isNotEmpty && _searcher != null;

  bool get _isSearchInProgress =>
      _searcher?.isSearching == true ||
      _pendingSearchQuery == widget.tab.searchQuery;

  bool get _canGoToPreviousMatch {
    final PdfTextSearcher? searcher = _searcher;
    return searcher != null &&
        searcher.matches.isNotEmpty &&
        (searcher.currentIndex ?? 0) > 0;
  }

  bool get _canGoToNextMatch {
    final PdfTextSearcher? searcher = _searcher;
    return searcher != null &&
        searcher.matches.isNotEmpty &&
        (searcher.currentIndex ?? -1) + 1 < searcher.matches.length;
  }

  Future<void> _goToPreviousSearchMatch() async {
    await _searcher?.goToPrevMatch();
    _updateState();
  }

  Future<void> _goToNextSearchMatch() async {
    await _searcher?.goToNextMatch();
    _updateState();
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
        final Rect documentRect = bounds.toRectInDocument(
          page: page,
          pageRect: pageRect,
        );
        _annotationHitAreas
            .putIfAbsent(annotation.id, () => <Rect>[])
            .add(documentRect);
        canvas.drawRect(rendered, paint);
      }
    }
  }

  bool _onViewerTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.tap) return false;
    for (final DocumentAnnotation annotation in widget.annotations) {
      if (annotation.kind == AnnotationKind.highlight &&
          annotationHitAreaContains(
            _annotationHitAreas[annotation.id] ?? const <Rect>[],
            details.documentPosition,
          )) {
        unawaited(_showHighlightEditor(annotation));
        return true;
      }
    }
    return false;
  }

  Future<void> _showHighlightEditor(DocumentAnnotation annotation) async {
    final String? action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit highlight'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'yellow'),
            child: const Text('Yellow'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'blue'),
            child: const Text('Blue'),
          ),
        ],
      ),
    );
    if (action == 'delete') {
      final String groupId = annotation.id.split(':').first;
      await ref
          .read(workspaceNotifierProvider.notifier)
          .removeAnnotation(widget.tab.id, groupId);
    } else if (action == 'yellow' || action == 'blue') {
      final String groupId = annotation.id.split(':').first;
      await ref
          .read(workspaceNotifierProvider.notifier)
          .updateHighlightColor(
            tabId: widget.tab.id,
            annotationId: groupId,
            colorValue: action == 'yellow' ? 0x66FFD54F : 0x668EC5FF,
          );
    }
  }

  void _rememberPointerPosition(PointerEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  Future<void> _showSelectionMenuAfterDrag(PointerUpEvent event) async {
    final Offset? start = _selectionDragStart;
    _selectionDragStart = null;
    if (start == null || (event.localPosition - start).distance < 4) return;
    if (!_controller.isReady) return;
    final ranges = await _controller.textSelectionDelegate
        .getSelectedTextRanges();
    if (!mounted || ranges.isEmpty) return;
    _updateState(
      () => _selectionMenuPosition = event.localPosition.translate(8, 8),
    );
  }

  void _updateSelectionAutoPan(PointerMoveEvent event) {
    if (_selectionDragStart == null ||
        event.buttons == 0 ||
        !_controller.isReady) {
      _stopSelectionAutoPan();
      return;
    }
    _selectionAutoPanPointer = event.localPosition;
    const edge = 32.0;
    final Size size = _controller.viewSize;
    final Offset point = event.localPosition;
    final bool nearEdge =
        point.dx < edge ||
        point.dx > size.width - edge ||
        point.dy < edge ||
        point.dy > size.height - edge;
    if (nearEdge && _selectionAutoPanTimer == null) {
      _selectionAutoPanTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _autoPanSelection(),
      );
    } else if (!nearEdge) {
      _stopSelectionAutoPan();
    }
  }

  void _autoPanSelection() {
    final Offset? point = _selectionAutoPanPointer;
    if (point == null || !_controller.isReady) return;
    const edge = 32.0;
    const maxSpeed = 12.0;
    final Size size = _controller.viewSize;
    double velocity(double value, double extent) {
      if (value < edge) return maxSpeed * (1 - value / edge);
      if (value > extent - edge) {
        return -maxSpeed * (1 - (extent - value) / edge);
      }
      return 0;
    }

    final double dx = velocity(point.dx, size.width);
    final double dy = velocity(point.dy, size.height);
    if (dx == 0 && dy == 0) return;
    final matrix = _controller.value.clone()
      ..setEntry(0, 3, _controller.value.entry(0, 3) + dx)
      ..setEntry(1, 3, _controller.value.entry(1, 3) + dy);
    _controller.value = _controller.makeMatrixInSafeRange(
      matrix,
      forceClamp: true,
    );
  }

  void _stopSelectionAutoPan() {
    _selectionAutoPanTimer?.cancel();
    _selectionAutoPanTimer = null;
    _selectionAutoPanPointer = null;
  }

  Future<void> _copyCurrentSelection() async {
    final String text = await _controller.textSelectionDelegate
        .getSelectedText();
    await Clipboard.setData(ClipboardData(text: text));
  }

  void _rememberTrackpadZoomStart(PointerPanZoomStartEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  void _rememberTrackpadZoomPosition(PointerPanZoomUpdateEvent event) {
    // PointerPanZoomUpdateEvent.position is the stationary mouse cursor.
    // event.pan is two-finger content translation, not cursor movement.
    _lastPointerGlobalPosition = event.position;
  }

  Widget? _buildSelectionContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (params.contextMenuFor != PdfViewerPart.selectedText) return null;
    return Material(
      color: widget.colors.panelRaised,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton.icon(
              onPressed: () async {
                final text = await params.textSelectionDelegate
                    .getSelectedText();
                await Clipboard.setData(ClipboardData(text: text));
                params.dismissContextMenu();
              },
              icon: const Icon(LucideIcons.copy, size: 14),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: () async {
                await _addNamedBookmark();
                params.dismissContextMenu();
              },
              icon: const Icon(LucideIcons.bookmarkPlus, size: 14),
              label: const Text('Bookmark'),
            ),
            for (final int color in const <int>[
              0x66FFD54F,
              0x6686EFAC,
              0x668EC5FF,
            ])
              IconButton(
                tooltip: 'Highlight',
                onPressed: () async {
                  await _highlightSelection(colorValue: color);
                  params.dismissContextMenu();
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
            TextButton(
              onPressed: () {
                _updateState(() => _colorInspectorOpen = true);
                params.dismissContextMenu();
              },
              child: const Text('More colours'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNamedBookmark() async {
    final controller = TextEditingController(text: 'Page $_page');
    final String? label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add bookmark'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label != null) {
      await ref
          .read(workspaceNotifierProvider.notifier)
          .addBookmark(tabId: widget.tab.id, pageNumber: _page, label: label);
    }
  }

  Future<void> _highlightSelection({int? colorValue}) async {
    final profile = ref.read(clarixThemeProvider).value;
    final int resolvedColor =
        colorValue ??
        (((profile?.highlightOpacity ?? 0.4) * 255).round() << 24) |
            (profile?.highlightColor ?? 0xFFFFD54F);
    final List<PdfPageTextRange> ranges = await _controller
        .textSelectionDelegate
        .getSelectedTextRanges();
    final String selectedText = await _controller.textSelectionDelegate
        .getSelectedText();
    final String highlightGroup =
        'highlight_${DateTime.now().microsecondsSinceEpoch}';
    for (final PdfPageTextRange range in ranges) {
      final List<Rect> pageRects = _selectionLineRects(range)
          .map(
            (bounds) => Rect.fromLTRB(
              bounds.left,
              bounds.bottom,
              bounds.right,
              bounds.top,
            ),
          )
          .toList(growable: false);
      if (pageRects.isNotEmpty) {
        await ref
            .read(workspaceNotifierProvider.notifier)
            .addHighlight(
              tabId: widget.tab.id,
              pageNumber: range.pageNumber,
              pageRects: pageRects,
              selectedText: selectedText,
              colorValue: resolvedColor,
              highlightId: '$highlightGroup:${range.pageNumber}',
            );
      }
    }
    await _controller.textSelectionDelegate.clearTextSelection();
    _updateState(() => _selectionMenuPosition = null);
  }

  List<PdfRect> _selectionLineRects(PdfPageTextRange range) {
    final List<PdfRect> lines = <PdfRect>[];
    for (int index = range.start; index < range.end; index++) {
      final PdfRect rect = range.pageText.charRects[index];
      if (rect.isEmpty) continue;
      if (lines.isNotEmpty &&
          (lines.last.top - rect.top).abs() < 2 &&
          (lines.last.bottom - rect.bottom).abs() < 2) {
        lines[lines.length - 1] = lines.last.merge(rect);
      } else {
        lines.add(rect);
      }
    }
    return lines;
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

// reader-interactions-anchor
