import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/editing/editor_command_id.dart';
import '../../../core/session_store.dart';
import '../../utilities/application/pdf_utility_service.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/document_metadata_store.dart';
import '../infrastructure/conversation_store.dart';
import '../infrastructure/local_rag_native_retriever.dart';
import '../infrastructure/local_rag_service.dart';
import '../infrastructure/local_rag_store.dart';
import '../infrastructure/provider_profile_store.dart';
import '../infrastructure/pdf_native_edit_coordinator.dart';
import '../infrastructure/pdf_text_engine.dart';
import '../infrastructure/pdf_edit_save_service.dart';
import '../infrastructure/installed_font_catalog.dart';
import '../editing/application/editor_session_registry.dart';
import '../editing/domain/editor_document_state.dart';
import '../editing/infrastructure/editor_session_gateway.dart';
import 'ai_runtime_service.dart';
import 'action_permission_service.dart';
import 'ai_tool_registry.dart';
import 'pdf_editing_controller.dart';
import 'workspace_notifier.dart';
import '../domain/workspace_feature_state.dart';

enum EditingRollout {
  legacy,
  compareScenes,
  clarixRustEditingV1;

  static const String _configuredValue = String.fromEnvironment(
    'CLARIX_EDITING_ROLLOUT',
    defaultValue: 'clarixRustEditingV1',
  );

  static EditingRollout get configured => values.firstWhere(
    (value) => value.name == _configuredValue,
    orElse: () => clarixRustEditingV1,
  );

  EditingRolloutPolicy get policy => switch (this) {
    legacy => const EditingRolloutPolicy(
      opensRustSession: false,
      constructsLegacyEditor: true,
      rustGesturesEnabled: false,
    ),
    compareScenes => const EditingRolloutPolicy(
      opensRustSession: true,
      constructsLegacyEditor: true,
      rustGesturesEnabled: false,
    ),
    clarixRustEditingV1 => const EditingRolloutPolicy(
      opensRustSession: true,
      constructsLegacyEditor: false,
      rustGesturesEnabled: true,
    ),
  };
}

class EditingRolloutPolicy {
  const EditingRolloutPolicy({
    required this.opensRustSession,
    required this.constructsLegacyEditor,
    required this.rustGesturesEnabled,
  });

  final bool opensRustSession;
  final bool constructsLegacyEditor;
  final bool rustGesturesEnabled;

  @override
  bool operator ==(Object other) =>
      other is EditingRolloutPolicy &&
      opensRustSession == other.opensRustSession &&
      constructsLegacyEditor == other.constructsLegacyEditor &&
      rustGesturesEnabled == other.rustGesturesEnabled;

  @override
  int get hashCode => Object.hash(
    opensRustSession,
    constructsLegacyEditor,
    rustGesturesEnabled,
  );
}

final editingRolloutProvider = Provider<EditingRollout>(
  (Ref ref) => EditingRollout.configured,
);

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<ClarixSessionStore>(
  (Ref ref) => ClarixSessionStore(ref.watch(sharedPreferencesProvider)),
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

final aiToolRegistryProvider = Provider<AiToolRegistry>((Ref ref) {
  return AiToolRegistry(
    editing: ref.watch(pdfEditingControllerProvider),
    permissions: ref.watch(actionPermissionServiceProvider),
    pathForDocument: (documentId) {
      final workspace = ref.read(workspaceNotifierProvider).value;
      if (workspace == null) return null;
      for (final tab in workspace.session.tabs) {
        if (tab.documentId == documentId) return tab.filePath;
      }
      return null;
    },
  );
});

final aiRuntimeServiceProvider = Provider<AiRuntimeService>((Ref ref) {
  final AiRuntimeService service = AiRuntimeService(
    providerProfiles: ref.watch(providerProfileStoreProvider),
    chunkStore: ref.watch(chunkStoreProvider),
    localRag: ref.watch(localRagServiceProvider),
    toolRegistry: ref.watch(aiToolRegistryProvider),
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

final pdfTextEngineProvider = Provider<PdfTextEngine>(
  (Ref ref) => createPdfTextEngine(),
);

final pdfNativeEditCoordinatorProvider = Provider<PdfNativeEditCoordinator>(
  (Ref ref) =>
      PdfNativeEditCoordinator(mutator: ref.watch(pdfTextEngineProvider)),
);

final installedFontCatalogProvider = FutureProvider<InstalledFontCatalog>(
  (Ref ref) => InstalledFontCatalog.scan(),
);

final pdfEditSaveServiceProvider = Provider<PdfEditSaveService>((Ref ref) {
  final PdfTextEngine engine = ref.watch(pdfTextEngineProvider);
  return PdfEditSaveService(
    writeDraft: (File working, draft) async {
      final PdfDocument document = await PdfDocument.openFile(working.path);
      late final List<int> bytes;
      try {
        bytes = await engine.applyDraft(document: document, draft: draft);
      } finally {
        await document.dispose();
      }
      await working.writeAsBytes(bytes, flush: true);
    },
    validate: (File working) async {
      final PdfDocument document = await PdfDocument.openFile(working.path);
      try {
        for (final PdfPage page in document.pages) {
          await page.loadText();
        }
      } finally {
        await document.dispose();
      }
    },
  );
});

final legacyPdfEditingControllerProvider =
    ChangeNotifierProvider<PdfEditingController>(
      (Ref ref) => PdfEditingController(
        engine: ref.watch(pdfTextEngineProvider),
        saveService: ref.watch(pdfEditSaveServiceProvider),
        nativeCoordinator: ref.watch(pdfNativeEditCoordinatorProvider),
      ),
    );

final pdfEditingControllerProvider = Provider<PdfEditingController?>((Ref ref) {
  final rollout = ref.watch(editingRolloutProvider);
  if (!rollout.policy.constructsLegacyEditor) return null;
  return ref.watch(legacyPdfEditingControllerProvider);
});
