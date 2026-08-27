import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../../../core/ffi/editing_api.dart' as native;
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
    for (final block in _importableBlocks(blocks)) {
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

  /// Converts the same PDFium scan into the semantic hydration payload.
  /// Only one-object blocks are safe to route today: a grouped block has no
  /// single recursive PDFium locator for a whole-text physical replacement.
  native.NativeLivePageImport buildPageImport({
    required int expectedRevision,
    required String sourceFingerprint,
    required int pageNumber,
    required double width,
    required double height,
    required Iterable<PdfTextBlock> blocks,
  }) => native.NativeLivePageImport(
    expectedRevision: BigInt.from(expectedRevision),
    pageNumber: pageNumber,
    width: width,
    height: height,
    objects: _importableBlocks(blocks)
        .map((block) {
          final path = block.objectPaths.single;
          final sourceKey = _sourceKey(sourceFingerprint, pageNumber, path);
          final style = block.styleAt(0);
          return native.NativeLiveTextObject(
            objectId: _uuidV5(sourceKey),
            sourceKey: sourceKey,
            sourceRevision: sourceFingerprint,
            text: block.text,
            bounds: native.NativePdfBox(
              left: block.bounds.left,
              bottom: block.bounds.bottom,
              right: block.bounds.right,
              top: block.bounds.top,
            ),
            style: native.NativeTextStyle(
              fontFamily: style.fontFamily,
              fontSize: style.fontSize,
              fontWeight: style.fontWeight.clamp(0, 65535),
              italic: style.italic,
              colorRgba: Uint8List.fromList(<int>[
                (style.fillColorValue >> 16) & 0xff,
                (style.fillColorValue >> 8) & 0xff,
                style.fillColorValue & 0xff,
                (style.fillColorValue >> 24) & 0xff,
              ]),
            ),
            baseline: block.baseline,
            editable: block.isEditable,
          );
        })
        .toList(growable: false),
  );

  Iterable<PdfTextBlock> _importableBlocks(Iterable<PdfTextBlock> blocks) =>
      blocks.where(
        (block) => block.objectPaths.length == 1 && block.runs.isNotEmpty,
      );
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
