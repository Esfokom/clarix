import 'dart:async';
import 'dart:io';

// ignore_for_file: unused_element, unused_element_parameter, unused_local_variable

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/models.dart';
import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../application/pdf_editing_controller.dart';
import '../../application/workspace_providers.dart';
import '../../domain/pdf_edit_session.dart';
import '../../domain/pdf_page_object.dart';
import '../../domain/pdf_text_types.dart';
import '../../domain/workspace_feature_state.dart';
import 'pdf_text_editor_overlay.dart';
import 'pdf_object_transform_overlay.dart';
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
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    return Column(
      children: <Widget>[
        _TabStrip(state: state, activeTab: activeTab, colors: colors),
        Expanded(
          child: _PdfViewerPane(
            tab: activeTab,
            documentRef: ref.watch(pdfDocumentRefProvider(activeTab.filePath)),
            annotations:
                state.documentMetadata[activeTab.documentId]?.annotations ??
                const <DocumentAnnotation>[],
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends ConsumerStatefulWidget {
  const _TabStrip({
    required this.state,
    required this.activeTab,
    required this.colors,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;
  final WorkspaceSurfaceTokens colors;

  @override
  ConsumerState<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<_TabStrip> {
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
          decoration: BoxDecoration(
            color: widget.colors.canvasRaised,
            border: Border(bottom: BorderSide(color: widget.colors.border)),
          ),
          child: Row(
            children: <Widget>[
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
                              ? widget.colors.panelRaised
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: selected
                                ? widget.colors.accentBorder
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
                                  ? widget.colors.warning
                                  : widget.colors.textMuted,
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
                                style: TextStyle(
                                  color: widget.colors.textStrong,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _confirmCloseTab(tab),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 12,
                                  color: widget.colors.textFaint,
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
              _IndexStatusIndicator(status: widget.activeTab.indexStatus),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmCloseTab(DocumentTabState tab) async {
    final notifier = ref.read(workspaceNotifierProvider.notifier);
    if (!notifier.hasUnsavedEditsFor(tab.id)) {
      await notifier.closeTab(tab.id);
      return;
    }
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: WorkspaceColors.panel,
        title: const Text(
          'Save PDF edits?',
          style: TextStyle(color: WorkspaceColors.textStrong),
        ),
        content: Text(
          '“${tab.title}” has unsaved bookmarks or highlights.',
          style: const TextStyle(color: WorkspaceColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await notifier.setActiveTab(tab.id);
      await notifier.saveActivePdfEdits();
      if (notifier.hasUnsavedEditsFor(tab.id)) return;
    }
    if (choice == 'save' || choice == 'discard') {
      await notifier.closeTab(tab.id);
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

class _IndexStatusIndicator extends StatefulWidget {
  const _IndexStatusIndicator({required this.status});
  final DocumentIndexStatus status;
  @override
  State<_IndexStatusIndicator> createState() => _IndexStatusIndicatorState();
}

class _IndexStatusIndicatorState extends State<_IndexStatusIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active =
        widget.status == DocumentIndexStatus.queued ||
        widget.status == DocumentIndexStatus.indexing;
    final Color color = widget.status == DocumentIndexStatus.indexed
        ? const Color(0xFF5BA56A)
        : active
        ? const Color(0xFFC5C5C5)
        : WorkspaceColors.textFaint;
    final String message = switch (widget.status) {
      DocumentIndexStatus.indexed =>
        'Indexed — ready for document-aware AI answers.',
      DocumentIndexStatus.indexing =>
        'Indexing this PDF for document-aware AI answers.',
      DocumentIndexStatus.queued => 'PDF indexing is queued.',
      DocumentIndexStatus.failed =>
        'Indexing failed. AI may use limited document context.',
      DocumentIndexStatus.unavailable =>
        'Indexing is unavailable for this document.',
      DocumentIndexStatus.idle => 'PDF has not been indexed yet.',
    };
    return Tooltip(
      message: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: active
            ? FadeTransition(
                opacity: Tween<double>(
                  begin: .35,
                  end: 1,
                ).animate(_controller!),
                child: _dot(color),
              )
            : _dot(color),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
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
    required this.colors,
  });

  final DocumentTabState tab;
  final PdfDocumentRef documentRef;
  final List<DocumentAnnotation> annotations;
  final WorkspaceSurfaceTokens colors;

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
  String? _pendingSearchQuery;
  Timer? _viewerStateDebounce;
  Offset? _lastPointerGlobalPosition;
  bool _colorInspectorOpen = false;
  int _customHighlightColor = 0x66FFD54F;
  final Map<String, List<Rect>> _annotationHitAreas = <String, List<Rect>>{};
  Offset? _selectionDragStart;
  Offset? _selectionMenuPosition;
  Offset? _selectionAutoPanPointer;
  Timer? _selectionAutoPanTimer;

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
      final editing = ref.read(pdfEditingControllerProvider);
      if (editing.sessionsByTabId[oldWidget.tab.id]?.mode !=
          PdfEditingMode.reading) {
        unawaited(editing.leaveTextMode(oldWidget.tab.id));
      }
      _disposeSearcher();
      _controller.removeListener(_syncViewerMetrics);
      _metrics.dispose();
      _viewerStateDebounce?.cancel();
      _lastPointerGlobalPosition = null;
      _pendingSearchQuery = null;
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
      _pendingSearchQuery = widget.tab.searchQuery.trim().isEmpty
          ? null
          : widget.tab.searchQuery;
      _searcher!.startTextSearch(
        widget.tab.searchQuery,
        searchImmediately: widget.tab.searchQuery.trim().isNotEmpty,
      );
    }
  }

  @override
  void dispose() {
    _viewerStateDebounce?.cancel();
    _selectionAutoPanTimer?.cancel();
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
    final PdfEditingController editing = ref.watch(
      pdfEditingControllerProvider,
    );
    final PdfEditingSession? editSession =
        editing.sessionsByTabId[widget.tab.id];
    final String? readerBackgroundPath = ref
        .watch(clarixThemeProvider)
        .value
        ?.readerBackgroundPath;
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
      decoration: BoxDecoration(color: widget.colors.canvas),
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: TextSelectionThemeData(
            selectionColor: widget.colors.selection,
          ),
        ),
        child: Stack(
          children: <Widget>[
            if (readerBackgroundPath case final String path)
              Positioned.fill(
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            Positioned.fill(
              child: Listener(
                onPointerHover: _rememberPointerPosition,
                onPointerDown: (PointerDownEvent event) {
                  _rememberPointerPosition(event);
                  _selectionDragStart = event.localPosition;
                },
                onPointerMove: (PointerMoveEvent event) {
                  _rememberPointerPosition(event);
                  _updateSelectionAutoPan(event);
                },
                onPointerUp: (PointerUpEvent event) {
                  _rememberPointerPosition(event);
                  _stopSelectionAutoPan();
                  unawaited(_showSelectionMenuAfterDrag(event));
                },
                onPointerCancel: _rememberPointerPosition,
                onPointerPanZoomStart: _rememberTrackpadZoomStart,
                onPointerPanZoomUpdate: _rememberTrackpadZoomPosition,
                child: ReaderCursorLockedPdfRegion(
                  controller: _controller,
                  onViewChanged: _queueViewerStatePersistence,
                  builder:
                      (BuildContext context, ReaderCursorLockedPdfInput input) {
                        return PdfViewer(
                          widget.documentRef,
                          controller: _controller,
                          initialPageNumber: widget.tab.currentPage,
                          params: PdfViewerParams(
                            backgroundColor: readerBackgroundPath == null
                                ? widget.colors.viewerBackground
                                : Colors.transparent,
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
                            textSelectionParams: textSelectionParamsFor(
                              editSession?.interaction ??
                                  PdfEditingInteraction.reading,
                            ),
                            buildContextMenu: _buildSelectionContextMenu,
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
                            onGeneralTap: _onViewerTap,
                            viewerOverlayBuilder: _buildViewerOverlay,
                            pageOverlaysBuilder: (context, pageRect, page) =>
                                <Widget>[
                                  if (editSession?.mode !=
                                          PdfEditingMode.reading &&
                                      editSession != null)
                                    PdfObjectTransformOverlay(
                                      objects: editSession.pageObjects
                                          .where(
                                            (object) =>
                                                object.locator.pageNumber ==
                                                    page.pageNumber &&
                                                object.locator.type !=
                                                    PdfPageObjectType.text,
                                          )
                                          .toList(growable: false),
                                      rectForObject: (object) =>
                                          PdfRect(
                                            object.bounds.left,
                                            object.bounds.top,
                                            object.bounds.right,
                                            object.bounds.bottom,
                                          ).toRect(
                                            page: page,
                                            scaledPageSize: pageRect.size,
                                          ),
                                      documentId: editSession.documentId,
                                      documentRevision: editSession.revision,
                                      onIntent: (intent) => unawaited(
                                        editing.dispatch(
                                          intent,
                                          provenance:
                                              PdfCommandProvenance.manual,
                                        ),
                                      ),
                                      onPreview: (locator, transform) =>
                                          editing.previewTransform(
                                            widget.tab.id,
                                            _controller.document,
                                            locator,
                                            transform,
                                          ),
                                    ),
                                  PdfTextEditorOverlay(
                                    mode:
                                        editSession?.mode ??
                                        PdfEditingMode.reading,
                                    blocks:
                                        editSession?.blocks
                                            .where(
                                              (block) =>
                                                  block.locator.pageNumber ==
                                                  page.pageNumber,
                                            )
                                            .toList(growable: false) ??
                                        const <PdfTextBlock>[],
                                    selection: editSession?.selection,
                                    nativeProjection: editing.nativeResultFor(
                                      widget.tab.id,
                                    ),
                                    onSelectionChanged: (range) => editing
                                        .setTextSelection(widget.tab.id, range),
                                    pageObjects:
                                        editSession?.pageObjects
                                            .where(
                                              (object) =>
                                                  object.locator.pageNumber ==
                                                  page.pageNumber,
                                            )
                                            .toList(growable: false) ??
                                        const <PdfPageObject>[],
                                    onObjectPreview: (locator, transform) =>
                                        editing.previewTransform(
                                          widget.tab.id,
                                          _controller.document,
                                          locator,
                                          transform,
                                        ),
                                    rectForBlock: (block) =>
                                        PdfRect(
                                          block.bounds.left,
                                          block.bounds.top,
                                          block.bounds.right,
                                          block.bounds.bottom,
                                        ).toRect(
                                          page: page,
                                          scaledPageSize: pageRect.size,
                                        ),
                                    onSelect: (locator) {
                                      unawaited(() async {
                                        await editing.selectTextBlock(
                                          widget.tab.id,
                                          _controller.document,
                                          locator,
                                        );
                                        await ref
                                            .read(
                                              workspaceNotifierProvider
                                                  .notifier,
                                            )
                                            .selectRightToolWindow(
                                              RightToolWindow.textFormat,
                                            );
                                      }());
                                    },
                                    documentId: editSession?.documentId,
                                    documentRevision: editSession?.revision,
                                    caseMatching:
                                        editSession?.caseMatching ?? true,
                                    onIntent: (intent) => unawaited(
                                      editing.dispatch(
                                        intent,
                                        provenance: PdfCommandProvenance.manual,
                                      ),
                                    ),
                                    onClearSelection: () => unawaited(
                                      editing.clearSelection(
                                        widget.tab.id,
                                        document: _controller.document,
                                      ),
                                    ),
                                    onUndo: () => unawaited(
                                      editing.undo(
                                        widget.tab.id,
                                        document: _controller.document,
                                      ),
                                    ),
                                    onRedo: () => unawaited(
                                      editing.redo(
                                        widget.tab.id,
                                        document: _controller.document,
                                      ),
                                    ),
                                  ),
                                ],
                          ),
                        );
                      },
                ),
              ),
            ),
            if (_shouldShowSearchOverlay)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: _DocumentSearchOverlay(
                    query: widget.tab.searchQuery,
                    isSearching: _isSearchInProgress,
                    matchCount: _searcher?.matches.length ?? 0,
                    currentIndex: _searcher?.currentIndex,
                    onPrevious: _canGoToPreviousMatch
                        ? () => unawaited(_goToPreviousSearchMatch())
                        : null,
                    onNext: _canGoToNextMatch
                        ? () => unawaited(_goToNextSearchMatch())
                        : null,
                  ),
                ),
              ),
            if (_selectionMenuPosition case final Offset position)
              Positioned(
                left: position.dx,
                top: position.dy,
                child: _QuickSelectionMenu(
                  colors: widget.colors,
                  onCopy: _copyCurrentSelection,
                  onBookmark: _addNamedBookmark,
                  onHighlight: (int color) =>
                      _highlightSelection(colorValue: color),
                  onDismiss: () =>
                      setState(() => _selectionMenuPosition = null),
                ),
              ),
            if (_colorInspectorOpen)
              Positioned(
                top: 18,
                right: 18,
                child: Material(
                  color: widget.colors.panelRaised,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 230,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('Custom highlight colour'),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _colorInspectorOpen = false),
                                icon: const Icon(LucideIcons.x, size: 15),
                              ),
                            ],
                          ),
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: Color(_customHighlightColor),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ColourWheel(
                            color: Color(_customHighlightColor),
                            onChanged: (Color color) => setState(
                              () => _customHighlightColor = color.toARGB32(),
                            ),
                          ),
                          FilledButton(
                            onPressed: () async {
                              await _highlightSelection(
                                colorValue: _customHighlightColor,
                              );
                              if (mounted) {
                                setState(() => _colorInspectorOpen = false);
                              }
                            },
                            child: const Text('Apply to selection'),
                          ),
                        ],
                      ),
                    ),
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
                            textEditing:
                                editSession != null &&
                                editSession.mode != PdfEditingMode.reading,
                            onToggleTextEditing: _controller.isReady
                                ? _toggleTextEditing
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
    final editing = ref.read(pdfEditingControllerProvider);
    if (!editing.sessionsByTabId.containsKey(widget.tab.id)) {
      editing.registerSession(
        widget.tab.id,
        PdfEditingSession.empty(
          widget.tab.documentId,
          sourceRevision: widget.tab.documentId,
        ),
      );
    }
    final PdfTextSearcher searcher = PdfTextSearcher(controller);
    if (widget.tab.searchQuery.trim().isNotEmpty) {
      _pendingSearchQuery = widget.tab.searchQuery;
      searcher.startTextSearch(widget.tab.searchQuery, searchImmediately: true);
    }
    _searchListener = () {
      if (mounted) {
        setState(() {
          if (!searcher.isSearching) {
            _pendingSearchQuery = null;
          }
        });
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

  Future<void> _toggleTextEditing() async {
    final editing = ref.read(pdfEditingControllerProvider);
    final session = editing.sessionFor(widget.tab.id);
    if (session.mode != PdfEditingMode.reading) {
      await editing.leaveTextMode(
        widget.tab.id,
        document: _controller.document,
      );
    } else {
      await editing.enterTextMode(widget.tab.id, _controller.document, _page);
    }
    if (mounted) _controller.invalidate();
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
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _goToNextSearchMatch() async {
    await _searcher?.goToNextMatch();
    if (mounted) {
      setState(() {});
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
          (_annotationHitAreas[annotation.id] ?? const <Rect>[]).any(
            (area) => area.inflate(3).contains(details.documentPosition),
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
    setState(
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
                setState(() => _colorInspectorOpen = true);
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
    if (mounted) setState(() => _selectionMenuPosition = null);
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
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onSelectZoomPreset,
    required this.onHighlightSelection,
    required this.textEditing,
    required this.onToggleTextEditing,
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
  final bool textEditing;
  final VoidCallback? onToggleTextEditing;

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
            const SizedBox(width: 6),
            Tooltip(
              message: textEditing
                  ? 'Leave PDF object editing'
                  : 'Edit PDF objects',
              child: _HudIcon(
                key: const Key('pdf-text-edit-toggle'),
                icon: LucideIcons.textCursorInput,
                onPressed: onToggleTextEditing,
                active: textEditing,
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
) => PdfTextSelectionParams(
  enabled: interaction == PdfEditingInteraction.reading,
  showContextMenuAutomatically: interaction == PdfEditingInteraction.reading,
);
