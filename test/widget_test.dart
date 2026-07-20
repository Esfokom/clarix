import 'package:clarix/src/core/model_catalog.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/core/pdf_oxide_bridge.dart';
import 'package:clarix/src/core/local_gemma_model_store.dart';
import 'package:clarix/src/features/workspace/application/ai_runtime_service.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/model_catalog_sheet.dart';
import 'package:flutter/material.dart';
import 'package:clarix/src/core/cancel_token.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void _useEmptyAsyncPreferences() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
}

void main() {
  test('workspace session round-trips through json', () {
    final WorkspaceSession session = WorkspaceSession.initial().copyWith(
      tabs: <DocumentTabState>[
        DocumentTabState.create(
          id: 'tab-1',
          documentId: 'doc_1',
          filePath: 'C:/docs/report.pdf',
          title: 'report.pdf',
        ).copyWith(currentPage: 8),
      ],
      activeTabId: 'tab-1',
      recentFiles: const <String>['C:/docs/report.pdf'],
    );

    final WorkspaceSession restored = WorkspaceSession.fromJson(
      session.toJson(),
    );

    expect(restored.activeTabId, 'tab-1');
    expect(restored.tabs.single.currentPage, 8);
    expect(restored.recentFiles.single, 'C:/docs/report.pdf');
  });

  test('ai workspace runtime phase is live-only after restore', () {
    final AiWorkspaceState state = AiWorkspaceState.initial().copyWith(
      inferenceReady: true,
      activityPhase: AiRuntimePhase.loadingInference,
      statusMessage: 'Loading inference model.',
    );

    final AiWorkspaceState restored = AiWorkspaceState.fromJson(
      state.toJson(),
    );

    expect(state.activityPhase, AiRuntimePhase.loadingInference);
    expect(restored.activityPhase, AiRuntimePhase.idle);
    expect(restored.inferenceReady, isTrue);
  });

  test('model catalog marks completed downloads as installed', () {
    const ClarixModelCatalog catalog = ClarixModelCatalog();

    final List<ModelCatalogItem> items = catalog.buildCatalog(
      downloads: <String, DownloadTaskState>{
        'gemma-4-e2b-it': DownloadTaskState.initial(
          'gemma-4-e2b-it',
        ).copyWith(status: DownloadTaskStatus.completed, progress: 100),
      },
    );

    final ModelCatalogItem gemmaItem = items.firstWhere(
      (ModelCatalogItem item) => item.id == 'gemma-4-e2b-it',
    );

    expect(gemmaItem.installState, ModelInstallState.installed);
  });

  test('gemma 4 catalog entries use resolve litertlm model files', () {
    const ClarixModelCatalog catalog = ClarixModelCatalog();

    final List<ModelCatalogItem> items = catalog.buildCatalog(
      downloads: <String, DownloadTaskState>{},
    );

    final ModelCatalogItem e2b = items.firstWhere(
      (ModelCatalogItem item) => item.id == 'gemma-4-e2b-it',
    );
    final ModelCatalogItem e4b = items.firstWhere(
      (ModelCatalogItem item) => item.id == 'gemma-4-e4b-it',
    );

    expect(e2b.modelUrl, contains('/resolve/main/'));
    expect(e2b.modelUrl, endsWith('gemma-4-E2B-it.litertlm'));
    expect(e2b.filename, 'gemma-4-E2B-it.litertlm');
    expect(e2b.fileType, ModelFileType.litertlm);
    expect(e4b.modelUrl, contains('/resolve/main/'));
    expect(e4b.modelUrl, endsWith('gemma-4-E4B-it.litertlm'));
    expect(e4b.filename, 'gemma-4-E4B-it.litertlm');
    expect(e4b.fileType, ModelFileType.litertlm);
  });

  test('model catalog marks local model files as installed', () {
    final ClarixModelCatalog catalog = ClarixModelCatalog(
      localModelStore: _FakeLocalGemmaModelStore(
        paths: <String, String>{
          'gemma-4-E2B-it.litertlm':
              r'C:\Users\S\AppData\Local\flutter_gemma\gemma-4-E2B-it.litertlm',
        },
      ),
    );

    final List<ModelCatalogItem> items = catalog.buildCatalog(
      downloads: <String, DownloadTaskState>{},
    );

    final ModelCatalogItem e2b = items.firstWhere(
      (ModelCatalogItem item) => item.id == 'gemma-4-e2b-it',
    );

    expect(e2b.installState, ModelInstallState.installed);
    expect(e2b.installedPath, contains('gemma-4-E2B-it.litertlm'));
  });

  test('completed downloads hide transfer controls', () {
    expect(
      shouldShowModelTransferControls(DownloadTaskStatus.completed),
      isFalse,
    );
    expect(shouldShowModelTransferControls(DownloadTaskStatus.running), isTrue);
    expect(
      shouldShowModelTransferControls(DownloadTaskStatus.validating),
      isTrue,
    );
  });

  test('vertical PDF scrollbar geometry matches visible document ratio', () {
    final PdfScrollbarGeometry? geometry = calculatePdfScrollbarGeometry(
      axis: PdfScrollbarAxis.vertical,
      viewportSize: const Size(800, 600),
      visibleRect: const Rect.fromLTWH(0, 250, 800, 500),
      documentSize: const Size(800, 2000),
    );

    expect(geometry, isNotNull);
    expect(geometry!.thumbExtent, 150);
    expect(geometry.thumbLeading, closeTo(75, 0.001));
  });

  test('horizontal PDF scrollbar geometry matches visible document ratio', () {
    final PdfScrollbarGeometry? geometry = calculatePdfScrollbarGeometry(
      axis: PdfScrollbarAxis.horizontal,
      viewportSize: const Size(900, 600),
      visibleRect: const Rect.fromLTWH(300, 0, 450, 600),
      documentSize: const Size(1800, 600),
    );

    expect(geometry, isNotNull);
    expect(geometry!.thumbExtent, 225);
    expect(geometry.thumbLeading, 150);
  });

  test('PDF scrollbar thumb drag maps back to visible document offset', () {
    final PdfScrollbarGeometry geometry = calculatePdfScrollbarGeometry(
      axis: PdfScrollbarAxis.vertical,
      viewportSize: const Size(800, 600),
      visibleRect: const Rect.fromLTWH(0, 250, 800, 500),
      documentSize: const Size(800, 2000),
    )!;

    expect(geometry.visibleLeadingForThumbDrag(37.5), closeTo(375, 0.001));
  });

  test('PDF zoom anchor uses global-to-viewer-local conversion', () {
    final Offset anchor = resolvePdfZoomAnchor(
      globalPosition: const Offset(520, 340),
      fallbackLocalPosition: const Offset(400, 300),
      globalToLocal: (Offset global) => global - const Offset(120, 40),
    );

    expect(anchor, const Offset(400, 300));
  });

  test('PDF zoom anchor falls back to center when conversion fails', () {
    final Offset anchor = resolvePdfZoomAnchor(
      globalPosition: const Offset(520, 340),
      fallbackLocalPosition: const Offset(400, 300),
      globalToLocal: (_) => null,
    );

    expect(anchor, const Offset(400, 300));
  });

  test('ai runtime prefers a local inference model before network install',
      () async {
    final _RecordingAiRuntimeService service = _RecordingAiRuntimeService(
      localModelStore: _FakeLocalGemmaModelStore(
        paths: <String, String>{
          'gemma-4-E2B-it.litertlm':
              r'C:\Users\S\AppData\Local\flutter_gemma\gemma-4-E2B-it.litertlm',
        },
      ),
    );
    const ClarixModelCatalog catalog = ClarixModelCatalog();
    final ModelCatalogItem e2b = catalog
        .buildCatalog(downloads: <String, DownloadTaskState>{})
        .firstWhere((ModelCatalogItem item) => item.id == 'gemma-4-e2b-it');
    final List<int> progress = <int>[];

    final ModelInstallResult result = await service.installInferenceModel(
      item: e2b,
      onProgress: progress.add,
      cancelToken: CancelToken(),
    );

    expect(service.registeredPath, contains('gemma-4-E2B-it.litertlm'));
    expect(result.usedLocalFile, isTrue);
    expect(progress, isEmpty);
  });

  test(
    'workspace startup continues when remembered inference model is inactive',
    () async {
      _useEmptyAsyncPreferences();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          aiRuntimeServiceProvider.overrideWithValue(
            _ThrowingAiRuntimeService(),
          ),
          pdfExtractionServiceProvider.overrideWithValue(
            _ExistingPdfExtraction(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final WorkspaceSession session = WorkspaceSession.initial().copyWith(
        tabs: <DocumentTabState>[
          DocumentTabState.create(
            id: 'tab-1',
            documentId: 'paper',
            filePath: 'C:/docs/paper.pdf',
            title: 'paper.pdf',
          ),
        ],
        activeTabId: 'tab-1',
      );
      final AiWorkspaceState aiState = AiWorkspaceState.initial().copyWith(
        inferenceReady: true,
        activeInferenceModelId: 'gemma-4-e2b-it',
      );
      await container.read(sessionStoreProvider).writeWorkspaceSession(session);
      await container.read(sessionStoreProvider).writeAiWorkspaceState(aiState);

      final WorkspaceFeatureState restored = await container.read(
        workspaceNotifierProvider.future,
      );

      expect(restored.session.activeTabId, 'tab-1');
      expect(restored.session.tabs.single.title, 'paper.pdf');
      expect(restored.aiState.inferenceReady, false);
      expect(restored.aiState.activeInferenceModelId, isNull);
      expect(restored.aiState.statusMessage, contains('Install'));
    },
  );

  test(
    'workspace restore marks active embedder available without loading it',
    () async {
      _useEmptyAsyncPreferences();
      final _EmbeddingRestoreAiRuntimeService aiRuntime =
          _EmbeddingRestoreAiRuntimeService();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          aiRuntimeServiceProvider.overrideWithValue(aiRuntime),
          pdfExtractionServiceProvider.overrideWithValue(
            _ExistingPdfExtraction(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final AiWorkspaceState aiState = AiWorkspaceState.initial().copyWith(
        embeddingReady: true,
        activeEmbeddingModelId: 'embedding-gemma-1024',
      );
      await container.read(sessionStoreProvider).writeAiWorkspaceState(aiState);

      final WorkspaceFeatureState restored = await container.read(
        workspaceNotifierProvider.future,
      );

      expect(restored.aiState.embeddingReady, isTrue);
      expect(restored.aiState.vectorStoreReady, isFalse);
      expect(aiRuntime.restoreEmbeddingCalled, isFalse);
    },
  );
}

class _ThrowingAiRuntimeService extends AiRuntimeService {
  @override
  Future<void> restore(AiWorkspaceState state) async {
    throw StateError(
      'No active inference model set. Use `FlutterGemma.installModel()` first',
    );
  }

  @override
  Future<ModelInstallResult> activateInferenceModel(ModelCatalogItem item) {
    throw StateError(
      'No active inference model set. Use `FlutterGemma.installModel()` first',
    );
  }
}

class _ExistingPdfExtraction extends HybridPdfExtractionService {
  @override
  Future<bool> fileExists(String path) async => true;
}

class _EmbeddingRestoreAiRuntimeService extends AiRuntimeService {
  bool restoreEmbeddingCalled = false;

  @override
  bool get hasActiveEmbedder => true;

  @override
  Future<void> restoreEmbedding() async {
    restoreEmbeddingCalled = true;
  }
}

class _FakeLocalGemmaModelStore extends LocalGemmaModelStore {
  const _FakeLocalGemmaModelStore({required this.paths});

  final Map<String, String> paths;

  @override
  String? pathForFilename(String filename) => paths[filename];

  @override
  String? installedPathSync(ModelCatalogItem item) => paths[item.filename];

  @override
  int fileSizeSync(String path) => 123;
}

class _RecordingAiRuntimeService extends AiRuntimeService {
  _RecordingAiRuntimeService({required super.localModelStore});

  String? registeredPath;

  @override
  Future<ModelInstallResult> registerLocalInferenceModel({
    required ModelCatalogItem item,
    required String path,
  }) async {
    registeredPath = path;
    return ModelInstallResult(
      installedPath: path,
      sizeBytes: 123,
      usedLocalFile: true,
    );
  }
}
