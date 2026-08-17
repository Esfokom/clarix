import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/editing/editor_command_id.dart';
import '../../../core/session_store.dart';
import 'package:clarix/src/features/ai/ai.dart';
import '../../utilities/application/pdf_utility_service.dart';
import '../infrastructure/document_metadata_store.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import '../agent/application/agent_run_controller.dart';
import 'ai_runtime_service.dart';
import 'action_permission_service.dart';
import 'workspace_notifier.dart';
import '../domain/workspace_feature_state.dart';

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<ClarixSessionStore>(
  (Ref ref) => ClarixSessionStore(ref.watch(sharedPreferencesProvider)),
);

final aiPreferencesStoreProvider = Provider<AiPreferencesStore>(
  (Ref ref) => AiPreferencesStore(ref.watch(sharedPreferencesProvider)),
);

final pdfExtractionServiceProvider = Provider<HybridPdfExtractionService>(
  (Ref ref) => HybridPdfExtractionService(),
);

final pdfUtilityServiceProvider = Provider<PdfUtilityService>((Ref ref) {
  return PdfUtilityService(
    openPdfFiles: ref.read(workspaceNotifierProvider.notifier).openPdfFiles,
  );
});

final pdfDocumentRefProvider = Provider.autoDispose
    .family<PdfDocumentRef, String>((Ref ref, String path) {
      final File file = File(path);
      Future<Uint8List>? bytes;
      final int fileSize = file.existsSync() ? file.lengthSync() : 0;
      return PdfDocumentRefCustom(
        fileSize: fileSize,
        sourceName: path,
        key: PdfDocumentRefKey(path),
        read: (Uint8List buffer, int position, int size) async {
          final Uint8List data = await (bytes ??= file.readAsBytes());
          if (position >= data.length) return 0;
          final int count = size.clamp(0, data.length - position);
          buffer.setRange(0, count, data, position);
          return count;
        },
      );
    });

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

final conversationStoreProvider = FutureProvider<ConversationStore>((
  Ref ref,
) async {
  final ConversationStore store = ConversationStore();
  await store.initialize();
  return store;
});

final actionPermissionServiceProvider = Provider<ActionPermissionService>(
  (Ref ref) => ActionPermissionService(
    store: SharedPreferencesActionPermissionStore(
      ref.watch(sharedPreferencesProvider),
    ),
    defaultPolicy: ActionPermissionPolicy.askAlways,
  ),
);

final aiRuntimeServiceProvider = Provider<AiRuntimeService>((Ref ref) {
  final AiRuntimeService service = AiRuntimeService(
    providerProfiles: ref.watch(providerProfileStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final workspaceNotifierProvider =
    AsyncNotifierProvider<WorkspaceNotifier, WorkspaceFeatureState>(
      WorkspaceNotifier.new,
    );

final editorSessionRegistryProvider = Provider<EditorSessionRegistry>((
  Ref ref,
) {
  final EditorSessionRegistry registry = EditorSessionRegistry(
    gateways: BridgeEditorSessionGateway.new,
    commandIds: newEditorCommandId,
  );
  ref.onDispose(() => unawaited(registry.closeAll()));
  return registry;
});

final editorDocumentStateProvider =
    StreamProvider.family<EditorDocumentState?, String>((ref, tabId) {
      return ref.watch(editorSessionRegistryProvider).watch(tabId);
    });

final agentRunControllerProvider = Provider.family<AgentRunController?, String>(
  (Ref ref, String tabId) {
    final bridge = ref.watch(editorSessionRegistryProvider).agentBridge(tabId);
    if (bridge == null) return null;
    final controller = AgentRunController(bridge: bridge);
    ref.onDispose(() => unawaited(controller.dispose()));
    return controller;
  },
);

final installedFontCatalogProvider = FutureProvider<InstalledFontCatalog>(
  (Ref ref) => InstalledFontCatalog.scan(),
);
