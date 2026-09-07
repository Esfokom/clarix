import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/core/theme_controller.dart';
import 'package:clarix/src/features/tts/tts.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/workspace_common.dart';
import 'reader_interaction_math.dart';
part 'reader_viewer_components.dart';
part 'reader_viewer_interactions.dart';
part 'reader_read_aloud.dart';

class ReaderViewerPane extends ConsumerStatefulWidget {
  const ReaderViewerPane({
    super.key,
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
  ConsumerState<ReaderViewerPane> createState() => _PdfViewerPaneState();
}

class _ReaderViewportMetrics {
  const _ReaderViewportMetrics({required this.page, required this.zoom});

  final int page;
  final double zoom;
}

class _PdfViewerPaneState extends ConsumerState<ReaderViewerPane> {
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
  final Map<int, List<_PageSentence>> _pageSentenceCache = <int, List<_PageSentence>>{};
  final Map<String, Rect> _readAloudHitAreas = <String, Rect>{};
  final List<ReadAloudSegment> _readAloudSessionSegments = <ReadAloudSegment>[];
  int? _readAloudNextPageToExtract;
  bool _readAloudExtending = false;
  bool _readAloudSessionOwned = false;

  int get _page => _metrics.value.page;
  double get _zoom => _metrics.value.zoom;

  void _updateState([VoidCallback? fn]) {
    if (mounted) {
      setState(fn ?? () {});
    }
  }

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
  void didUpdateWidget(covariant ReaderViewerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _disposeSearcher();
      _controller.removeListener(_syncViewerMetrics);
      _metrics.dispose();
      _viewerStateDebounce?.cancel();
      _lastPointerGlobalPosition = null;
      _pendingSearchQuery = null;
      _resetReadAloudSession();
      _pageSentenceCache.clear();
      _readAloudHitAreas.clear();
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
    _disposeSearcher();
    _controller.removeListener(_syncViewerMetrics);
    _metrics.dispose();
    if (_readAloudSessionOwned) {
      unawaited(ref.read(ttsNotifierProvider.notifier).stop());
    }
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
    final String? readerBackgroundPath = ref
        .watch(clarixThemeProvider)
        .value
        ?.readerBackgroundPath;
    final TtsPlaybackState readAloudPlayback =
        ref.watch(ttsNotifierProvider).value?.playback ?? const TtsPlaybackState();
    ref.listen<TtsPlaybackState>(
      ttsNotifierProvider.select(
        (AsyncValue<TtsFeatureState> value) =>
            value.value?.playback ?? const TtsPlaybackState(),
      ),
      _onReadAloudPlaybackChanged,
    );
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
                onPointerDown: _rememberPointerPosition,
                onPointerMove: _rememberPointerPosition,
                onPointerUp: _rememberPointerPosition,
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
                            // Render and keep a screenful of pages beyond the
                            // viewport in every direction so a fast scroll
                            // lands on painted pages instead of placeholders.
                            limitRenderingCache: false,
                            maxImageBytesCachedOnMemory: 192 * 1024 * 1024,
                            horizontalCacheExtent: 1,
                            verticalCacheExtent: 2,
                            panEnabled: true,
                            scaleEnabled: input.pdfrxScaleEnabled,
                            scaleByPointerScale: readerPointerZoomSensitivity,
                            interactionDelegateProvider:
                                input.interactionDelegateProvider,
                            onInteractionEnd: (_) => _persistViewerState(),
                            onPageChanged: _onPageChanged,
                            onViewerReady: _onViewerReady,
                            pagePaintCallbacks: <PdfViewerPagePaintCallback>[
                              _paintAnnotations,
                              _paintReadAloudHighlight,
                              if (_searcher != null)
                                _searcher!.pageTextMatchPaintCallback,
                            ],
                            onGeneralTap: _onViewerTap,
                            customizeContextMenuItems: _customizeContextMenu,
                            viewerOverlayBuilder: _buildViewerOverlay,
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
            if (readAloudPlayback.status != TtsPlaybackStatus.idle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 60,
                child: Center(
                  child: _ReadAloudBar(
                    playback: readAloudPlayback,
                    colors: widget.colors,
                    onPauseResume: () =>
                        readAloudPlayback.status == TtsPlaybackStatus.speaking
                        ? ref.read(ttsNotifierProvider.notifier).pause()
                        : ref.read(ttsNotifierProvider.notifier).resume(),
                    onStop: () => ref.read(ttsNotifierProvider.notifier).stop(),
                  ),
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
}
