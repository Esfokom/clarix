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
import '../../utilities/application/pdf_utility_service.dart';
import '../infrastructure/document_metadata_store.dart';
import '../../annotations/annotations.dart';
import '../../tts/tts.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'workspace_notifier.dart';
import '../domain/workspace_feature_state.dart';



final kittenTtsServiceProvider = Provider<KittenTtsService>(
  (Ref ref) => KittenTtsService(),
);

final audioToAudioServiceProvider = Provider<AudioToAudioService>(
  (Ref ref) => AudioToAudioService(
    ttsService: ref.watch(kittenTtsServiceProvider),
  ),
);

final latexOcrServiceProvider = Provider<LatexOcrService>(
  (Ref ref) => LatexOcrService(),
);

final smartRedactionServiceProvider = Provider<SmartRedactionService>(
  (Ref ref) => SmartRedactionService(),
);

final offlineAudioBookServiceProvider = Provider<OfflineAudioBookService>(
  (Ref ref) => OfflineAudioBookService(
    ttsService: ref.watch(kittenTtsServiceProvider),
  ),
);

final gemmaSimulationServiceProvider = Provider<GemmaSimulationService>(
  (Ref ref) => GemmaSimulationService(),
);

final gemmaTimelineServiceProvider = Provider<GemmaTimelineService>(
  (Ref ref) => GemmaTimelineService(),
);

final gemmaCognitiveUiServiceProvider = Provider<GemmaCognitiveUiService>(
  (Ref ref) => GemmaCognitiveUiService(),
);

final gemmaAuditorServiceProvider = Provider<GemmaAuditorService>(
  (Ref ref) => GemmaAuditorService(),
);

final voiceCopilotServiceProvider = Provider<VoiceCopilotService>(
  (Ref ref) => VoiceCopilotService(),
);

final livingDocumentServiceProvider = Provider<LivingDocumentService>(
  (Ref ref) => LivingDocumentService(),
);

final forensicMarginaliaServiceProvider = Provider<ForensicMarginaliaService>(
  (Ref ref) => ForensicMarginaliaService(),
);

final brainTrustDebaterServiceProvider = Provider<BrainTrustDebaterService>(
  (Ref ref) => BrainTrustDebaterService(),
);
final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<ClarixSessionStore>(
  (Ref ref) => ClarixSessionStore(ref.watch(sharedPreferencesProvider)),
);

final actionPermissionServiceProvider = Provider<ActionPermissionService>(
  (Ref ref) => ActionPermissionService(
    store: SharedPreferencesActionPermissionStore(
      ref.watch(sharedPreferencesProvider),
    ),
    defaultPolicy: ActionPermissionPolicy.askAlways,
  ),
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
    final registry = ref.watch(editorSessionRegistryProvider);
    final bridge = registry.agentBridge(tabId);
    if (bridge == null) {
      final subscription = registry.watchAgentBridge(tabId).listen((bridge) {
        if (bridge != null) {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(subscription.cancel);
      return null;
    }
    final controller = AgentRunController(bridge: bridge);
    ref.onDispose(() => unawaited(controller.dispose()));
    return controller;
  },
);

final installedFontCatalogProvider = FutureProvider<InstalledFontCatalog>(
  (Ref ref) => InstalledFontCatalog.scan(),
);

final activeMarkdownEditorTabIdProvider =
    NotifierProvider<ActiveMarkdownEditorTabIdNotifier, String?>(
      ActiveMarkdownEditorTabIdNotifier.new,
    );

class ActiveMarkdownEditorTabIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setTabId(String? tabId) => state = tabId;
}

