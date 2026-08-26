import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/pdf_oxide_bridge.dart';
import '../../../core/session_store.dart';
import '../../utilities/application/pdf_utility_service.dart';
import '../infrastructure/document_metadata_store.dart';
import '../../annotations/infrastructure/annotation_sidecar_store.dart';
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

final annotationSidecarStoreProvider = Provider<AnnotationSidecarStore>(
  (Ref ref) => AnnotationSidecarStore(),
);

final workspaceNotifierProvider =
    AsyncNotifierProvider<WorkspaceNotifier, WorkspaceFeatureState>(
      WorkspaceNotifier.new,
    );
