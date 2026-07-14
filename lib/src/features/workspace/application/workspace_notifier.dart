import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clarix_logger.dart';
import '../../../core/local_gemma_model_store.dart';
import '../../../core/model_catalog.dart';
import '../../../core/models.dart';
import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/session_store.dart';
import '../domain/workspace_feature_state.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/document_metadata_store.dart';
import 'ai_runtime_service.dart';
import 'workspace_providers.dart';

class WorkspaceNotifier extends AsyncNotifier<WorkspaceFeatureState> {
  final Map<String, CancelToken> _downloadTokens = <String, CancelToken>{};
  final Map<String, int> _downloadLogBuckets = <String, int>{};

  ClarixSessionStore get _sessionStore => ref.read(sessionStoreProvider);
  ClarixModelCatalog get _catalogService => ref.read(modelCatalogServiceProvider);
  LocalGemmaModelStore get _localModelStore =>
      ref.read(localGemmaModelStoreProvider);
  HybridPdfExtractionService get _pdfExtraction =>
      ref.read(pdfExtractionServiceProvider);
  DocumentChunkStore get _chunkStore => ref.read(chunkStoreProvider);
  DocumentIdentityService get _identityService =>
      ref.read(documentIdentityServiceProvider);
  Future<DocumentMetadataStore> get _metadataStore =>
      ref.read(documentMetadataStoreProvider.future);
  AiRuntimeService get _ai => ref.read(aiRuntimeServiceProvider);

  @override
  Future<WorkspaceFeatureState> build() async {
    final WorkspaceSession storedSession =
        await _sessionStore.readWorkspaceSession();
    final AiWorkspaceState storedAi = await _sessionStore.readAiWorkspaceState();
    final Map<String, DownloadTaskState> downloads =
        await _sessionStore.readDownloads();
    final WorkspaceSession restoredSession =
        await _rehydrateWorkspace(storedSession);
    final Map<String, DocumentMetadata> documentMetadata =
        await _loadDocumentMetadata(restoredSession);
    final List<ModelCatalogItem> catalog =
        _catalogService.buildCatalog(downloads: downloads);
    final AiWorkspaceState restoredAi = await _restoreAiBestEffort(
      storedAi,
      catalog,
    );

    return WorkspaceFeatureState(
      session: restoredSession,
      aiState: restoredAi,
      downloads: downloads,
      catalog: _catalogService.buildCatalog(downloads: downloads),
      outlines: const <String, List<OutlineNodeState>>{},
      documentMetadata: documentMetadata,
      composerExpanded: false,
      showModelCatalog: false,
      bannerMessage: null,
    );
  }

  Future<void> pickAndOpenPdfs() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      allowMultiple: true,
      dialogTitle: 'Open PDF files',
    );
    if (result == null) {
      return;
    }
    await openPdfFiles(
      result.files
          .map((PlatformFile file) => file.path)
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Future<void> openPdfFiles(List<String> paths) async {
    final WorkspaceFeatureState current = _requireState();
    final List<DocumentTabState> tabs = List<DocumentTabState>.from(
      current.session.tabs,
    );
    final Map<String, DocumentMetadata> metadata =
        Map<String, DocumentMetadata>.from(current.documentMetadata);
    final List<String> recentFiles =
        List<String>.from(current.session.recentFiles);
    final List<DocumentTabState> tabsToIndex = <DocumentTabState>[];
    String? activeTabId = current.session.activeTabId;
    final DocumentMetadataStore store = await _metadataStore;

    for (final String path in paths) {
      DocumentIdentity identity;
      try {
        identity = await _identityService.identify(path);
      } on FileSystemException catch (error) {
        clarixLog.w('Could not open PDF: $path', error: error);
        continue;
      }

      DocumentTabState? existing;
      for (final DocumentTabState tab in tabs) {
        if (tab.documentId == identity.fingerprint ||
            tab.filePath == identity.path) {
          existing = tab;
          break;
        }
      }
      if (existing != null) {
        activeTabId = existing.id;
        continue;
      }

      DocumentMetadata documentMetadata =
          await store.read(identity.fingerprint) ??
              DocumentMetadata.empty(identity);
      if (documentMetadata.identity.path != identity.path) {
        documentMetadata = documentMetadata.copyWith(identity: identity);
      }
      await store.write(documentMetadata);
      metadata[identity.fingerprint] = documentMetadata;

      final DocumentTabState tab = DocumentTabState.create(
        id: '${DateTime.now().microsecondsSinceEpoch}_${tabs.length}',
        documentId: identity.fingerprint,
        filePath: identity.path,
        title: identity.title,
      );
      tabs.add(tab);
      tabsToIndex.add(tab);
      activeTabId = tab.id;

      recentFiles
        ..remove(identity.path)
        ..insert(0, identity.path);
    }

    final WorkspaceSession session = current.session.copyWith(
      tabs: tabs,
      activeTabId: activeTabId,
      recentFiles: recentFiles.take(12).toList(growable: false),
      lastOpenedAt: DateTime.now().toUtc(),
    );
    await _commit(
      current.copyWith(session: session, documentMetadata: metadata),
      persistAi: false,
    );
    for (final DocumentTabState tab in tabsToIndex) {
      unawaited(_indexDocument(tab));
    }
  }

  Future<void> reopenRecent(String path) => openPdfFiles(<String>[path]);

  Future<void> closeTab(String tabId) async {
    final WorkspaceFeatureState current = _requireState();
    final List<DocumentTabState> tabs = current.session.tabs
        .where((DocumentTabState tab) => tab.id != tabId)
        .toList(growable: false);
    final String? activeTabId;
    if (tabs.isEmpty) {
      activeTabId = null;
    } else if (current.session.activeTabId == tabId) {
      activeTabId = tabs.last.id;
    } else {
      activeTabId = current.session.activeTabId;
    }

    final WorkspaceSession session = current.session.copyWith(
      tabs: tabs,
      activeTabId: activeTabId,
      clearActiveTabId: tabs.isEmpty,
      lastOpenedAt: DateTime.now().toUtc(),
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> setActiveTab(String tabId) async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(activeTabId: tabId);
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> toggleRestorePreviousSession(bool enabled) async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      restorePreviousSession: enabled,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> discardSessionOnClose() async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      tabs: const <DocumentTabState>[],
      clearActiveTabId: true,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> setSidebarPane(SidebarPane pane) async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session =
        current.session.copyWith(sidebarPane: pane);
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> toggleComposerExpanded() async {
    final WorkspaceFeatureState current = _requireState();
    state = AsyncData(
      current.copyWith(composerExpanded: !current.composerExpanded),
    );
  }

  Future<void> setSearchQuery(String tabId, String query) async {
    final WorkspaceFeatureState current = _requireState();
    final List<DocumentTabState> tabs = current.session.tabs
        .map(
          (DocumentTabState tab) => tab.id == tabId
              ? tab.copyWith(searchQuery: query, selectedSearchResult: 0)
              : tab,
        )
        .toList(growable: false);
    final WorkspaceSession session = current.session.copyWith(tabs: tabs);
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> updateViewerState({
    required String tabId,
    int? currentPage,
    double? zoomScale,
    int? pageCountHint,
  }) async {
    final WorkspaceFeatureState current = _requireState();
    final List<DocumentTabState> tabs = current.session.tabs
        .map(
          (DocumentTabState tab) => tab.id == tabId
              ? tab.copyWith(
                  currentPage: currentPage,
                  zoomScale: zoomScale,
                  pageCountHint: pageCountHint,
                  clearMissingFileMessage: true,
                )
              : tab,
        )
        .toList(growable: false);
    final WorkspaceSession session = current.session.copyWith(tabs: tabs);
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> setOutline(
    String tabId,
    List<OutlineNodeState> outline,
  ) async {
    final WorkspaceFeatureState current = _requireState();
    final Map<String, List<OutlineNodeState>> outlines =
        Map<String, List<OutlineNodeState>>.from(current.outlines)
          ..[tabId] = outline;
    state = AsyncData(current.copyWith(outlines: outlines));
  }

  Future<void> toggleModelCatalog([bool? value]) async {
    final WorkspaceFeatureState current = _requireState();
    state = AsyncData(
      current.copyWith(showModelCatalog: value ?? !current.showModelCatalog),
    );
  }

  Future<void> installModel(ModelCatalogItem item) async {
    final WorkspaceFeatureState current = _requireState();
    final CancelToken token = CancelToken();
    _downloadTokens[item.id] = token;
    _downloadLogBuckets.remove(item.id);
    clarixLog.i('Model install started: ${item.id}');
    await _setDownload(
      item.id,
      (current.downloads[item.id] ?? DownloadTaskState.initial(item.id))
          .copyWith(
        status: DownloadTaskStatus.running,
        progress: 0,
        downloadedBytes: 0,
        totalBytes: item.sizeBytes,
        clearErrorMessage: true,
      ),
    );

    try {
      final ModelInstallResult installResult;
      if (item.type == ModelCatalogType.inference) {
        installResult = await _ai.installInferenceModel(
          item: item,
          cancelToken: token,
          onProgress: (int progress) {
            _logDownloadProgress(item.id, progress);
            unawaited(
              _setDownload(
                item.id,
                (state.value?.downloads[item.id] ??
                        DownloadTaskState.initial(item.id))
                    .copyWith(
                  status: DownloadTaskStatus.running,
                  progress: progress,
                  downloadedBytes: _estimateDownloadedBytes(
                    progress: progress,
                    totalBytes: item.sizeBytes,
                  ),
                  totalBytes: item.sizeBytes,
                ),
              ),
            );
          },
        );
      } else {
        installResult = await _ai.installEmbeddingModel(
          item: item,
          cancelToken: token,
          onModelProgress: (int progress) {
            _logDownloadProgress(item.id, progress);
            unawaited(
              _setDownload(
                item.id,
                (state.value?.downloads[item.id] ??
                        DownloadTaskState.initial(item.id))
                    .copyWith(
                  status: DownloadTaskStatus.running,
                  progress: progress,
                  downloadedBytes: _estimateDownloadedBytes(
                    progress: progress,
                    totalBytes: item.sizeBytes,
                  ),
                  totalBytes: item.sizeBytes,
                ),
              ),
            );
          },
          onTokenizerProgress: (int progress) {
            _logDownloadProgress(item.id, progress);
            unawaited(
              _setDownload(
                item.id,
                (state.value?.downloads[item.id] ??
                        DownloadTaskState.initial(item.id))
                    .copyWith(
                  status: DownloadTaskStatus.validating,
                  progress: progress,
                  downloadedBytes: _estimateDownloadedBytes(
                    progress: progress,
                    totalBytes: item.sizeBytes,
                  ),
                  totalBytes: item.sizeBytes,
                ),
              ),
            );
          },
        );
      }

      final WorkspaceFeatureState refreshed = _requireState();
      final AiWorkspaceState aiState = item.type == ModelCatalogType.inference
          ? refreshed.aiState.copyWith(
              inferenceReady: true,
              activityPhase: AiRuntimePhase.idle,
              statusMessage: 'Inference model ready.',
              activeInferenceModelId: item.id,
            )
          : refreshed.aiState.copyWith(
              embeddingReady: true,
              vectorStoreReady: true,
              activityPhase: AiRuntimePhase.idle,
              statusMessage: 'Embedding model ready. PDF grounding unlocked.',
              activeEmbeddingModelId: item.id,
            );

      await _setDownload(
        item.id,
        (state.value?.downloads[item.id] ?? DownloadTaskState.initial(item.id))
            .copyWith(
          status: DownloadTaskStatus.completed,
          progress: 100,
          downloadedBytes: installResult.sizeBytes,
          totalBytes: installResult.sizeBytes,
          installedPath: installResult.installedPath,
          clearErrorMessage: true,
        ),
      );
      clarixLog.i(
        'Model install completed: ${item.id} at ${installResult.installedPath}',
      );
      final WorkspaceFeatureState completedState = _requireState();
      await _commit(completedState.copyWith(aiState: aiState));

      if (item.type == ModelCatalogType.embedding) {
        for (final DocumentTabState tab in refreshed.session.tabs) {
          unawaited(_syncTabIndexToVectorStore(tab));
        }
      }
    } catch (error) {
      final DownloadTaskStatus status = CancelToken.isCancel(error)
          ? DownloadTaskStatus.paused
          : DownloadTaskStatus.failed;
      clarixLog.w(
        'Model install ${status.name}: ${item.id}',
        error: error,
      );
      await _setDownload(
        item.id,
        (state.value?.downloads[item.id] ?? DownloadTaskState.initial(item.id))
            .copyWith(
          status: status,
          errorMessage: error.toString(),
        ),
      );
    } finally {
      _downloadTokens.remove(item.id);
      _downloadLogBuckets.remove(item.id);
    }
  }

  void pauseDownload(String modelId) {
    final CancelToken? token = _downloadTokens[modelId];
    token?.cancel('Paused by user');
  }

  Future<void> cancelDownload(String modelId) async {
    final CancelToken? token = _downloadTokens[modelId];
    token?.cancel('Cancelled by user');
    _downloadTokens.remove(modelId);
    await _setDownload(
      modelId,
      DownloadTaskState.initial(modelId),
    );
  }

  Future<void> openModelLocation(ModelCatalogItem item) async {
    final WorkspaceFeatureState current = _requireState();
    final String? path = item.installedPath ??
        current.downloads[item.id]?.installedPath ??
        _localModelStore.installedPathSync(item);
    if (path == null) {
      clarixLog.w('No installed path available for ${item.id}');
      return;
    }
    await _localModelStore.reveal(path);
  }

  Future<void> toggleScopeMode() async {
    final WorkspaceFeatureState current = _requireState();
    final AiWorkspaceState aiState = current.aiState.copyWith(
      useCurrentDocumentScope: !current.aiState.useCurrentDocumentScope,
    );
    await _commit(current.copyWith(aiState: aiState));
  }

  Future<void> sendPrompt(String prompt) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState? activeTab = activeTabState;
    if (prompt.trim().isEmpty || current.aiState.chatBusy) {
      return;
    }

    final ComposerMessage userMessage = ComposerMessage(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      text: prompt.trim(),
      createdAt: DateTime.now().toUtc(),
      citations: const <CitationSnippet>[],
    );
    final ComposerMessage assistantMessage = ComposerMessage(
      id: 'assistant_${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      text: '',
      createdAt: DateTime.now().toUtc(),
      citations: const <CitationSnippet>[],
    );

    await _commit(
      current.copyWith(
        aiState: current.aiState.copyWith(
          chatBusy: true,
          activityPhase: AiRuntimePhase.loadingInference,
          statusMessage: 'Loading inference model. First response can take a minute.',
          messages: <ComposerMessage>[
            ...current.aiState.messages,
            userMessage,
            assistantMessage,
          ],
          lastRetrievalSnippets: const <CitationSnippet>[],
        ),
      ),
    );

    try {
      final StringBuffer answerBuffer = StringBuffer();
      final _AiReplyData reply = await _generateReply(
        prompt: prompt.trim(),
        useCurrentDocumentScope: current.aiState.useCurrentDocumentScope,
        currentDocumentId: activeTab?.documentId,
        onStatus: _setAiActivity,
        onToken: (String token) {
          answerBuffer.write(token);
          final WorkspaceFeatureState live = _requireState();
          final List<ComposerMessage> updatedMessages =
              List<ComposerMessage>.from(live.aiState.messages);
          updatedMessages[updatedMessages.length - 1] =
              updatedMessages.last.copyWith(text: answerBuffer.toString());
          state = AsyncData(
            live.copyWith(
              aiState: live.aiState.copyWith(
                activityPhase: AiRuntimePhase.generating,
                statusMessage: 'Generating response.',
                messages: updatedMessages,
              ),
            ),
          );
        },
      );

      final WorkspaceFeatureState refreshed = _requireState();
      final List<ComposerMessage> messages =
          List<ComposerMessage>.from(refreshed.aiState.messages);
      messages[messages.length - 1] = messages.last.copyWith(
        text: reply.text,
        citations: reply.citations,
      );
      await _commit(
        refreshed.copyWith(
          aiState: refreshed.aiState.copyWith(
            chatBusy: false,
            activityPhase: AiRuntimePhase.idle,
            statusMessage: _readyStatusMessage(refreshed.aiState),
            messages: messages,
            lastRetrievalSnippets: reply.citations,
          ),
        ),
      );
    } catch (error, stackTrace) {
      clarixLog.w(
        'Prompt generation failed.',
        error: error,
        stackTrace: stackTrace,
      );
      final WorkspaceFeatureState refreshed = _requireState();
      final List<ComposerMessage> messages =
          List<ComposerMessage>.from(refreshed.aiState.messages);
      messages[messages.length - 1] = messages.last.copyWith(
        text: 'I could not generate a response.\n\n$error',
      );
      await _commit(
        refreshed.copyWith(
          aiState: refreshed.aiState.copyWith(
            chatBusy: false,
            activityPhase: AiRuntimePhase.failed,
            statusMessage: 'Generation failed.',
            messages: messages,
          ),
        ),
      );
    }
  }

  Future<void> stopGeneration() async {
    await _ai.stopGeneration();
    final WorkspaceFeatureState current = _requireState();
    await _commit(
      current.copyWith(
        aiState: current.aiState.copyWith(
          chatBusy: false,
          activityPhase: AiRuntimePhase.idle,
          statusMessage: 'Generation stopped.',
        ),
      ),
    );
  }

  int _estimateDownloadedBytes({
    required int progress,
    required int totalBytes,
  }) {
    if (progress <= 0) {
      return 0;
    }
    if (progress >= 100) {
      return totalBytes;
    }
    return ((totalBytes * progress) / 100).round();
  }

  DocumentTabState? get activeTabState {
    final WorkspaceFeatureState? current = state.value;
    if (current == null) {
      return null;
    }
    final String? activeId = current.session.activeTabId;
    if (activeId == null) {
      return null;
    }
    for (final DocumentTabState tab in current.session.tabs) {
      if (tab.id == activeId) {
        return tab;
      }
    }
    return null;
  }

  Future<void> locateMissingFile(String tabId) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      allowMultiple: false,
      dialogTitle: 'Locate ${tab.title}',
    );
    final String? selectedPath = result?.files.single.path;
    if (selectedPath == null) {
      return;
    }

    final DocumentIdentity identity =
        await _identityService.identify(selectedPath);
    final bool hasStableFingerprint =
        RegExp(r'^[a-f0-9]{64}$').hasMatch(tab.documentId);
    if (hasStableFingerprint && identity.fingerprint != tab.documentId) {
      state = AsyncData(
        current.copyWith(
          bannerMessage: 'The selected file does not match ${tab.title}.',
        ),
      );
      return;
    }

    final DocumentMetadataStore store = await _metadataStore;
    final DocumentMetadata existing = current.documentMetadata[tab.documentId] ??
        await store.read(identity.fingerprint) ??
        DocumentMetadata.empty(identity);
    final DocumentMetadata updatedMetadata = existing.copyWith(
      identity: identity,
    );
    await store.write(updatedMetadata);

    final List<DocumentTabState> tabs = current.session.tabs
        .map(
          (DocumentTabState item) => item.id == tabId
              ? item.copyWith(
                  documentId: identity.fingerprint,
                  filePath: identity.path,
                  title: identity.title,
                  clearMissingFileMessage: true,
                  indexStatus: DocumentIndexStatus.queued,
                )
              : item,
        )
        .toList(growable: false);
    final List<String> recentFiles =
        List<String>.from(current.session.recentFiles)
          ..remove(identity.path)
          ..insert(0, identity.path);
    final Map<String, DocumentMetadata> metadata =
        Map<String, DocumentMetadata>.from(current.documentMetadata)
          ..remove(tab.documentId)
          ..[identity.fingerprint] = updatedMetadata;
    final WorkspaceSession session = current.session.copyWith(
      tabs: tabs,
      recentFiles: recentFiles.take(12).toList(growable: false),
    );
    await _commit(
      current.copyWith(
        session: session,
        documentMetadata: metadata,
        clearBannerMessage: true,
      ),
      persistAi: false,
    );
    unawaited(
      _indexDocument(tabs.firstWhere((DocumentTabState item) => item.id == tabId)),
    );
  }

  Future<void> toggleBookmark(String tabId, int pageNumber) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final DocumentMetadata? document = current.documentMetadata[tab.documentId];
    if (document == null) {
      return;
    }
    final List<DocumentBookmark> bookmarks =
        List<DocumentBookmark>.from(document.bookmarks);
    final int existing = bookmarks.indexWhere(
      (DocumentBookmark item) => item.pageNumber == pageNumber,
    );
    if (existing >= 0) {
      bookmarks.removeAt(existing);
    } else {
      bookmarks.add(
        DocumentBookmark(
          id: 'bookmark_${DateTime.now().microsecondsSinceEpoch}',
          pageNumber: pageNumber,
          label: 'Page $pageNumber',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      bookmarks.sort(
        (DocumentBookmark a, DocumentBookmark b) =>
            a.pageNumber.compareTo(b.pageNumber),
      );
    }
    await _saveDocumentMetadata(
      current,
      document.copyWith(bookmarks: bookmarks),
    );
  }

  Future<void> addNote({
    required String tabId,
    required int pageNumber,
    required String note,
  }) async {
    final String trimmed = note.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final DocumentMetadata? document = current.documentMetadata[tab.documentId];
    if (document == null) {
      return;
    }
    final List<DocumentAnnotation> annotations =
        List<DocumentAnnotation>.from(document.annotations)
          ..add(
            DocumentAnnotation(
              id: 'note_${DateTime.now().microsecondsSinceEpoch}',
              kind: AnnotationKind.note,
              pageNumber: pageNumber,
              pageRects: const <Rect>[],
              selectedText: '',
              note: trimmed,
              colorValue: 0x66FFD54F,
              createdAt: DateTime.now().toUtc(),
            ),
          );
    await _saveDocumentMetadata(
      current,
      document.copyWith(annotations: annotations),
    );
  }

  Future<void> addHighlight({
    required String tabId,
    required int pageNumber,
    required Rect pageRect,
    required String selectedText,
  }) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final DocumentMetadata? document = current.documentMetadata[tab.documentId];
    if (document == null || selectedText.trim().isEmpty) {
      return;
    }
    final List<DocumentAnnotation> annotations =
        List<DocumentAnnotation>.from(document.annotations)
          ..add(
            DocumentAnnotation(
              id: 'highlight_${DateTime.now().microsecondsSinceEpoch}',
              kind: AnnotationKind.highlight,
              pageNumber: pageNumber,
              pageRects: <Rect>[pageRect],
              selectedText: selectedText,
              note: null,
              colorValue: 0x66FFD54F,
              createdAt: DateTime.now().toUtc(),
            ),
          );
    await _saveDocumentMetadata(
      current,
      document.copyWith(annotations: annotations),
    );
  }
  Future<void> updateAnnotationNote({
    required String tabId,
    required String annotationId,
    required String note,
  }) async {
    final String trimmed = note.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final DocumentMetadata? document = current.documentMetadata[tab.documentId];
    if (document == null) {
      return;
    }
    await _saveDocumentMetadata(
      current,
      document.copyWith(
        annotations: document.annotations
            .map(
              (DocumentAnnotation item) => item.id == annotationId
                  ? item.copyWith(note: trimmed)
                  : item,
            )
            .toList(growable: false),
      ),
    );
  }
  Future<void> removeAnnotation(String tabId, String annotationId) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState tab = current.session.tabs.firstWhere(
      (DocumentTabState item) => item.id == tabId,
    );
    final DocumentMetadata? document = current.documentMetadata[tab.documentId];
    if (document == null) {
      return;
    }
    await _saveDocumentMetadata(
      current,
      document.copyWith(
        annotations: document.annotations
            .where((DocumentAnnotation item) => item.id != annotationId)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _saveDocumentMetadata(
    WorkspaceFeatureState current,
    DocumentMetadata document,
  ) async {
    await (await _metadataStore).write(document);
    final Map<String, DocumentMetadata> metadata =
        Map<String, DocumentMetadata>.from(current.documentMetadata)
          ..[document.identity.fingerprint] = document;
    state = AsyncData(current.copyWith(documentMetadata: metadata));
  }

  Future<Map<String, DocumentMetadata>> _loadDocumentMetadata(
    WorkspaceSession session,
  ) async {
    final DocumentMetadataStore store = await _metadataStore;
    final Map<String, DocumentMetadata> output = <String, DocumentMetadata>{};
    for (final DocumentTabState tab in session.tabs) {
      if (tab.isMissingFile ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(tab.documentId)) {
        continue;
      }
      final DocumentIdentity identity = await _identityService.identify(
        tab.filePath,
        pageCount: tab.pageCountHint,
      );
      DocumentMetadata document =
          await store.read(tab.documentId) ?? DocumentMetadata.empty(identity);
      if (document.identity.path != identity.path ||
          document.identity.modifiedAt != identity.modifiedAt) {
        document = document.copyWith(identity: identity);
        await store.write(document);
      }
      output[tab.documentId] = document;
    }
    return output;
  }

  Future<WorkspaceSession> _rehydrateWorkspace(WorkspaceSession session) async {
    if (!session.restorePreviousSession) {
      return session.copyWith(
        tabs: const <DocumentTabState>[],
        clearActiveTabId: true,
      );
    }

    final List<DocumentTabState> tabs = <DocumentTabState>[];
    final Set<String> fingerprints = <String>{};
    for (final DocumentTabState tab in session.tabs) {
      final bool exists = await _pdfExtraction.fileExists(tab.filePath);
      if (!exists) {
        tabs.add(
          tab.copyWith(
            missingFileMessage: 'File is no longer available on disk.',
          ),
        );
        continue;
      }
      DocumentIdentity identity;
      try {
        identity = await _identityService.identify(
          tab.filePath,
          pageCount: tab.pageCountHint,
        );
      } on FileSystemException {
        tabs.add(tab.copyWith(clearMissingFileMessage: true));
        continue;
      }
      if (!fingerprints.add(identity.fingerprint)) {
        continue;
      }
      tabs.add(
        tab.copyWith(
          documentId: identity.fingerprint,
          filePath: identity.path,
          title: identity.title,
          clearMissingFileMessage: true,
        ),
      );
    }

    final String? activeTabId = tabs.any(
      (DocumentTabState tab) => tab.id == session.activeTabId,
    )
        ? session.activeTabId
        : tabs.isEmpty
            ? null
            : tabs.first.id;

    return session.copyWith(
      tabs: tabs,
      activeTabId: activeTabId,
      clearActiveTabId: activeTabId == null,
    );
  }
  Future<void> _indexDocument(DocumentTabState tab) async {
    await _markTabIndexStatus(tab.id, DocumentIndexStatus.indexing);
    try {
      clarixLog.i('Indexing PDF document: ${tab.filePath}');
      final int chunkCount = await _chunkStore.replaceWithBatches(
        tab.documentId,
        _pdfExtraction.buildChunkBatches(
          path: tab.filePath,
          documentId: tab.documentId,
          title: tab.title,
          batchSize: 32,
        ),
      );
      await _markTabIndexStatus(
        tab.id,
        chunkCount == 0
            ? DocumentIndexStatus.unavailable
            : DocumentIndexStatus.indexed,
      );
      await _syncTabIndexToVectorStore(tab);
    } catch (error, stackTrace) {
      clarixLog.w(
        'PDF indexing failed: ${tab.filePath}',
        error: error,
        stackTrace: stackTrace,
      );
      await _markTabIndexStatus(tab.id, DocumentIndexStatus.failed);
    }
  }

  Future<void> _syncTabIndexToVectorStore(DocumentTabState tab) async {
    final WorkspaceFeatureState? current = state.value;
    if (current == null || !current.aiState.embeddingReady) {
      return;
    }
    final List<PdfChunkRecord> chunks = await _chunkStore.readChunks(tab.documentId);
    try {
      if (!current.aiState.chatBusy) {
        _setAiActivity(
          AiRuntimePhase.indexing,
          'Preparing PDF grounding for ${tab.title}.',
        );
      }
      await _ai.ensureDocumentIndexed(chunks);
      final WorkspaceFeatureState? refreshed = state.value;
      if (refreshed != null && !refreshed.aiState.chatBusy) {
        _setAiActivity(
          AiRuntimePhase.idle,
          _readyStatusMessage(refreshed.aiState),
        );
      }
    } catch (error, stackTrace) {
      clarixLog.w(
        'Vector-store sync failed for ${tab.documentId}',
        error: error,
        stackTrace: stackTrace,
      );
      final WorkspaceFeatureState? refreshed = state.value;
      if (refreshed != null && !refreshed.aiState.chatBusy) {
        _setAiActivity(
          AiRuntimePhase.failed,
          'PDF grounding is unavailable. Chat will continue without context.',
        );
      }
    }
  }

  Future<void> _markTabIndexStatus(
    String tabId,
    DocumentIndexStatus status,
  ) async {
    final WorkspaceFeatureState current = _requireState();
    final List<DocumentTabState> tabs = current.session.tabs
        .map(
          (DocumentTabState tab) =>
              tab.id == tabId ? tab.copyWith(indexStatus: status) : tab,
        )
        .toList(growable: false);
    final WorkspaceSession session = current.session.copyWith(tabs: tabs);
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> _setDownload(String modelId, DownloadTaskState task) async {
    final WorkspaceFeatureState current = _requireState();
    final DownloadTaskState stampedTask = task.copyWith(
      lastUpdatedAt: DateTime.now().toUtc(),
    );
    final Map<String, DownloadTaskState> downloads =
        Map<String, DownloadTaskState>.from(current.downloads)
          ..[modelId] = stampedTask;
    final List<ModelCatalogItem> catalog =
        _catalogService.buildCatalog(downloads: downloads);
    await _commit(
      current.copyWith(downloads: downloads, catalog: catalog),
      persistSession: false,
      persistAi: false,
    );
    await _sessionStore.writeDownloads(downloads);
  }

  Future<_AiReplyData> _generateReply({
    required String prompt,
    required bool useCurrentDocumentScope,
    required String? currentDocumentId,
    required void Function(AiRuntimePhase phase, String message) onStatus,
    required void Function(String token) onToken,
  }) async {
    final AiReply reply = await _ai.sendPrompt(
      prompt: prompt,
      useCurrentDocumentScope: useCurrentDocumentScope,
      currentDocumentId: currentDocumentId,
      onToken: onToken,
      onStatus: onStatus,
    );
    return _AiReplyData(
      text: reply.text,
      citations: reply.citations,
    );
  }

  Future<AiWorkspaceState> _restoreAiBestEffort(
    AiWorkspaceState storedAi,
    List<ModelCatalogItem> catalog,
  ) async {
    AiWorkspaceState restored = storedAi.copyWith(chatBusy: false);

    if (storedAi.activeEmbeddingModelId != null) {
      try {
        clarixLog.i(
          'Restoring embedding model: ${storedAi.activeEmbeddingModelId}',
        );
        if (!_ai.hasActiveEmbedder) {
          throw StateError(
            'No active embedding model set. Use FlutterGemma.installEmbedder() first.',
          );
        }
        restored = restored.copyWith(embeddingReady: true);
      } catch (error, stackTrace) {
        clarixLog.w(
          'Embedding restore failed; PDF reader will continue.',
          error: error,
          stackTrace: stackTrace,
        );
        restored = restored.copyWith(
          embeddingReady: false,
          vectorStoreReady: false,
          clearActiveEmbeddingModelId: true,
          statusMessage: 'Install a model to unlock local AI features.',
        );
      }
    }

    if (storedAi.activeInferenceModelId == null) {
      return restored.copyWith(inferenceReady: false);
    }

    final ModelCatalogItem? activeItem = _findCatalogItem(
      catalog,
      storedAi.activeInferenceModelId!,
    );
    if (activeItem == null) {
      clarixLog.w(
        'Saved inference model is no longer in the catalog: '
        '${storedAi.activeInferenceModelId}',
      );
      return restored.copyWith(
        inferenceReady: false,
        clearActiveInferenceModelId: true,
        statusMessage: 'Install a model to unlock local AI features.',
      );
    }

    try {
      final ModelInstallResult result =
          await _ai.activateInferenceModel(activeItem);
      clarixLog.i(
        'Inference model restored: ${activeItem.id} at ${result.installedPath}',
      );
      return restored.copyWith(
        inferenceReady: true,
        activityPhase: AiRuntimePhase.idle,
        activeInferenceModelId: activeItem.id,
        statusMessage: 'Inference model ready.',
      );
    } catch (error, stackTrace) {
      clarixLog.w(
        'Inference restore failed; PDF reader will continue.',
        error: error,
        stackTrace: stackTrace,
      );
      return restored.copyWith(
        inferenceReady: false,
        activityPhase: AiRuntimePhase.idle,
        clearActiveInferenceModelId: true,
        statusMessage: 'Install a model to unlock local AI features.',
      );
    }
  }

  ModelCatalogItem? _findCatalogItem(
    List<ModelCatalogItem> catalog,
    String modelId,
  ) {
    for (final ModelCatalogItem item in catalog) {
      if (item.id == modelId) {
        return item;
      }
    }
    return null;
  }

  void _logDownloadProgress(String modelId, int progress) {
    final int bucket = progress ~/ 10;
    if (_downloadLogBuckets[modelId] == bucket) {
      return;
    }
    _downloadLogBuckets[modelId] = bucket;
    clarixLog.i('Model download progress: $modelId $progress%');
  }

  void _setAiActivity(AiRuntimePhase phase, String message) {
    final WorkspaceFeatureState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        aiState: current.aiState.copyWith(
          activityPhase: phase,
          embeddingReady:
              phase == AiRuntimePhase.retrieving ? true : null,
          vectorStoreReady:
              phase == AiRuntimePhase.retrieving ? true : null,
          statusMessage: message,
        ),
      ),
    );
    clarixLog.i('AI activity: ${phase.name} - $message');
  }

  String _readyStatusMessage(AiWorkspaceState aiState) {
    if (aiState.inferenceReady && aiState.embeddingReady) {
      return 'AI ready. PDF grounding available.';
    }
    if (aiState.inferenceReady) {
      return 'AI ready. PDF grounding unavailable.';
    }
    return 'Install a model to unlock local AI features.';
  }

  Future<void> _commit(
    WorkspaceFeatureState newState, {
    bool persistSession = true,
    bool persistAi = true,
  }) async {
    state = AsyncData(
      newState.copyWith(
        catalog: _catalogService.buildCatalog(downloads: newState.downloads),
      ),
    );
    if (persistSession) {
      await _sessionStore.writeWorkspaceSession(newState.session);
    }
    if (persistAi) {
      await _sessionStore.writeAiWorkspaceState(newState.aiState);
    }
    await _sessionStore.writeDownloads(newState.downloads);
  }

  WorkspaceFeatureState _requireState() {
    final WorkspaceFeatureState? current = state.value;
    if (current == null) {
      throw StateError('Workspace state is not ready.');
    }
    return current;
  }
}

class _AiReplyData {
  const _AiReplyData({
    required this.text,
    required this.citations,
  });

  final String text;
  final List<CitationSnippet> citations;
}
