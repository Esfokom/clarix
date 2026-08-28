import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/core/theme_controller.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/workspace_common.dart';
import 'reader_interaction_math.dart';
part 'reader_viewer_components.dart';
part 'reader_viewer_interactions.dart';

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
  late PdfrxPageSurface _pageSurface;
  late ValueNotifier<_ReaderViewportMetrics> _metrics;
  PageSceneLifecycle? _pageSceneLifecycle;
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
  bool _nativeLifecycleSyncScheduled = false;

  int get _page => _metrics.value.page;
  double get _zoom => _metrics.value.zoom;

  void _updateState([VoidCallback? fn]) {
    if (mounted) {
      setState(fn ?? () {});
    }
  }

  AiProviderProfile? _selectedProvider() {
    final ai = ref.read(aiNotifierProvider).value;
    final selected = ai?.chat.selectedProviderId;
    if (selected == null) return null;
    return ai?.providerProfiles
        .where((profile) => profile.id == selected)
        .firstOrNull;
  }

  Future<void> _runSelectionAction(
    SelectionAiAction action,
    EditorSelection selection,
    EditorSceneObject object,
    int pageNumber,
  ) async {
    final profile = _selectedProvider();
    final controller = ref.read(agentRunControllerProvider(widget.tab.id));
    final text = object.text ?? '';
    if (profile == null || controller == null) return;
    if (!profile.shareRetrievedPassages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable document sharing for this provider to use selected text.',
            ),
          ),
        );
      }
      return;
    }
    if (selection.range.end <= selection.range.start ||
        selection.range.end > text.length) {
      return;
    }
    final selectedText = text.substring(
      selection.range.start,
      selection.range.end,
    );
    final selected = AgentSelection(
      revision: _pageSceneLifecycle?.controller.state.revision ?? 0,
      ranges: <AgentSelectionRange>[
        AgentSelectionRange(
          objectId: object.objectId,
          pageId: object.pageId,
          pageNumber: pageNumber,
          startUtf16: selection.range.start,
          endUtf16: selection.range.end,
          quotedText: selectedText,
        ),
      ],
      objectIds: const <String>[],
      primaryIndex: 0,
    );
    final nativeContext = await controller.selectionContext(selected);
    if (!mounted) return;
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AgentDisclosureDialog(
        disclosure: AgentDisclosure(
          providerLabel: profile.label,
          selectedText: nativeContext.ranges
              .map((range) => range.quotedText)
              .join('\n'),
          nearbyTextBefore: nativeContext.nearbyTextBefore,
          nearbyTextAfter: nativeContext.nearbyTextAfter,
          pageNumbers: nativeContext.pageNumbers,
          sha256: nativeContext.disclosureSha256,
        ),
        includesConversationHistory: true,
        onConfirm: () => confirmed = true,
      ),
    );
    if (!confirmed || !mounted) return;
    final apiKey = await ref
        .read(providerProfileStoreProvider)
        .readApiKey(profile.id);
    if (apiKey == null || apiKey.isEmpty) return;
    await controller.start(
      AgentStartRequest(
        providerEndpoint: profile.baseUrl,
        modelId: profile.modelId,
        headers: profile.headers,
        apiKey: apiKey,
        userPrompt: _selectionPrompt(action),
        selection: selected,
        disclosureSha256: nativeContext.disclosureSha256,
      ),
    );
  }

  String _selectionPrompt(SelectionAiAction action) => switch (action) {
    SelectionAiAction.rewrite => 'Rewrite the selected text for clarity.',
    SelectionAiAction.shorten => 'Shorten the selected text.',
    SelectionAiAction.expand => 'Expand the selected text with useful detail.',
    SelectionAiAction.translate => 'Translate the selected text.',
    SelectionAiAction.summarize => 'Summarize the selected text.',
    SelectionAiAction.ask => 'Help with the selected text.',
  };

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = PdfViewerController();
    _pageSurface = PdfrxPageSurface(_controller);
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
      _pageSceneLifecycle?.dispose();
      _pageSceneLifecycle = null;
      _pageSurface.dispose();
      // The registry is keyed by tab id and closeTab closes sessions on tab
      // close — keep the old tab's session (and undo history) alive across
      // tab switches.
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
    _pageSceneLifecycle?.dispose();
    _pageSurface.dispose();
    unawaited(ref.read(editorSessionRegistryProvider).close(widget.tab.id));
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
    ref.watch(editorDocumentStateProvider(widget.tab.id));
    final registeredNative = ref.read(
      editorSessionRegistryProvider,
    )[widget.tab.id];
    if (!identical(_pageSceneLifecycle?.controller, registeredNative) &&
        !_nativeLifecycleSyncScheduled) {
      _nativeLifecycleSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _nativeLifecycleSyncScheduled = false;
        if (!mounted) return;
        final current = ref.read(editorSessionRegistryProvider)[widget.tab.id];
        if (identical(_pageSceneLifecycle?.controller, current)) return;
        _pageSceneLifecycle?.dispose();
        _pageSceneLifecycle = current == null
            ? null
            : (PageSceneLifecycle(surface: _pageSurface, controller: current)
                ..start());
        setState(() {});
      });
    }
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

    final workspaceSession = ref
        .watch(workspaceNotifierProvider)
        .value
        ?.session;
    final editorState = ref
        .watch(editorDocumentStateProvider(widget.tab.id))
        .value;
    // pdfrx invokes page overlay builders outside this widget's synchronous
    // build. Capture provider values here; calling ref.watch from that deferred
    // callback can target a disposed ConsumerState after a tab is closed.
    final agent = ref.watch(agentRunControllerProvider(widget.tab.id));
    // A persisted inspector selection is not an editor session. Only expose
    // edit interaction after the native session has actually opened.
    final isEditingMode =
        editorState?.isOpen == true &&
        (workspaceSession?.rightToolWindow == RightToolWindow.textFormat ||
            editorState?.selection != null);
    final interaction = isEditingMode
        ? PdfEditingInteraction.textEditing
        : PdfEditingInteraction.reading;

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
                              interaction,
                            ),
                            onKey: viewerKeyHandlerFor(interaction),
                            buildContextMenu: _buildSelectionContextMenu,
                            interactionDelegateProvider:
                                input.interactionDelegateProvider,
                            // pdfrx can finish a gesture after this pane has
                            // been removed.  Persist through the debounced
                            // path so dispose can cancel the pending work
                            // before it notifies the workspace provider.
                            onInteractionEnd: (_) =>
                                _queueViewerStatePersistence(),
                            onPageChanged: _onPageChanged,
                            onViewerReady: _onViewerReady,
                            pagePaintCallbacks: <PdfViewerPagePaintCallback>[
                              _paintAnnotations,
                              if (_searcher != null)
                                _searcher!.pageTextMatchPaintCallback,
                            ],
                            onGeneralTap: _onViewerTap,
                            viewerOverlayBuilder: _buildViewerOverlay,
                            pageOverlaysBuilder: (context, pageRect, page) {
                              // pdfrx invokes this builder lazily, outside
                              // this widget's build — it can run after the
                              // pane has been disposed or its lifecycle torn
                              // down for a tab switch.
                              if (!mounted) return <Widget>[];
                              return <Widget>[
                                  if (_pageSceneLifecycle
                                      case final PageSceneLifecycle lifecycle
                                          when !lifecycle.isDisposed)
                                    Positioned.fill(
                                      child: PageSceneHost(
                                        lifecycle: lifecycle,
                                        pageNumber: page.pageNumber,
                                        builder: (context, scene) {
                                          Widget sceneWidget(
                                            AgentRunControllerState? agentState,
                                          ) => PageEditScene(
                                            scene: scene,
                                            document:
                                                lifecycle.controller.state,
                                            session: lifecycle.controller,
                                            editingEnabled: isEditingMode,
                                            displaySize: pageRect.size,
                                            cleanPatches: lifecycle
                                                .cleanPatchesFor(
                                                  page.pageNumber,
                                                ),
                                            liveTiles: lifecycle.liveTilesFor(
                                              page.pageNumber,
                                            ),
                                            selectionActionsBuilder:
                                                (
                                                  context,
                                                  selection,
                                                  object,
                                                  pageNumber,
                                                ) => SelectionAiToolbar(
                                                  hasValidatedSelection: true,
                                                  sharingEnabled:
                                                      _selectedProvider()
                                                          ?.shareRetrievedPassages ??
                                                      false,
                                                  onAction: (action) =>
                                                      _runSelectionAction(
                                                        action,
                                                        selection,
                                                        object,
                                                        pageNumber,
                                                      ),
                                                ),
                                            pageOverlayBuilder:
                                                (context, pageNumber) {
                                                  final proposal = agentState
                                                      ?.pendingProposal;
                                                  if (proposal == null ||
                                                      !proposal.targets.any(
                                                        (target) =>
                                                            target.pageNumber ==
                                                            pageNumber,
                                                      )) {
                                                    return null;
                                                  }
                                                  return AgentDiffOverlay(
                                                    proposal: proposal,
                                                  );
                                                },
                                          );
                                          if (agent == null) {
                                            return sceneWidget(null);
                                          }
                                          return StreamBuilder<
                                            AgentRunControllerState
                                          >(
                                            stream: agent.changes,
                                            initialData: agent.state,
                                            builder: (context, snapshot) =>
                                                sceneWidget(snapshot.data),
                                          );
                                        },
                                      ),
                                    ),
                              ];
                            },
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
                            textEditing: isEditingMode,
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
}
