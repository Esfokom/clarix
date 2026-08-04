import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clarix_logger.dart';
import '../../../core/models.dart';
import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/session_store.dart';
import '../../utilities/domain/utility_job.dart';
import '../domain/workspace_feature_state.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/document_metadata_store.dart';
import '../infrastructure/local_rag_native_retriever.dart';
import '../infrastructure/provider_profile_store.dart';
import 'ai_runtime_service.dart';
import 'workspace_providers.dart';

class WorkspaceNotifier extends AsyncNotifier<WorkspaceFeatureState> {
  ClarixSessionStore get _sessionStore => ref.read(sessionStoreProvider);
  HybridPdfExtractionService get _pdfExtraction =>
      ref.read(pdfExtractionServiceProvider);
  DocumentChunkStore get _chunkStore => ref.read(chunkStoreProvider);
  LocalRagIndexer get _localRagIndexer => ref.read(localRagIndexerProvider);
  DocumentIdentityService get _identityService =>
      ref.read(documentIdentityServiceProvider);
  Future<DocumentMetadataStore> get _metadataStore =>
      ref.read(documentMetadataStoreProvider.future);
  AiRuntimeService get _ai => ref.read(aiRuntimeServiceProvider);
  ProviderProfileStore get _providerProfiles =>
      ref.read(providerProfileStoreProvider);

  @override
  Future<WorkspaceFeatureState> build() async {
    final WorkspaceSession storedSession = await _sessionStore
        .readWorkspaceSession();
    final AiWorkspaceState storedAi = await _sessionStore
        .readAiWorkspaceState();
    final List<AiProviderProfile> providerProfiles = await _providerProfiles
        .readProfiles();
    final String? defaultProfileId = await _providerProfiles
        .readDefaultProfileId();
    final WorkspaceSession restoredSession = await _rehydrateWorkspace(
      storedSession,
    );
    final Map<String, DocumentMetadata> documentMetadata =
        await _loadDocumentMetadata(restoredSession);
    AiWorkspaceState restoredAi = storedAi.copyWith(chatBusy: false);
    final AiProviderProfile? selectedProfile =
        _profileById(providerProfiles, defaultProfileId) ??
        (providerProfiles.isEmpty ? null : providerProfiles.first);
    final bool providerReady =
        selectedProfile != null &&
        (await _providerProfiles.readApiKey(selectedProfile.id))?.isNotEmpty ==
            true;
    restoredAi = restoredAi.copyWith(
      selectedProviderId: selectedProfile?.id,
      clearSelectedProviderId: selectedProfile == null,
      providerReady: providerReady,
      statusMessage: providerReady
          ? '${selectedProfile.label} is ready.'
          : 'Add a provider to start a remote AI chat.',
    );

    return WorkspaceFeatureState(
      session: restoredSession,
      aiState: restoredAi,
      outlines: const <String, List<OutlineNodeState>>{},
      documentMetadata: documentMetadata,
      composerExpanded: false,
      bannerMessage: null,
      providerProfiles: providerProfiles,
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
    final List<String> recentFiles = List<String>.from(
      current.session.recentFiles,
    );
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

  Future<void> openUtilityResult(UtilityResult result) {
    return ref
        .read(pdfUtilityServiceProvider)
        .openGeneratedPdf(result.outputPath);
  }

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
    final WorkspaceSession session = current.session.copyWith(
      activeTabId: tabId,
    );
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
    final WorkspaceSession session = current.session.copyWith(
      sidebarPane: pane,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> setLeftPaneWidth(double width) async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      leftPaneWidth: width,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> setRightPaneWidth(double width) async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      rightPaneWidth: width,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> toggleLeftPane() async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      leftPaneCollapsed: !current.session.leftPaneCollapsed,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> toggleRightPane() async {
    final WorkspaceFeatureState current = _requireState();
    final WorkspaceSession session = current.session.copyWith(
      rightPaneCollapsed: !current.session.rightPaneCollapsed,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> selectRightToolWindow(RightToolWindow tool) async {
    final WorkspaceFeatureState current = _requireState();
    final RightToolWindow next = current.session.rightToolWindow == tool
        ? RightToolWindow.none
        : tool;
    final WorkspaceSession session = current.session.copyWith(
      rightToolWindow: next,
    );
    await _commit(current.copyWith(session: session), persistAi: false);
  }

  Future<void> navigateToCitation(CitationSnippet citation) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState? tab = current.session.tabs
        .where(
          (DocumentTabState item) => item.documentId == citation.documentId,
        )
        .cast<DocumentTabState?>()
        .firstOrNull;
    if (tab == null) return;
    final List<DocumentTabState> tabs = current.session.tabs
        .map(
          (DocumentTabState item) => item.id == tab.id
              ? item.copyWith(currentPage: citation.pageNumber)
              : item,
        )
        .toList(growable: false);
    final WorkspaceSession session = current.session.copyWith(
      tabs: tabs,
      activeTabId: tab.id,
    );
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

  Future<void> setOutline(String tabId, List<OutlineNodeState> outline) async {
    final WorkspaceFeatureState current = _requireState();
    final Map<String, List<OutlineNodeState>> outlines =
        Map<String, List<OutlineNodeState>>.from(current.outlines)
          ..[tabId] = outline;
    state = AsyncData(current.copyWith(outlines: outlines));
  }

  Future<void> toggleScopeMode() async {
    final WorkspaceFeatureState current = _requireState();
    final AiWorkspaceState aiState = current.aiState.copyWith(
      useCurrentDocumentScope: !current.aiState.useCurrentDocumentScope,
    );
    await _commit(current.copyWith(aiState: aiState));
  }

  Future<void> selectProvider(String? profileId) async {
    final WorkspaceFeatureState current = _requireState();
    final AiProviderProfile? profile = _profileById(
      current.providerProfiles,
      profileId,
    );
    final bool ready =
        profile != null &&
        (await _providerProfiles.readApiKey(profile.id))?.isNotEmpty == true;
    if (profile != null) {
      await _providerProfiles.saveDefaultProfileId(profile.id);
    }
    await _commit(
      current.copyWith(
        aiState: current.aiState.copyWith(
          selectedProviderId: profile?.id,
          clearSelectedProviderId: profile == null,
          providerReady: ready,
          statusMessage: ready
              ? '${profile.label} is ready.'
              : 'Add an API key to use this provider.',
        ),
      ),
    );
  }

  Future<void> saveProvider(AiProviderProfile profile, {String? apiKey}) async {
    await _providerProfiles.saveProfile(
      profile,
      apiKey: apiKey?.trim().isEmpty == true ? null : apiKey?.trim(),
    );
    final WorkspaceFeatureState current = _requireState();
    final List<AiProviderProfile> profiles = await _providerProfiles
        .readProfiles();
    await _commit(current.copyWith(providerProfiles: profiles));
    await selectProvider(profile.id);
  }

  Future<void> testProvider(
    AiProviderProfile profile, {
    required String apiKey,
  }) => _ai.testProvider(profile, apiKey);

  Future<void> deleteProvider(String profileId) async {
    await _providerProfiles.deleteProfile(profileId);
    final WorkspaceFeatureState current = _requireState();
    final List<AiProviderProfile> profiles = await _providerProfiles
        .readProfiles();
    await _commit(current.copyWith(providerProfiles: profiles));
    if (current.aiState.selectedProviderId == profileId) {
      await selectProvider(null);
    }
  }

  Future<void> sendPrompt(String prompt) async {
    final WorkspaceFeatureState current = _requireState();
    final DocumentTabState? activeTab = activeTabState;
    if (prompt.trim().isEmpty || current.aiState.chatBusy) {
      return;
    }
    if (!current.aiState.providerReady ||
        current.aiState.selectedProviderId == null) {
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
          statusMessage:
              'Loading inference model. First response can take a minute.',
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
        profileId: current.aiState.selectedProviderId!,
        useCurrentDocumentScope: current.aiState.useCurrentDocumentScope,
        currentDocumentId: activeTab?.documentId,
        onStatus: _setAiActivity,
        onToken: (String token) {
          answerBuffer.write(token);
          final WorkspaceFeatureState live = _requireState();
          final List<ComposerMessage> updatedMessages =
              List<ComposerMessage>.from(live.aiState.messages);
          updatedMessages[updatedMessages.length - 1] = updatedMessages.last
              .copyWith(text: answerBuffer.toString());
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
      final List<ComposerMessage> messages = List<ComposerMessage>.from(
        refreshed.aiState.messages,
      );
      messages[messages.length - 1] = messages.last.copyWith(
        text: reply.text,
        citations: reply.citations,
      );
      await _commit(
        refreshed.copyWith(
          aiState: refreshed.aiState.copyWith(
            chatBusy: false,
            activityPhase: AiRuntimePhase.idle,
            statusMessage: 'Ready to chat with your remote provider.',
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
      final List<ComposerMessage> messages = List<ComposerMessage>.from(
        refreshed.aiState.messages,
      );
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

    final DocumentIdentity identity = await _identityService.identify(
      selectedPath,
    );
    final bool hasStableFingerprint = RegExp(
      r'^[a-f0-9]{64}$',
    ).hasMatch(tab.documentId);
    if (hasStableFingerprint && identity.fingerprint != tab.documentId) {
      state = AsyncData(
        current.copyWith(
          bannerMessage: 'The selected file does not match ${tab.title}.',
        ),
      );
      return;
    }

    final DocumentMetadataStore store = await _metadataStore;
    final DocumentMetadata existing =
        current.documentMetadata[tab.documentId] ??
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
      _indexDocument(
        tabs.firstWhere((DocumentTabState item) => item.id == tabId),
      ),
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
    final List<DocumentBookmark> bookmarks = List<DocumentBookmark>.from(
      document.bookmarks,
    );
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
        List<DocumentAnnotation>.from(document.annotations)..add(
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
        List<DocumentAnnotation>.from(document.annotations)..add(
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
              (DocumentAnnotation item) =>
                  item.id == annotationId ? item.copyWith(note: trimmed) : item,
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

    final String? activeTabId =
        tabs.any((DocumentTabState tab) => tab.id == session.activeTabId)
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
      final bool hasCachedChunks = await _chunkStore.hasChunks(tab.documentId);
      final int chunkCount;
      if (hasCachedChunks) {
        chunkCount = (await _chunkStore.readChunks(tab.documentId)).length;
      } else {
        chunkCount = await _chunkStore.replaceWithBatches(
          tab.documentId,
          _pdfExtraction.buildChunkBatches(
            path: tab.filePath,
            documentId: tab.documentId,
            title: tab.title,
            batchSize: 32,
          ),
        );
      }
      if (chunkCount > 0) {
        // Persistence is deliberately complete before loading/downloading the
        // embedding model. This background task never affects the normal PDF
        // text-index status.
        unawaited(_indexLocalRag(tab.documentId));
      }
      await _markTabIndexStatus(
        tab.id,
        chunkCount == 0
            ? DocumentIndexStatus.unavailable
            : DocumentIndexStatus.indexed,
      );
    } catch (error, stackTrace) {
      clarixLog.w(
        'PDF indexing failed: ${tab.filePath}',
        error: error,
        stackTrace: stackTrace,
      );
      await _markTabIndexStatus(tab.id, DocumentIndexStatus.failed);
    }
  }

  Future<void> _indexLocalRag(String documentId) async {
    try {
      final List<PdfChunkRecord> chunks = await _chunkStore.readChunks(
        documentId,
      );
      await _localRagIndexer.index(documentId, chunks);
    } catch (error, stackTrace) {
      // Native RAG is optional; LocalRagService will use persisted lexical
      // retrieval, so this must not alter document indexing state.
      clarixLog.w(
        'Local RAG indexing failed: $documentId',
        error: error,
        stackTrace: stackTrace,
      );
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

  Future<_AiReplyData> _generateReply({
    required String prompt,
    required String profileId,
    required bool useCurrentDocumentScope,
    required String? currentDocumentId,
    required void Function(AiRuntimePhase phase, String message) onStatus,
    required void Function(String token) onToken,
  }) async {
    final AiReply reply = await _ai.sendPrompt(
      prompt: prompt,
      profileId: profileId,
      useCurrentDocumentScope: useCurrentDocumentScope,
      currentDocumentId: currentDocumentId,
      onToken: onToken,
      onStatus: onStatus,
    );
    return _AiReplyData(text: reply.text, citations: reply.citations);
  }

  AiProviderProfile? _profileById(
    List<AiProviderProfile> profiles,
    String? profileId,
  ) {
    if (profileId == null) return null;
    for (final AiProviderProfile profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
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
          statusMessage: message,
        ),
      ),
    );
    clarixLog.i('AI activity: ${phase.name} - $message');
  }

  Future<void> _commit(
    WorkspaceFeatureState newState, {
    bool persistSession = true,
    bool persistAi = true,
  }) async {
    state = AsyncData(newState);
    if (persistSession) {
      await _sessionStore.writeWorkspaceSession(newState.session);
    }
    if (persistAi) {
      await _sessionStore.writeAiWorkspaceState(newState.aiState);
    }
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
  const _AiReplyData({required this.text, required this.citations});

  final String text;
  final List<CitationSnippet> citations;
}
