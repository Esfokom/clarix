import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/local_gemma_model_store.dart';
import '../../../core/model_catalog.dart';
import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/session_store.dart';
import '../infrastructure/document_chunk_store.dart';
import 'ai_runtime_service.dart';
import 'workspace_notifier.dart';
import '../domain/workspace_feature_state.dart';

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<ClarixSessionStore>(
  (Ref ref) => ClarixSessionStore(ref.watch(sharedPreferencesProvider)),
);

final localGemmaModelStoreProvider = Provider<LocalGemmaModelStore>(
  (Ref ref) => const LocalGemmaModelStore(),
);

final modelCatalogServiceProvider = Provider<ClarixModelCatalog>(
  (Ref ref) => ClarixModelCatalog(
    localModelStore: ref.watch(localGemmaModelStoreProvider),
  ),
);

final pdfExtractionServiceProvider = Provider<HybridPdfExtractionService>(
  (Ref ref) => HybridPdfExtractionService(),
);

final chunkStoreProvider = Provider<DocumentChunkStore>(
  (Ref ref) => DocumentChunkStore(),
);

final aiRuntimeServiceProvider = Provider<AiRuntimeService>((Ref ref) {
  final AiRuntimeService service = AiRuntimeService(
    localModelStore: ref.watch(localGemmaModelStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final workspaceNotifierProvider = AsyncNotifierProvider<
    WorkspaceNotifier, WorkspaceFeatureState>(WorkspaceNotifier.new);
