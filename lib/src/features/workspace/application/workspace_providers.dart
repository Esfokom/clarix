import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/session_store.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/document_metadata_store.dart';
import '../infrastructure/local_rag_native_retriever.dart';
import '../infrastructure/local_rag_service.dart';
import '../infrastructure/local_rag_store.dart';
import '../infrastructure/provider_profile_store.dart';
import 'ai_runtime_service.dart';
import 'workspace_notifier.dart';
import '../domain/workspace_feature_state.dart';

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<ClarixSessionStore>(
  (Ref ref) => ClarixSessionStore(ref.watch(sharedPreferencesProvider)),
);

final pdfExtractionServiceProvider = Provider<HybridPdfExtractionService>(
  (Ref ref) => HybridPdfExtractionService(),
);

final pdfDocumentRefProvider = Provider.autoDispose
    .family<PdfDocumentRefFile, String>(
      (Ref ref, String path) => PdfDocumentRefFile(path),
    );

final chunkStoreProvider = Provider<DocumentChunkStore>(
  (Ref ref) => DocumentChunkStore(),
);
final localRagStoreProvider = Provider<LocalRagStore>(
  (Ref ref) => LocalRagStore(),
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
final providerProfileStoreProvider = Provider<ProviderProfileStore>(
  (Ref ref) => ProviderProfileStore(
    preferences: ref.watch(sharedPreferencesProvider),
    secretStore: FlutterSecureProviderSecretStore(),
  ),
);
final documentIdentityServiceProvider = Provider<DocumentIdentityService>(
  (Ref ref) => DocumentIdentityService(),
);

final documentMetadataStoreProvider = FutureProvider<DocumentMetadataStore>((
  Ref ref,
) async {
  Directory root;
  try {
    root = await getApplicationSupportDirectory();
  } catch (_) {
    root = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}clarix',
    );
  }
  return DocumentMetadataStore(root: root);
});

final aiRuntimeServiceProvider = Provider<AiRuntimeService>((Ref ref) {
  final AiRuntimeService service = AiRuntimeService(
    providerProfiles: ref.watch(providerProfileStoreProvider),
    chunkStore: ref.watch(chunkStoreProvider),
    localRag: ref.watch(localRagServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final workspaceNotifierProvider =
    AsyncNotifierProvider<WorkspaceNotifier, WorkspaceFeatureState>(
      WorkspaceNotifier.new,
    );
