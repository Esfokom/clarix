import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/ffi/api.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/core/theme_controller.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/workspace_common.dart';
import 'reader_interaction_math.dart';
import 'reading_velocity_pill.dart';
import 'package:clarix/src/core/deep_link_service.dart';
import '../domain/pdf_night_mode.dart';
import 'package:clarix/src/features/scrapbook/presentation/scrapbook_side_pane.dart';
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
  Offset? _selectionMenuPosition;
  Timer? _selectionAutoPanTimer;
  bool _nativeLifecycleSyncScheduled = false;
  bool _isCanvasEditingActive = false;
  PdfNightMode _nightMode = PdfNightMode.off;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNativeSession();
      _loadFullPdfTextViaNativeSession();
    });
  }

  Future<void> _initNativeSession() async {
    if (_pageSceneLifecycle == null && mounted) {
      await _openNativeEditor(widget.tab.id, widget.tab.filePath);
    }
  }

  Future<void> _refreshCanvasOverlay() async {
    if (_controller.isReady) {
      _controller.invalidate();
    }
    var session = ref.read(editorSessionRegistryProvider)[widget.tab.id];
    session ??= await _openNativeEditor(widget.tab.id, widget.tab.filePath);
    if (session != null) {
      await session.refreshPage(widget.tab.currentPage);
    }
    _updateState();
  }

  String? _cachedFullMarkdownText;

  Future<void> _loadFullPdfTextViaNativeSession() async {
    try {
      final nativeSession = await NativePdfSession.open(path: widget.tab.filePath);
      final pageCount = widget.tab.pageCountHint ?? 26;
      final buffer = StringBuffer();

      PdfDocument? pdfrxDoc;
      try {
        await pdfrxInitialize();
        pdfrxDoc = await PdfDocument.openFile(widget.tab.filePath);
      } catch (_) {}

      for (var i = 1; i <= pageCount; i++) {
        try {
          final text = await nativeSession.pageText(pageNumber: BigInt.from(i));
          final cleanText = text.trim();
          if (cleanText.isNotEmpty || pdfrxDoc != null) {
            buffer.writeln('## Page $i\n');
            final formattedText = _formatExtractedTables(cleanText);
            buffer.writeln(formattedText);
            buffer.writeln();

            // If textual content is sparse or empty (scanned diagram page), render page diagram image
            if (cleanText.isEmpty && pdfrxDoc != null && i <= pdfrxDoc.pages.length) {
              try {
                final page = await pdfrxDoc.pages[i - 1].ensureLoaded();
                final pixelWidth = (page.width * 1.5).round();
                final pixelHeight = (page.height * 1.5).round();
                final rendered = await page.render(
                  width: pixelWidth,
                  height: pixelHeight,
                  fullWidth: pixelWidth.toDouble(),
                  fullHeight: pixelHeight.toDouble(),
                  backgroundColor: 0xffffffff,
                );
                if (rendered != null) {
                  try {
                    final raster = rendered.createImageNF();
                    final pngBytes = img.encodePng(raster);
                    final tempDir = Directory.systemTemp;
                    final tempFile = File('${tempDir.path}${Platform.pathSeparator}clarix_page_${i}_${DateTime.now().millisecondsSinceEpoch}.png');
                    await tempFile.writeAsBytes(pngBytes);
                    final fileUri = Uri.file(tempFile.path).toString();
                    buffer.writeln('![Page $i Diagram]($fileUri)\n');
                  } finally {
                    rendered.dispose();
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      if (pdfrxDoc != null) {
        await pdfrxDoc.dispose();
      }

      final result = buffer.toString().trim();
      if (result.isNotEmpty && mounted) {
        setState(() {
          _cachedFullMarkdownText = result;
        });
      }
    } catch (_) {}
  }

  String _formatExtractedTables(String text) {
    final lines = text.split('\n');
    final result = <String>[];
    List<List<String>> currentTable = [];

    void flushCurrentTable() {
      if (currentTable.isNotEmpty) {
        if (currentTable.length >= 2) {
          final headers = currentTable.first;
          result.add('| ${headers.join(' | ')} |');
          result.add('| ${headers.map((_) => '---').join(' | ')} |');
          for (final row in currentTable.skip(1)) {
            result.add('| ${row.join(' | ')} |');
          }
        } else {
          for (final row in currentTable) {
            result.add(row.join(' '));
          }
        }
        currentTable.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushCurrentTable();
        result.add('');
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s{2,}|\t'));
      if (parts.length >= 2) {
        currentTable.add(parts.map((p) => p.trim()).toList());
      } else {
        flushCurrentTable();
        result.add(trimmed);
      }
    }
    flushCurrentTable();
    return result.join('\n');
  }

  String _extractCurrentMarkdownText() {
    if (_cachedFullMarkdownText != null && _cachedFullMarkdownText!.isNotEmpty) {
      return _cachedFullMarkdownText!;
    }
    _loadFullPdfTextViaNativeSession();
    return '# Extracting Document Text...\n\nPlease wait a moment while the full PDF text is being extracted.';
  }

  bool get _isEditedDocument {
    final name = widget.tab.filePath.split(Platform.pathSeparator).last.toLowerCase();
    return name.startsWith('edited_') || name.contains('_edited');
  }

  Future<void> _overwriteCurrentMarkdownPdf(String markdown) async {
    try {
      await MarkdownPdfCompiler.saveToFile(markdown, widget.tab.filePath);
      _cachedFullMarkdownText = markdown;
      if (mounted) {
        setState(() => _isCanvasEditingActive = false);
        if (_controller.isReady) {
          _controller.invalidate();
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document updated cleanly.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not overwrite PDF: $e')),
        );
      }
    }
  }

  Future<void> _saveAsNewMarkdownPdf(String markdown) async {
    try {
      final defaultName = 'edited_${widget.tab.title}';
      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Save As New PDF',
        fileName: defaultName.endsWith('.pdf') ? defaultName : '$defaultName.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (savePath != null && savePath.isNotEmpty) {
        final targetPath = savePath.endsWith('.pdf') ? savePath : '$savePath.pdf';
        await MarkdownPdfCompiler.saveToFile(markdown, targetPath);

        if (mounted) {
          setState(() => _isCanvasEditingActive = false);
        }

        await ref
            .read(workspaceNotifierProvider.notifier)
            .openPdfFiles([targetPath]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save new PDF: $e')),
        );
      }
    }
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
      _cachedFullMarkdownText = null;
      _isCanvasEditingActive = false;
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initNativeSession();
        _loadFullPdfTextViaNativeSession();
      });
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
        _isCanvasEditingActive ||
        workspaceSession?.rightToolWindow == RightToolWindow.textFormat ||
        workspaceSession?.rightToolWindow == RightToolWindow.document ||
        (editorState?.isOpen == true &&
            (editorState?.selection != null ||
                (editorState?.revision ?? 0) > 0));
    final interaction = isEditingMode
        ? PdfEditingInteraction.textEditing
        : PdfEditingInteraction.reading;

    return DecoratedBox(
      decoration: BoxDecoration(color: widget.colors.canvas),
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: const TextSelectionThemeData(
            selectionColor: Color(0x662563EB),
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
            if (_isCanvasEditingActive || ref.watch(activeMarkdownEditorTabIdProvider) == widget.tab.id)
              Positioned.fill(
                child: MarkdownEditorPane(
                  initialMarkdown: _extractCurrentMarkdownText(),
                  onSave: (markdown) async {
                    if (_isEditedDocument) {
                      await _overwriteCurrentMarkdownPdf(markdown);
                    } else {
                      await _saveAsNewMarkdownPdf(markdown);
                    }
                  },
                  onSaveAs: _isEditedDocument
                      ? (markdown) async {
                          await _saveAsNewMarkdownPdf(markdown);
                        }
                      : null,
                  onClose: () {
                    setState(() => _isCanvasEditingActive = false);
                    ref.read(activeMarkdownEditorTabIdProvider.notifier).setTabId(null);
                  },
                ),
              )
            else
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: _nightMode.colorFilter ?? const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: ReaderCursorLockedPdfRegion(
                  controller: _controller,
                  onViewChanged: _queueViewerStatePersistence,
                  builder:
                      (BuildContext context, ReaderCursorLockedPdfInput input) {                        return PdfViewer(
                          widget.documentRef,
                          controller: _controller,
                          initialPageNumber: widget.tab.currentPage,
                          params: PdfViewerParams(
                            sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(minScale: 0.1, maxScale: 6.0),
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
                  onScrapbook: () async {
                    final contextText =
                        await _controller.textSelectionDelegate.getSelectedText();
                    if (contextText.trim().isNotEmpty) {
                      ref.read(scrapbookServiceProvider).addItem(
                            documentTitle: widget.tab.title,
                            filePath: widget.tab.filePath,
                            pageNumber: _page,
                            text: contextText,
                          );
                      await ref
                          .read(workspaceNotifierProvider.notifier)
                          .selectRightToolWindow(RightToolWindow.scrapbook);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Added clipping to Scrapbook!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
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
            if (!_isCanvasEditingActive)
              Positioned(
                top: 14,
                right: 18,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _EditDocumentModeButton(
                      isEditingMode: _isCanvasEditingActive,
                      onToggle: () async {
                        if (!_isCanvasEditingActive) {
                          try {
                            await ref.read(editorSessionRegistryProvider).open(
                                  tabId: widget.tab.id,
                                  sourcePath: widget.tab.filePath,
                                );
                          } catch (error) {
                            ref.read(workspaceNotifierProvider.notifier).reportPdfEditFailure(error);
                          }
                        }
                        if (mounted) {
                          setState(() => _isCanvasEditingActive = !_isCanvasEditingActive);
                        }
                      },
                    ),
                  ],
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
                            documentId: widget.tab.documentId,
                            filePath: widget.tab.filePath,
                            nightMode: _nightMode,
                            onNightModeChanged: (mode) => setState(() => _nightMode = mode),
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
                            onGoToPage: _controller.isReady
                                ? (page) => _controller.goToPage(pageNumber: page)
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
                            scanning: editorState?.scanning ?? false,
                            onToggleTextEditing: _controller.isReady
                                ? _toggleTextEditing
                                : null,
                            onRefreshCanvas: _refreshCanvasOverlay,
                            onUndo: null,
                            onRedo: null,
                            onSave: () => ref.read(workspaceNotifierProvider.notifier).saveActivePdfEdits(),
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

class _EditDocumentModeButton extends StatelessWidget {
  const _EditDocumentModeButton({
    required this.isEditingMode,
    required this.onToggle,
  });

  final bool isEditingMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isEditingMode
                ? const Color(0xFF16A34A)
                : const Color(0xCC0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isEditingMode
                  ? const Color(0xFF22C55E)
                  : const Color(0x33FFFFFF),
              width: 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isEditingMode ? LucideIcons.check : LucideIcons.pencil,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                isEditingMode ? 'Done Editing' : 'Edit Document',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
