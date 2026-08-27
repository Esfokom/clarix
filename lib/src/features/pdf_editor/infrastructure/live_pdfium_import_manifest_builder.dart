import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../../../core/editing/live_pdfium_editor_port.dart';
import '../domain/pdf_text_types.dart';

/// Produces semantic identities and physical locators from one PDFium scan.
/// The identity is path-based; text and geometry are deliberately excluded.
final class LivePdfiumImportManifestBuilder {
  const LivePdfiumImportManifestBuilder();

  LivePdfiumImportManifest build({
    required String sourceFingerprint,
    required Iterable<PdfTextBlock> blocks,
  }) {
    final bindings = <LivePdfiumImportBinding>[];
    for (final block in blocks) {
      if (block.objectPaths.length != 1) continue;
      final path = block.objectPaths.single;
      final sourceKey = _sourceKey(
        sourceFingerprint,
        block.locator.pageNumber,
        path,
      );
      bindings.add(
        LivePdfiumImportBinding(
          objectId: _uuidV5(sourceKey),
          sourceKey: sourceKey,
          sourceRevision: sourceFingerprint,
          locator: EditorPhysicalLocator(
            pageNumber: block.locator.pageNumber,
            objectPath: path,
            objectType: 'text',
            sourceFingerprint: sourceFingerprint,
            objectRevision: 0,
          ),
        ),
      );
    }
    return LivePdfiumImportManifest(
      sourceFingerprint: sourceFingerprint,
      bindings: List<LivePdfiumImportBinding>.unmodifiable(bindings),
    );
  }
}

String _sourceKey(String fingerprint, int pageNumber, List<int> objectPath) =>
    '$fingerprint/live-pdfium/page/$pageNumber/object/${objectPath.join('.')}';

String _uuidV5(String value) {
  const namespace = <int>[
    0x63,
    0x6c,
    0x61,
    0x72,
    0x69,
    0x78,
    0x45,
    0x44,
    0x91,
    0x54,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
  ];
  final bytes = Uint8List.fromList(<int>[...namespace, ...value.codeUnits]);
  final digest = sha1.convert(bytes).bytes;
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  final hex = digest
      .take(16)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
