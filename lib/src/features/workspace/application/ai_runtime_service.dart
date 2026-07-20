import '../../../core/cancel_token.dart';
import '../../../core/local_gemma_model_store.dart';
import '../../../core/models.dart';

class AiRuntimeService {
  AiRuntimeService({this.localModelStore = const LocalGemmaModelStore()});

  final LocalGemmaModelStore localModelStore;

  Future<void> restore(AiWorkspaceState state) async {}
  Future<void> restoreEmbedding() async {}
  bool get hasActiveEmbedder => false;

  Future<ModelInstallResult> activateInferenceModel(ModelCatalogItem item) =>
      Future<ModelInstallResult>.error(
        StateError('Local Gemma models are no longer supported.'),
      );

  Future<ModelInstallResult> registerLocalInferenceModel({
    required ModelCatalogItem item,
    required String path,
  }) => Future<ModelInstallResult>.error(
    StateError('Local Gemma models are no longer supported.'),
  );

  Future<ModelInstallResult> installInferenceModel({
    required ModelCatalogItem item,
    required void Function(int progress) onProgress,
    required CancelToken cancelToken,
  }) => Future<ModelInstallResult>.error(
    StateError('Local Gemma models are no longer supported.'),
  );

  Future<ModelInstallResult> installEmbeddingModel({
    required ModelCatalogItem item,
    required void Function(int progress) onModelProgress,
    required void Function(int progress) onTokenizerProgress,
    required CancelToken cancelToken,
  }) => Future<ModelInstallResult>.error(
    StateError('Local Gemma models are no longer supported.'),
  );

  Future<void> ensureDocumentIndexed(List<PdfChunkRecord> chunks) async {}

  Future<AiReply> sendPrompt({
    required String prompt,
    required bool useCurrentDocumentScope,
    String? currentDocumentId,
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) => Future<AiReply>.error(
    StateError('Configure a remote AI provider to chat.'),
  );

  Future<void> stopGeneration() async {}
  Future<void> dispose() async {}
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
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
