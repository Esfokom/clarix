import '../../../core/cancel_token.dart';
import '../../../core/local_gemma_model_store.dart';
import '../../../core/models.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/openai_compatible_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import 'ai_agent_runtime.dart';

class AiRuntimeService {
  AiRuntimeService({
    this.localModelStore = const LocalGemmaModelStore(),
    ProviderProfileStore? providerProfiles,
    DocumentChunkStore? chunkStore,
  }) : _providerProfiles = providerProfiles, _chunkStore = chunkStore;

  final LocalGemmaModelStore localModelStore;
  final ProviderProfileStore? _providerProfiles;
  final DocumentChunkStore? _chunkStore;

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
    required String profileId,
    required bool useCurrentDocumentScope,
    String? currentDocumentId,
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final store = _providerProfiles;
    final chunks = _chunkStore;
    if (store == null || chunks == null) throw StateError('Configure a remote AI provider to chat.');
    final profiles = await store.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) throw StateError('Select a remote AI provider to chat.');
    final key = await store.readApiKey(profile.id);
    if (key == null || key.isEmpty) throw StateError('Add an API key for ${profile.label}.');
    onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}.');
    final reply = await AiAgentRuntime(
      provider: OpenAiCompatibleProvider(),
      readChunks: chunks.readChunks,
    ).run(AiAgentRequest(
      profile: profile,
      apiKey: key,
      prompt: prompt,
      documentIds: useCurrentDocumentScope && currentDocumentId != null
          ? <String>[currentDocumentId] : const <String>[],
    ));
    onToken(reply.text);
    return AiReply(text: reply.text, citations: reply.citations);
  }

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
