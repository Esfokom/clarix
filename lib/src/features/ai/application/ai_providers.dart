import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_feature_state.dart';
import '../infrastructure/ai_preferences_store.dart';
import '../infrastructure/conversation_store.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/local_rag_native_retriever.dart';
import '../infrastructure/local_rag_service.dart';
import '../infrastructure/local_rag_store.dart';
import '../infrastructure/local_model_store.dart';
import '../infrastructure/flutter_gemma_local_model_gateway.dart';
import '../infrastructure/groq_transcription_service.dart';
import '../infrastructure/provider_profile_store.dart';
import '../infrastructure/record_voice_recorder.dart';
import '../infrastructure/voice_input_settings_store.dart';
import 'ai_notifier.dart';
import 'ai_runtime_service.dart';
import 'local_model_runtime.dart';

final aiSharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final aiPreferencesStoreProvider = Provider<AiPreferencesStore>(
  (Ref ref) => AiPreferencesStore(ref.watch(aiSharedPreferencesProvider)),
);

final providerProfileStoreProvider = Provider<ProviderProfileStore>(
  (Ref ref) => ProviderProfileStore(
    preferences: ref.watch(aiSharedPreferencesProvider),
    secretStore: FlutterSecureProviderSecretStore(),
  ),
);

final conversationStoreProvider = FutureProvider<ConversationStore>((
  Ref ref,
) async {
  final ConversationStore store = ConversationStore();
  await store.initialize();
  return store;
});

final chunkStoreProvider = Provider<DocumentChunkStore>(
  (Ref ref) => DocumentChunkStore(),
);
final localRagStoreProvider = Provider<LocalRagStore>(
  (Ref ref) => LocalRagStore(),
);
final localModelStoreProvider = Provider<LocalModelStore>(
  (Ref ref) => LocalModelStore(ref.watch(aiSharedPreferencesProvider)),
);
final localModelRuntimeProvider = Provider<LocalModelRuntime>(
  (Ref ref) => LocalModelRuntime(gateway: FlutterGemmaLocalModelGateway()),
);
final localRagNativeRetrieverProvider = Provider<NativeLocalRagRetriever>((
  Ref ref,
) {
  final DocumentChunkStore chunks = ref.watch(chunkStoreProvider);
  return NativeLocalRagRetriever(
    store: ref.watch(localRagStoreProvider),
    readChunks: chunks.readChunks,
  );
});
final localRagIndexerProvider = Provider<LocalRagIndexer>(
  (Ref ref) => ref.watch(localRagNativeRetrieverProvider),
);
final localRagServiceProvider = Provider<LocalRagService>((Ref ref) {
  final DocumentChunkStore chunks = ref.watch(chunkStoreProvider);
  return LocalRagService(
    readChunks: chunks.readChunks,
    nativeRetriever: ref.watch(localRagNativeRetrieverProvider),
  );
});

final aiRuntimeServiceProvider = Provider<AiRuntimeService>((Ref ref) {
  final AiRuntimeService service = AiRuntimeService(
    providerProfiles: ref.watch(providerProfileStoreProvider),
    localModels: ref.watch(localModelStoreProvider),
    localRuntime: ref.watch(localModelRuntimeProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final groqTranscriptionServiceProvider = Provider<GroqTranscriptionService>(
  (Ref ref) =>
      GroqTranscriptionService(apiKey: GroqTranscriptionService.apiKey),
);

final voiceRecorderProvider = Provider<RecordVoiceRecorder>(
  (Ref ref) => RecordVoiceRecorder(),
);
final voiceInputSettingsStoreProvider = Provider<VoiceInputSettingsStore>(
  (Ref ref) => VoiceInputSettingsStore(ref.watch(aiSharedPreferencesProvider)),
);

final aiNotifierProvider = AsyncNotifierProvider<AiNotifier, AiFeatureState>(
  AiNotifier.new,
);
