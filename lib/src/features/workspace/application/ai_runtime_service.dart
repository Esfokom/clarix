import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/clarix_logger.dart';
import '../../../core/local_gemma_model_store.dart';
import '../../../core/models.dart';

class AiRuntimeService {
  AiRuntimeService({
    this.localModelStore = const LocalGemmaModelStore(),
  });

  final LocalGemmaModelStore localModelStore;

  InferenceModel? _inferenceModel;
  InferenceChat? _chat;
  EmbeddingModel? _embeddingModel;
  final Set<String> _indexedChunkIds = <String>{};
  String? _vectorStorePath;

  Future<void> restore(AiWorkspaceState state) async {
    if (state.activeEmbeddingModelId != null) {
      await restoreEmbedding();
    }
    if (state.activeInferenceModelId != null) {
      await ensureInferenceModel();
    }
  }

  Future<void> restoreEmbedding() async {
    await ensureGroundingReady();
  }

  bool get hasActiveEmbedder => FlutterGemma.hasActiveEmbedder();

  Future<ModelInstallResult> activateInferenceModel(ModelCatalogItem item) async {
    final String? localPath = localModelStore.installedPathSync(item);
    if (localPath != null) {
      clarixLog.i('Reactivating inference model ${item.id} from $localPath');
      return registerLocalInferenceModel(item: item, path: localPath);
    }

    if (FlutterGemma.hasActiveModel()) {
      clarixLog.i('FlutterGemma already has an active inference model.');
      return ModelInstallResult(
        installedPath: localModelStore.pathForFilename(item.filename),
        sizeBytes: item.sizeBytes,
        usedLocalFile: false,
      );
    }

    throw StateError(
      'No local model file or active FlutterGemma inference model for ${item.id}.',
    );
  }

  Future<void> ensureInferenceModel() async {
    if (_inferenceModel != null && _chat != null) {
      return;
    }

    clarixLog.i('Creating active FlutterGemma inference chat.');
    final InferenceModel model = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
      enableSpeculativeDecoding: true,
    );
    final InferenceChat chat = await model.createChat(
      systemInstruction:
          'You are Clarix, an on-device PDF reading copilot. Prefer concise answers, cite pages when grounding against retrieved passages, and say when context is missing.',
    );
    _inferenceModel = model;
    _chat = chat;
  }

  Future<ModelInstallResult> installInferenceModel({
    required ModelCatalogItem item,
    required void Function(int progress) onProgress,
    required CancelToken cancelToken,
  }) async {
    final String? localPath = localModelStore.installedPathSync(item);
    if (localPath != null) {
      clarixLog.i('Using local inference model ${item.id} from $localPath');
      final ModelInstallResult result =
          await registerLocalInferenceModel(item: item, path: localPath);
      return result;
    }

    clarixLog.i('Downloading inference model ${item.id} from ${item.modelUrl}');
    await FlutterGemma.installModel(
      modelType: item.modelType ?? ModelType.gemma4,
      fileType: item.fileType,
    )
        .fromNetwork(item.modelUrl)
        .withCancelToken(cancelToken)
        .withProgress(onProgress)
        .install();

    final String? installedPath = localModelStore.pathForFilename(item.filename);
    clarixLog.i('Inference model ${item.id} installed at $installedPath');
    return ModelInstallResult(
      installedPath: installedPath,
      sizeBytes: _fileSizeOrDefault(installedPath, item.sizeBytes),
      usedLocalFile: false,
    );
  }

  Future<ModelInstallResult> installEmbeddingModel({
    required ModelCatalogItem item,
    required void Function(int progress) onModelProgress,
    required void Function(int progress) onTokenizerProgress,
    required CancelToken cancelToken,
  }) async {
    await FlutterGemma.installEmbedder()
        .modelFromNetwork(item.modelUrl)
        .tokenizerFromNetwork(item.tokenizerUrl!)
        .withCancelToken(cancelToken)
        .withModelProgress(onModelProgress)
        .withTokenizerProgress(onTokenizerProgress)
        .install();
    await ensureGroundingReady();
    final String? installedPath = localModelStore.pathForFilename(item.filename);
    clarixLog.i('Embedding model ${item.id} installed at $installedPath');
    return ModelInstallResult(
      installedPath: installedPath,
      sizeBytes: _fileSizeOrDefault(installedPath, item.sizeBytes),
      usedLocalFile: false,
    );
  }

  Future<void> ensureDocumentIndexed(List<PdfChunkRecord> chunks) async {
    if (chunks.isEmpty) {
      return;
    }
    await ensureGroundingReady();
    for (final PdfChunkRecord chunk in chunks) {
      if (_indexedChunkIds.contains(chunk.id)) {
        continue;
      }
      clarixLog.d('Adding document chunk to vector store: ${chunk.id}');
      await FlutterGemmaPlugin.instance.addDocument(
        id: chunk.id,
        content: chunk.text,
        metadata: chunk.metadataJson,
      );
      _indexedChunkIds.add(chunk.id);
    }
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required bool useCurrentDocumentScope,
    String? currentDocumentId,
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    onStatus?.call(
      AiRuntimePhase.loadingInference,
      'Loading inference model. First response can take a minute.',
    );
    await ensureInferenceModel();

    List<RetrievalResult> retrievals = const <RetrievalResult>[];
    if (!_groundingReady && hasActiveEmbedder) {
      try {
        onStatus?.call(
          AiRuntimePhase.preparingGrounding,
          'Preparing PDF grounding.',
        );
        await ensureGroundingReady();
      } catch (error, stackTrace) {
        clarixLog.w(
          'PDF grounding warm-up failed; continuing without retrieved context.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (_groundingReady) {
      try {
        onStatus?.call(
          AiRuntimePhase.retrieving,
          'Searching PDF context.',
        );
        retrievals = await FlutterGemmaPlugin.instance.searchSimilar(
          query: prompt,
          topK: 4,
          threshold: 0.15,
          filter: useCurrentDocumentScope && currentDocumentId != null
              ? Filter(
                  must: <Condition>[
                    FieldEquals(key: 'documentId', value: currentDocumentId),
                  ],
                )
              : null,
        );
      } catch (error, stackTrace) {
        clarixLog.w(
          'Vector retrieval failed; continuing without retrieved context.',
          error: error,
          stackTrace: stackTrace,
        );
        retrievals = const <RetrievalResult>[];
      }
    } else {
      clarixLog.d(
        'Skipping PDF retrieval because embedding/vector runtime is not ready.',
      );
    }

    final String finalPrompt;
    if (retrievals.isEmpty) {
      finalPrompt = prompt;
    } else {
      final String context = retrievals
          .asMap()
          .entries
          .map(
            (MapEntry<int, RetrievalResult> entry) =>
                '[source ${entry.key + 1}] ${entry.value.content}',
          )
          .join('\n\n');
      finalPrompt = '''
You are answering a question about local PDF content.
Use the retrieved context when it is relevant, and mention page numbers when available.
If the answer is not supported by the retrieved context, say so.

Retrieved context:
$context

User question:
$prompt
''';
    }

    onStatus?.call(AiRuntimePhase.generating, 'Generating response.');
    await _chat!.addQueryChunk(Message.text(text: finalPrompt, isUser: true));
    final StringBuffer answer = StringBuffer();
    await for (final ModelResponse response in _chat!.generateChatResponseAsync()) {
      if (response is TextResponse) {
        answer.write(response.token);
        onToken(response.token);
      }
    }

    final List<CitationSnippet> citations = retrievals
        .map(
          (RetrievalResult item) => CitationSnippet.fromMetadata(
            content: item.content,
            metadata: item.metadata,
          ),
        )
        .toList(growable: false);

    return AiReply(
      text: answer.toString(),
      citations: citations,
    );
  }

  Future<void> stopGeneration() async {
    await _chat?.stopGeneration();
  }

  Future<void> dispose() async {
    await _chat?.close();
    await _inferenceModel?.close();
    await _embeddingModel?.close();
  }

  Future<ModelInstallResult> registerLocalInferenceModel({
    required ModelCatalogItem item,
    required String path,
  }) async {
    await FlutterGemma.installModel(
      modelType: item.modelType ?? ModelType.gemma4,
      fileType: item.fileType,
    ).fromFile(path).install();
    return ModelInstallResult(
      installedPath: path,
      sizeBytes: localModelStore.fileSizeSync(path),
      usedLocalFile: true,
    );
  }

  int _fileSizeOrDefault(String? path, int fallback) {
    if (path == null) {
      return fallback;
    }
    final int size = localModelStore.fileSizeSync(path);
    return size == 0 ? fallback : size;
  }

  Future<void> _ensureVectorStore() async {
    if (_vectorStorePath != null) {
      return;
    }
    final Directory appDir = await getApplicationSupportDirectory();
    final String storePath = p.join(appDir.path, 'clarix', 'rag_store');
    await Directory(p.dirname(storePath)).create(recursive: true);
    clarixLog.i('Initializing vector store at $storePath');
    await FlutterGemmaPlugin.instance.initializeVectorStore(storePath);
    _vectorStorePath = storePath;
  }

  Future<void> ensureGroundingReady() async {
    await _ensureVectorStore();
    await _ensureEmbeddingModel();
  }

  Future<void> _ensureEmbeddingModel() async {
    if (_embeddingModel != null) {
      return;
    }
    if (!hasActiveEmbedder) {
      throw StateError(
        'No active embedding model set. Use FlutterGemma.installEmbedder() first.',
      );
    }
    clarixLog.i('Creating active FlutterGemma embedding model.');
    _embeddingModel = await FlutterGemma.getActiveEmbedder();
  }

  bool get _groundingReady => _vectorStorePath != null && _embeddingModel != null;
}

class ModelInstallResult {
  const ModelInstallResult({
    required this.installedPath,
    required this.sizeBytes,
    required this.usedLocalFile,
  });

  final String? installedPath;
  final int sizeBytes;
  final bool usedLocalFile;
}

class AiReply {
  const AiReply({
    required this.text,
    required this.citations,
  });

  final String text;
  final List<CitationSnippet> citations;
}
