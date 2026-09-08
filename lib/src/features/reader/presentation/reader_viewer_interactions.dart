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
    _precachePageSentences(page);
  }

  Future<void> _onViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
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
      final int readyPage = controller.pageNumber ?? widget.tab.currentPage;
      _metrics.value = _ReaderViewportMetrics(
        page: readyPage,
        zoom: controller.currentZoom,
      );
      _precachePageSentences(readyPage);
    } else {
      searcher.dispose();
    }
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
        colors: widget.colors,
      ),
      _PdfEdgeScrollbar(
        controller: _controller,
        axis: PdfScrollbarAxis.horizontal,
        viewportSize: size,
        colors: widget.colors,
      ),
    ];
  }

  Widget? _buildSelectionToolbar(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (!params.isTextSelectionEnabled ||
        !params.textSelectionDelegate.hasSelectedText) {
      return null;
    }
    _dismissSelectionMenu = params.dismissContextMenu;
    final ClarixThemeProfile profile =
        ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile();
    return ReaderSelectionToolbar(
      highlightColors: profile.highlightPalette,
      onCopy: () => unawaited(_copySelection(params)),
      onAskAi: () => unawaited(_askAiAboutSelection(params)),
      onNote: () => unawaited(_addNoteForSelection(params)),
      onBookmark: () => unawaited(_bookmarkSelection(params)),
      onReadAloud: () => unawaited(_readSelectionAloud(params)),
      onHighlight: (int color) =>
          unawaited(_highlightSelection(colorValue: color, params: params)),
      onMoreColors: () => unawaited(_chooseHighlightColor(params)),
    );
  }

  bool? _onViewerKey(
    PdfViewerKeyHandlerParams _,
    LogicalKeyboardKey key,
    bool isRealKeyPress,
  ) {
    if (key != LogicalKeyboardKey.escape || !isRealKeyPress) return null;
    unawaited(_clearActiveTextSelection());
    return true;
  }

  void _handlePointerUp(PointerUpEvent event) {
    _rememberPointerPosition(event);
    if (event.kind != PointerDeviceKind.mouse) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showAutomaticSelectionToolbar();
    });
  }

  void _showAutomaticSelectionToolbar() {
    if (!_controller.isReady ||
        !_controller.textSelectionDelegate.hasSelectedText) {
      return;
    }
    final Offset? globalPosition = _lastPointerGlobalPosition;
    if (globalPosition == null) return;
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final RenderBox? overlayBox =
        overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final Offset position = overlayBox.globalToLocal(globalPosition);
    final Size size = overlayBox.size;
    final Offset anchor =
        _controller.globalToLocal(globalPosition) ?? Offset.zero;
    final PdfViewerContextMenuBuilderParams params =
        PdfViewerContextMenuBuilderParams(
          isTextSelectionEnabled: true,
          anchorA: anchor,
          textSelectionDelegate: _controller.textSelectionDelegate,
          contextMenuFor: PdfViewerPart.selectedText,
          dismissContextMenu: _removeAutomaticSelectionToolbar,
        );
    final ClarixThemeProfile profile =
        ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile();
    _removeAutomaticSelectionToolbar();
    _automaticSelectionToolbar = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: (position.dx - 20).clamp(8.0, size.width - 8.0).toDouble(),
        top: (position.dy + 12).clamp(8.0, size.height - 8.0).toDouble(),
        child: ReaderSelectionToolbar(
          highlightColors: profile.highlightPalette,
          onCopy: () => unawaited(_copySelection(params)),
          onAskAi: () => unawaited(_askAiAboutSelection(params)),
          onNote: () => unawaited(_addNoteForSelection(params)),
          onBookmark: () => unawaited(_bookmarkSelection(params)),
          onReadAloud: () => unawaited(_readSelectionAloud(params)),
          onHighlight: (int color) =>
              unawaited(_highlightSelection(colorValue: color, params: params)),
          onMoreColors: () => unawaited(_chooseHighlightColor(params)),
        ),
      ),
    );
    overlay.insert(_automaticSelectionToolbar!);
  }

  void _removeAutomaticSelectionToolbar() {
    _automaticSelectionToolbar?.remove();
    _automaticSelectionToolbar = null;
  }

  Future<void> _copySelection(PdfViewerContextMenuBuilderParams params) async {
    await params.textSelectionDelegate.copyTextSelection();
    params.dismissContextMenu();
    _dismissSelectionMenu = null;
  }

  Future<void> _askAiAboutSelection(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    final String selectedText = await params.textSelectionDelegate
        .getSelectedText();
    await _dismissTextSelection(params);
    if (selectedText.trim().isEmpty) return;
    unawaited(
      ref
          .read(aiNotifierProvider.notifier)
          .sendPrompt(
            'Explain this selected passage from ${widget.tab.title}:\n\n'
            '“${selectedText.trim()}”',
            AiDocumentContext(
              tabId: widget.tab.id,
              documentId: widget.tab.documentId,
              title: widget.tab.title,
              filePath: widget.tab.filePath,
            ),
          ),
    );
  }

  Future<void> _readSelectionAloud(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    final Offset anchor = params.anchorA;
    await _dismissTextSelection(params);
    await _startReadAloud(anchor);
  }

  Future<void> _bookmarkSelection(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    final String selectedText = await params.textSelectionDelegate
        .getSelectedText();
    final List<PdfPageTextRange> ranges = await params.textSelectionDelegate
        .getSelectedTextRanges();
    await _dismissTextSelection(params);
    if (ranges.isEmpty) return;
    final String normalized = selectedText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final String label = normalized.length <= 72
        ? normalized
        : '${normalized.substring(0, 69)}…';
    if (label.isEmpty) return;
    await ref
        .read(workspaceNotifierProvider.notifier)
        .addBookmark(
          tabId: widget.tab.id,
          pageNumber: ranges.first.pageNumber,
          label: label,
        );
  }

  Future<void> _addNoteForSelection(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    final String selectedText = await params.textSelectionDelegate
        .getSelectedText();
    final List<PdfPageTextRange> ranges = await params.textSelectionDelegate
        .getSelectedTextRanges();
    await _dismissTextSelection(params);
    if (!mounted || selectedText.trim().isEmpty || ranges.isEmpty) return;
    final TextEditingController controller = TextEditingController();
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add note'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                selectedText.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'Write a note'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || note.trim().isEmpty) return;
    final PdfPageTextRange range = ranges.first;
    final ClarixThemeProfile profile =
        ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile();
    await ref
        .read(workspaceNotifierProvider.notifier)
        .addNote(
          tabId: widget.tab.id,
          pageNumber: range.pageNumber,
          note: note,
          selectedText: selectedText,
          pageRects: _pageRectsForRange(range),
          colorValue: _highlightColorWithOpacity(
            profile.highlightColor,
            profile.highlightOpacity,
          ),
        );
  }

  Future<void> _chooseHighlightColor(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    final ClarixThemeProfile profile =
        ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile();
    int selectedColor = profile.highlightColor;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('More highlight colours'),
          content: _ColourWheel(
            color: Color(selectedColor),
            onChanged: (Color color) =>
                setState(() => selectedColor = color.toARGB32()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selectedColor),
              child: const Text('Highlight'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final List<int> customColors = List<int>.from(profile.customHighlightColors)
      ..remove(picked)
      ..add(picked);
    while (customColors.length > ClarixThemeProfile.maxCustomHighlightColors) {
      customColors.removeAt(0);
    }
    await ref
        .read(clarixThemeProvider.notifier)
        .setProfile(
          profile.copyWith(
            highlightColor: picked,
            customHighlightColors: customColors,
          ),
        );
    await _highlightSelection(colorValue: picked, params: params);
  }

  Future<void> _dismissTextSelection(
    PdfViewerContextMenuBuilderParams params,
  ) async {
    params.dismissContextMenu();
    _dismissSelectionMenu = null;
    await params.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _clearActiveTextSelection() async {
    _removeAutomaticSelectionToolbar();
    _dismissSelectionMenu?.call();
    _dismissSelectionMenu = null;
    if (_controller.isReady) {
      await _controller.textSelectionDelegate.clearTextSelection();
    }
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final DocumentAnnotation annotation in widget.annotations) {
      if (annotation.pageNumber != page.pageNumber ||
          (annotation.kind != AnnotationKind.highlight &&
              annotation.kind != AnnotationKind.note)) {
        continue;
      }
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
        if (annotation.kind == AnnotationKind.highlight) {
          canvas.drawRect(
            rendered,
            Paint()..color = Color(annotation.colorValue),
          );
        } else {
          final Rect marker = Rect.fromCenter(
            center: Offset(rendered.right, rendered.top),
            width: 15,
            height: 15,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(marker, const Radius.circular(4)),
            Paint()..color = const Color(0xFFF5C451),
          );
          canvas.drawCircle(
            marker.center,
            2,
            Paint()..color = const Color(0xFF5A430D),
          );
        }
      }
    }
  }

  bool _onViewerTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.tap) return false;
    unawaited(_clearActiveTextSelection());
    if (_handleReadAloudSkipTap(details.documentPosition)) return true;
    for (final DocumentAnnotation annotation in widget.annotations) {
      if (annotationHitAreaContains(
        _annotationHitAreas[annotation.id] ?? const <Rect>[],
        details.documentPosition,
      )) {
        if (annotation.kind == AnnotationKind.highlight) {
          unawaited(_showHighlightEditor(annotation));
        } else {
          unawaited(_showNoteEditor(annotation));
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _showHighlightEditor(DocumentAnnotation annotation) async {
    final ClarixThemeProfile profile =
        ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile();
    final int? action = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Edit highlight'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, -1),
            child: const Text('Delete'),
          ),
          ...profile.highlightPalette.map(
            (int color) => IconButton(
              tooltip: 'Change highlight colour',
              onPressed: () => Navigator.pop(context, color),
              icon: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (action == -1) {
      final String groupId = annotation.id.split(':').first;
      await ref
          .read(workspaceNotifierProvider.notifier)
          .removeAnnotation(widget.tab.id, groupId);
    } else if (action != null) {
      final String groupId = annotation.id.split(':').first;
      await ref
          .read(workspaceNotifierProvider.notifier)
          .updateHighlightColor(
            tabId: widget.tab.id,
            annotationId: groupId,
            colorValue: _highlightColorWithOpacity(
              action,
              profile.highlightOpacity,
            ),
          );
    }
  }

  Future<void> _showNoteEditor(DocumentAnnotation annotation) async {
    final TextEditingController controller = TextEditingController(
      text: annotation.note,
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Note'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Delete'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value.trim().isEmpty) {
      await ref
          .read(workspaceNotifierProvider.notifier)
          .removeAnnotation(widget.tab.id, annotation.id);
      return;
    }
    await ref
        .read(workspaceNotifierProvider.notifier)
        .updateAnnotationNote(
          tabId: widget.tab.id,
          annotationId: annotation.id,
          note: value,
        );
  }

  void _rememberPointerPosition(PointerEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  static const double _chromeEdgeZone = 56;

  void _onFullscreenChromeHover(Offset localPosition, Size size) {
    final bool nearTop = localPosition.dy <= _chromeEdgeZone;
    final bool nearBottom = localPosition.dy >= size.height - _chromeEdgeZone;
    _hideChromeTimer?.cancel();
    if (nearTop != _showTopChrome || nearBottom != _showBottomChrome) {
      _updateState(() {
        _showTopChrome = nearTop;
        _showBottomChrome = nearBottom;
      });
    }
    if (!nearTop && !nearBottom) {
      _scheduleHideFullscreenChrome();
    }
  }

  void _scheduleHideFullscreenChrome() {
    _hideChromeTimer?.cancel();
    _hideChromeTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _updateState(() {
        _showTopChrome = false;
        _showBottomChrome = false;
      });
    });
  }

  void _rememberTrackpadZoomStart(PointerPanZoomStartEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  void _rememberTrackpadZoomPosition(PointerPanZoomUpdateEvent event) {
    // PointerPanZoomUpdateEvent.position is the stationary mouse cursor.
    // event.pan is two-finger content translation, not cursor movement.
    _lastPointerGlobalPosition = event.position;
  }

  Future<void> _highlightSelection({
    int? colorValue,
    PdfViewerContextMenuBuilderParams? params,
  }) async {
    final profile = ref.read(clarixThemeProvider).value;
    final int resolvedColor = _highlightColorWithOpacity(
      colorValue ?? profile?.highlightColor ?? 0xFFFFD54F,
      profile?.highlightOpacity ?? ClarixThemeProfile.defaultHighlightOpacity,
    );
    final delegate =
        params?.textSelectionDelegate ?? _controller.textSelectionDelegate;
    final List<PdfPageTextRange> ranges = await delegate
        .getSelectedTextRanges();
    final String selectedText = await delegate.getSelectedText();
    final String highlightGroup =
        'highlight_${DateTime.now().microsecondsSinceEpoch}';
    for (final PdfPageTextRange range in ranges) {
      final List<Rect> pageRects = _pageRectsForRange(range);
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
    if (params != null) {
      await _dismissTextSelection(params);
    } else {
      await _clearActiveTextSelection();
    }
  }

  List<Rect> _pageRectsForRange(PdfPageTextRange range) =>
      _selectionLineRects(range)
          .map(
            (PdfRect bounds) => Rect.fromLTRB(
              bounds.left,
              bounds.bottom,
              bounds.right,
              bounds.top,
            ),
          )
          .toList(growable: false);

  int _highlightColorWithOpacity(int color, double opacity) =>
      ((opacity * 255).round() << 24) | (color & 0x00FFFFFF);

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
      duration: readerZoomAnimationDuration,
    );
    await _persistViewerState();
  }

  Future<void> _zoomOutAtPointer() async {
    await _controller.zoomDownOnLocalPosition(
      localPosition: _lastPointerAnchor(),
      duration: readerZoomAnimationDuration,
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
          duration: readerZoomAnimationDuration,
        );
        break;
      case _ZoomPreset.fitPage:
        await _controller.goTo(
          _controller.calcMatrixForFit(pageNumber: _page),
          duration: readerZoomAnimationDuration,
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
      duration: readerZoomAnimationDuration,
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
