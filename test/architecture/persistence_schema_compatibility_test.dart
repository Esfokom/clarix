import 'dart:convert';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/core/session_store.dart';
import 'package:clarix/src/features/workspace/domain/ai_provider.dart';
import 'package:clarix/src/features/workspace/infrastructure/provider_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late SharedPreferencesAsyncPlatform? previousPlatform;

  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPlatform;
  });

  test('preference storage keys remain stable', () {
    expect(
      ClarixSessionStore.workspaceStorageKeyForTest,
      'clarix.workspace.session',
    );
    expect(ClarixSessionStore.aiStorageKeyForTest, 'clarix.ai.state');
    expect(
      ProviderProfileStore.profilesStorageKeyForTest,
      'clarix.ai.providers',
    );
    expect(
      ProviderProfileStore.defaultProfileStorageKeyForTest,
      'clarix.ai.default_provider',
    );
  });

  test('workspace session JSON round-trips without schema drift', () async {
    final DocumentTabState tab = DocumentTabState(
      id: 'tab-1',
      documentId: 'doc-1',
      filePath: r'C:\docs\sample.pdf',
      title: 'Sample',
      currentPage: 3,
      zoomScale: 1.25,
      scrollOffsetX: 4,
      scrollOffsetY: 80,
      searchQuery: 'contract',
      selectedSearchResult: 2,
      outlineExpanded: false,
      indexStatus: DocumentIndexStatus.indexed,
      missingFileMessage: null,
      lastOpenedAt: DateTime.utc(2026, 8, 17, 12),
      pageCountHint: 12,
    );
    final WorkspaceSession session = WorkspaceSession(
      restorePreviousSession: true,
      tabs: <DocumentTabState>[tab],
      activeTabId: tab.id,
      lastOpenedAt: DateTime.utc(2026, 8, 17, 12, 30),
      recentFiles: <String>[tab.filePath],
      sidebarPane: SidebarPane.outline,
      leftPaneWidth: 250,
      rightPaneWidth: 400,
      leftPaneCollapsed: false,
      rightPaneCollapsed: true,
      rightToolWindow: RightToolWindow.ai,
    );
    final Map<String, dynamic> expected = <String, dynamic>{
      'restorePreviousSession': true,
      'tabs': <Map<String, dynamic>>[tab.toJson()],
      'activeTabId': 'tab-1',
      'lastOpenedAt': '2026-08-17T12:30:00.000Z',
      'recentFiles': <String>[r'C:\docs\sample.pdf'],
      'sidebarPane': 'outline',
      'leftPaneWidth': 250.0,
      'rightPaneWidth': 400.0,
      'leftPaneCollapsed': false,
      'rightPaneCollapsed': true,
      'rightToolWindow': 'ai',
    };

    expect(session.toJson(), expected);
    final ClarixSessionStore store = ClarixSessionStore(
      SharedPreferencesAsync(),
    );
    await store.writeWorkspaceSession(session);
    expect((await store.readWorkspaceSession()).toJson(), expected);
  });

  test('AI state JSON and defaults remain stable', () async {
    final AiWorkspaceState state = AiWorkspaceState.initial().copyWith(
      providerReady: true,
      selectedProviderId: 'openai',
      activityPhase: AiRuntimePhase.generating,
      statusMessage: 'Generating',
      useCurrentDocumentScope: false,
    );
    final Map<String, dynamic> expected = <String, dynamic>{
      'providerReady': true,
      'selectedProviderId': 'openai',
      'activityPhase': 'generating',
      'statusMessage': 'Generating',
      'useCurrentDocumentScope': false,
    };

    expect(state.toJson(), expected);
    final ClarixSessionStore store = ClarixSessionStore(
      SharedPreferencesAsync(),
    );
    await store.writeAiWorkspaceState(state);
    final AiWorkspaceState restored = await store.readAiWorkspaceState();
    expect(restored.toJson(), <String, dynamic>{
      ...expected,
      'activityPhase': 'idle',
    });
    expect(AiWorkspaceState.fromJson(const <String, dynamic>{}).toJson(), {
      'providerReady': false,
      'selectedProviderId': null,
      'activityPhase': 'idle',
      'statusMessage': 'Add a provider to start a remote AI chat.',
      'useCurrentDocumentScope': true,
    });
  });

  test('provider and retrieval metadata schemas remain stable', () {
    final AiProviderProfile profile = AiProviderProfile.create(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      modelId: 'gpt-5',
      shareRetrievedPassages: true,
      contextWindowTokens: 128000,
      headers: const <String, String>{'X-Tenant': 'clarix'},
    );
    expect(profile.toJson(), <String, dynamic>{
      'id': 'openai',
      'label': 'OpenAI',
      'baseUrl': 'https://api.openai.com/v1/',
      'modelId': 'gpt-5',
      'shareRetrievedPassages': true,
      'contextWindowTokens': 128000,
      'headers': const <String, String>{'X-Tenant': 'clarix'},
    });
    expect(AiProviderProfile.fromJson(profile.toJson()), profile);

    const PdfChunkRecord chunk = PdfChunkRecord(
      id: 'chunk-1',
      documentId: 'doc-1',
      title: 'Sample',
      pageNumber: 4,
      chunkOrder: 2,
      text: 'A representative passage.',
      sectionTitle: 'Terms',
    );
    expect(jsonDecode(chunk.metadataJson), <String, dynamic>{
      'documentId': 'doc-1',
      'title': 'Sample',
      'pageNumber': 4,
      'chunkOrder': 2,
      'sectionTitle': 'Terms',
    });
    expect(
      CitationSnippet.fromMetadata(
        content: chunk.text,
        metadata: chunk.metadataJson,
      ).pageNumber,
      4,
    );
  });

  test('document metadata JSON round-trips bookmarks and annotations', () {
    final DateTime timestamp = DateTime.utc(2026, 8, 17, 13);
    final DocumentIdentity identity = DocumentIdentity(
      fingerprint: 'doc-1',
      path: r'C:\docs\sample.pdf',
      title: 'Sample',
      byteLength: 1024,
      modifiedAt: timestamp,
      pageCount: 12,
      isEncrypted: false,
    );
    final DocumentMetadata metadata = DocumentMetadata(
      identity: identity,
      bookmarks: <DocumentBookmark>[
        DocumentBookmark(
          id: 'bookmark-1',
          pageNumber: 2,
          label: 'Clause',
          createdAt: timestamp,
        ),
      ],
      annotations: <DocumentAnnotation>[
        DocumentAnnotation(
          id: 'annotation-1',
          kind: AnnotationKind.highlight,
          pageNumber: 2,
          pageRects: const <Rect>[Rect.fromLTWH(1, 2, 3, 4)],
          selectedText: 'Clause',
          note: 'Review',
          colorValue: 0x66FFD54F,
          createdAt: timestamp,
        ),
      ],
    );

    expect(
      DocumentMetadata.fromJson(metadata.toJson()).toJson(),
      metadata.toJson(),
    );
  });
}
