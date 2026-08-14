import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'clarix_rust_runtime.dart';
import 'ffi/api.dart' as ffi;
import 'ffi/lib.dart' as ffi_types;
import 'models.dart' as core_models;
import 'models.dart';

abstract class PdfOxideBridge {
  const PdfOxideBridge();

  Future<PdfDocumentMetadata> openDocument(String path);
  Future<String?> extractPageText(String path, int pageNumber);
  Future<List<String>> extractDocumentText(String path);
  Future<List<PdfSearchMatch>> searchDocument(String path, Pattern query);
  Future<PdfNativeAnnotations> readPdfAnnotations(String path);
  Stream<List<PdfChunkRecord>> buildChunkBatches(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
    int batchSize = 32,
  });

  Future<void> savePdfAnnotations({
    required String path,
    required List<DocumentBookmark> bookmarks,
    required List<DocumentAnnotation> annotations,
  });

  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  }) async {
    final List<PdfChunkRecord> output = <PdfChunkRecord>[];
    await for (final List<PdfChunkRecord> batch in buildChunkBatches(
      path,
      documentId: documentId,
      title: title,
      maxCharsPerChunk: maxCharsPerChunk,
    )) {
      output.addAll(batch);
    }
    return output;
  }
}

class FrbPdfOxideBridge implements PdfOxideBridge {
  const FrbPdfOxideBridge();

  Future<ffi.NativePdfSession> _session(String path) async {
    if (!await ClarixRustRuntime.ensureInitialized()) {
      throw UnimplementedError(
        'The bundled Clarix Rust runtime is unavailable: ${ClarixRustRuntime.initializationError ?? 'no runtime DLL was loaded'}',
      );
    }
    return ffi.NativePdfSession.open(path: path);
  }

  @override
  Stream<List<PdfChunkRecord>> buildChunkBatches(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
    int batchSize = 32,
  }) async* {
    final ffi.NativePdfSession session = await _session(path);
    await for (final String event in session.index(
      maxCharsPerChunk: BigInt.from(maxCharsPerChunk),
      batchSize: BigInt.from(batchSize),
    )) {
      final Map<String, dynamic> decoded =
          jsonDecode(event) as Map<String, dynamic>;
      final List<dynamic>? values = decoded['ChunkBatch'] as List<dynamic>?;
      if (values == null) continue;
      yield values
          .map((dynamic value) {
            final Map<String, dynamic> chunk = value as Map<String, dynamic>;
            return PdfChunkRecord(
              id: '$documentId:${chunk['page_number']}:${chunk['chunk_order']}',
              documentId: documentId,
              title: title,
              pageNumber: chunk['page_number'] as int,
              chunkOrder: chunk['chunk_order'] as int,
              text: chunk['text'] as String,
              sectionTitle: chunk['section_title'] as String?,
            );
          })
          .toList(growable: false);
    }
  }

  @override
  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  }) async {
    final List<PdfChunkRecord> chunks = <PdfChunkRecord>[];
    await for (final List<PdfChunkRecord> batch in buildChunkBatches(
      path,
      documentId: documentId,
      title: title,
      maxCharsPerChunk: maxCharsPerChunk,
    )) {
      chunks.addAll(batch);
    }
    return chunks;
  }

  @override
  Future<List<String>> extractDocumentText(String path) async {
    final core_models.PdfDocumentMetadata metadata = await openDocument(path);
    final List<String> text = <String>[];
    for (var page = 1; page <= metadata.pageCount; page++) {
      text.add(await extractPageText(path, page) ?? '');
    }
    return text;
  }

  @override
  Future<String?> extractPageText(String path, int pageNumber) async =>
      (await _session(path)).pageText(pageNumber: BigInt.from(pageNumber));

  @override
  Future<core_models.PdfDocumentMetadata> openDocument(String path) async {
    final ffi_types.PdfDocumentMetadata metadata = await (await _session(
      path,
    )).metadata();
    return core_models.PdfDocumentMetadata(
      documentId: metadata.documentId,
      title: metadata.title,
      pageCount: metadata.pageCount.toInt(),
      isEncrypted: metadata.isEncrypted,
    );
  }

  @override
  Future<List<PdfSearchMatch>> searchDocument(
    String path,
    Pattern query,
  ) async {
    final String queryText = query is String ? query : query.toString();
    return (await (await _session(path)).search(query: queryText))
        .map(
          (ffi_types.PdfSearchMatch match) => core_models.PdfSearchMatch(
            pageNumber: match.pageNumber.toInt(),
            text: match.text,
            bounds: Rect.fromLTRB(
              match.bounds.$1,
              match.bounds.$2,
              match.bounds.$3,
              match.bounds.$4,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PdfNativeAnnotations> readPdfAnnotations(String path) async {
    if (!await ClarixRustRuntime.ensureInitialized()) {
      throw UnimplementedError(
        'The bundled Clarix Rust runtime is unavailable: ${ClarixRustRuntime.initializationError ?? 'no runtime DLL was loaded'}',
      );
    }
    final ffi.NativePdfAnnotations native = await ffi.readPdfAnnotations(
      path: path,
    );
    return PdfNativeAnnotations(
      bookmarks: native.bookmarks
          .map(
            (item) => DocumentBookmark(
              id: item.id,
              label: item.title,
              pageNumber: item.pageNumber.toInt(),
              createdAt: DateTime.now().toUtc(),
            ),
          )
          .toList(growable: false),
      highlights: native.highlights
          .map(
            (item) => DocumentAnnotation(
              id: item.id,
              kind: AnnotationKind.highlight,
              pageNumber: item.pageNumber.toInt(),
              pageRects: _pageRectsFromQuadPoints(item),
              selectedText: item.text,
              note: null,
              colorValue:
                  (((item.opacity * 255).round().clamp(0, 255)) << 24) |
                  (((item.red * 255).round().clamp(0, 255)) << 16) |
                  (((item.green * 255).round().clamp(0, 255)) << 8) |
                  ((item.blue * 255).round().clamp(0, 255)),
              createdAt: DateTime.now().toUtc(),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> savePdfAnnotations({
    required String path,
    required List<DocumentBookmark> bookmarks,
    required List<DocumentAnnotation> annotations,
  }) async {
    if (!await ClarixRustRuntime.ensureInitialized()) {
      throw UnimplementedError(
        'The bundled Clarix Rust runtime is unavailable: ${ClarixRustRuntime.initializationError ?? 'no runtime DLL was loaded'}',
      );
    }
    final ffi.NativePdfSaveRequest request = ffi.NativePdfSaveRequest(
      path: path,
      bookmarks: bookmarks
          .map(
            (item) => ffi.NativePdfBookmark(
              id: item.id,
              title: item.label,
              pageNumber: BigInt.from(item.pageNumber),
            ),
          )
          .toList(growable: false),
      highlights: annotations
          .where(
            (item) =>
                item.kind == AnnotationKind.highlight &&
                item.pageRects.isNotEmpty,
          )
          .map((item) {
            final Rect rect = item.pageRects.first;
            final int color = item.colorValue;
            return ffi.NativePdfHighlight(
              id: item.id,
              pageNumber: BigInt.from(item.pageNumber),
              left: rect.left,
              top: rect.top,
              right: rect.right,
              bottom: rect.bottom,
              red: ((color >> 16) & 0xff) / 255,
              green: ((color >> 8) & 0xff) / 255,
              blue: (color & 0xff) / 255,
              opacity: ((color >> 24) & 0xff) / 255,
              text: item.selectedText,
              quadPoints: Float32List.fromList(
                item.pageRects
                    .expand(
                      (rect) => <double>[
                        rect.left,
                        rect.bottom,
                        rect.right,
                        rect.bottom,
                        rect.left,
                        rect.top,
                        rect.right,
                        rect.top,
                      ],
                    )
                    .toList(growable: false),
              ),
            );
          })
          .toList(growable: false),
    );
    try {
      await ffi.savePdfAnnotations(request: request);
    } catch (error) {
      if (!error.toString().contains('invalid file trailer')) rethrow;
      final File normalized = await _normalizeWithPdfium(path);
      try {
        await ffi.savePdfAnnotations(
          request: ffi.NativePdfSaveRequest(
            path: normalized.path,
            outputPath: path,
            bookmarks: request.bookmarks,
            highlights: request.highlights,
          ),
        );
      } finally {
        if (await normalized.exists()) await normalized.delete();
      }
    }
  }

  Future<File> _normalizeWithPdfium(String path) async {
    await pdfrxInitialize();
    final PdfDocument document = await PdfDocument.openFile(path);
    final File normalized = File(
      p.join(
        p.dirname(path),
        '.${p.basenameWithoutExtension(path)}.clarix-normalized-${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    try {
      await normalized.writeAsBytes(
        await document.encodePdf(incremental: false),
        flush: true,
      );
      return normalized;
    } catch (_) {
      if (await normalized.exists()) await normalized.delete();
      rethrow;
    } finally {
      await document.dispose();
    }
  }

  List<Rect> _pageRectsFromQuadPoints(ffi.NativePdfHighlight highlight) {
    if (highlight.quadPoints.length < 8) {
      return <Rect>[
        Rect.fromLTRB(
          highlight.left,
          highlight.bottom,
          highlight.right,
          highlight.top,
        ),
      ];
    }
    return <Rect>[
      for (int index = 0; index + 7 < highlight.quadPoints.length; index += 8)
        Rect.fromLTRB(
          highlight.quadPoints[index],
          highlight.quadPoints[index + 5],
          highlight.quadPoints[index + 2],
          highlight.quadPoints[index + 1],
        ),
    ];
  }
}

class PdfrxFallbackBridge extends PdfOxideBridge {
  const PdfrxFallbackBridge();

  PdfDocumentListenable _document(String path) =>
      PdfDocumentRefFile(path).resolveListenable();

  @override
  Future<PdfDocumentMetadata> openDocument(String path) async {
    final PdfDocumentMetadata? metadata = await _document(path).useDocument(
      (PdfDocument document) => PdfDocumentMetadata(
        documentId: _documentIdFromPath(path),
        title: p.basename(path),
        pageCount: document.pages.length,
        isEncrypted: document.isEncrypted,
      ),
    );
    if (metadata == null) {
      throw FileSystemException('Could not load PDF document.', path);
    }
    return metadata;
  }

  @override
  Future<PdfNativeAnnotations> readPdfAnnotations(String path) =>
      throw UnsupportedError(
        'Reading PDF annotations requires the native Clarix runtime.',
      );

  @override
  Future<void> savePdfAnnotations({
    required String path,
    required List<DocumentBookmark> bookmarks,
    required List<DocumentAnnotation> annotations,
  }) => throw UnsupportedError(
    'Saving PDF annotations requires the native Clarix runtime.',
  );

  @override
  Future<String?> extractPageText(String path, int pageNumber) async {
    return await _document(path).useDocument<String?>((
      PdfDocument document,
    ) async {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        return null;
      }
      final PdfPageRawText? pageText = await document.pages[pageNumber - 1]
          .loadText();
      return pageText?.fullText;
    });
  }

  @override
  Future<List<String>> extractDocumentText(String path) async {
    final List<String>? pages = await _document(path).useDocument((
      PdfDocument document,
    ) async {
      final List<String> output = <String>[];
      for (final PdfPage page in document.pages) {
        final PdfPageRawText? pageText = await page.loadText();
        output.add(pageText?.fullText ?? '');
      }
      return output;
    });
    return pages ?? const <String>[];
  }

  @override
  Future<List<PdfSearchMatch>> searchDocument(
    String path,
    Pattern query,
  ) async {
    final String needle = (query is String ? query : query.toString())
        .trim()
        .toLowerCase();
    if (needle.isEmpty) {
      return const <PdfSearchMatch>[];
    }
    final List<PdfSearchMatch>? matches = await _document(path).useDocument((
      PdfDocument document,
    ) async {
      final List<PdfSearchMatch> output = <PdfSearchMatch>[];
      for (final PdfPage page in document.pages) {
        final PdfPageRawText? rawText = await page.loadText();
        if (rawText == null || rawText.fullText.isEmpty) {
          continue;
        }
        final String lower = rawText.fullText.toLowerCase();
        int start = 0;
        while (start < lower.length) {
          final int index = lower.indexOf(needle, start);
          if (index < 0) {
            break;
          }
          final int end = index + needle.length;
          Rect bounds = Rect.zero;
          if (index < rawText.charRects.length &&
              end <= rawText.charRects.length) {
            final PdfRect pdfBounds = rawText.charRects.boundingRect(
              start: index,
              end: end,
            );
            bounds = Rect.fromLTRB(
              pdfBounds.left,
              pdfBounds.bottom,
              pdfBounds.right,
              pdfBounds.top,
            );
          }
          output.add(
            PdfSearchMatch(
              pageNumber: page.pageNumber,
              text: rawText.fullText.substring(index, end),
              bounds: bounds,
            ),
          );
          start = max(end, index + 1);
        }
      }
      return output;
    });
    return matches ?? const <PdfSearchMatch>[];
  }

  @override
  Stream<List<PdfChunkRecord>> buildChunkBatches(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
    int batchSize = 32,
  }) {
    final StreamController<List<PdfChunkRecord>> controller =
        StreamController<List<PdfChunkRecord>>();
    unawaited(
      Future<void>(() async {
        try {
          await _document(path).useDocument((PdfDocument document) async {
            final List<PdfChunkRecord> batch = <PdfChunkRecord>[];
            int chunkOrder = 0;
            for (final PdfPage page in document.pages) {
              final PdfPageRawText? rawText = await page.loadText();
              final String normalized = _normalizeText(rawText?.fullText ?? '');
              if (normalized.isEmpty) {
                continue;
              }
              for (final String chunk in _sliceText(
                normalized,
                maxCharsPerChunk: maxCharsPerChunk,
              )) {
                batch.add(
                  PdfChunkRecord(
                    id: '$documentId:${page.pageNumber}:$chunkOrder',
                    documentId: documentId,
                    title: title,
                    pageNumber: page.pageNumber,
                    chunkOrder: chunkOrder++,
                    text: chunk,
                  ),
                );
                if (batch.length == batchSize) {
                  controller.add(List<PdfChunkRecord>.of(batch));
                  batch.clear();
                }
              }
            }
            if (batch.isNotEmpty) {
              controller.add(List<PdfChunkRecord>.of(batch));
            }
          });
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        } finally {
          await controller.close();
        }
      }),
    );
    return controller.stream;
  }

  List<String> _sliceText(String text, {required int maxCharsPerChunk}) {
    if (maxCharsPerChunk <= 0) {
      return const <String>[];
    }
    final List<String> output = <String>[];
    final StringBuffer current = StringBuffer();
    int currentLength = 0;
    for (final String word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) {
        continue;
      }
      final int nextLength =
          currentLength + (currentLength == 0 ? 0 : 1) + word.runes.length;
      if (currentLength > 0 && nextLength > maxCharsPerChunk) {
        output.add(current.toString());
        current.clear();
        currentLength = 0;
      }
      if (currentLength > 0) {
        current.write(' ');
        currentLength++;
      }
      current.write(word);
      currentLength += word.runes.length;
    }
    if (currentLength > 0) {
      output.add(current.toString());
    }
    return output;
  }

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _documentIdFromPath(String path) {
    return p
        .basenameWithoutExtension(path)
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}

class HybridPdfExtractionService {
  HybridPdfExtractionService({
    PdfOxideBridge? primary,
    PdfOxideBridge? fallback,
  }) : _primary = primary ?? const FrbPdfOxideBridge(),
       _fallback = fallback ?? const PdfrxFallbackBridge();

  final PdfOxideBridge _primary;
  final PdfOxideBridge _fallback;

  Future<PdfDocumentMetadata> openDocument(String path) async {
    try {
      return await _primary.openDocument(path);
    } on UnimplementedError {
      return _fallback.openDocument(path);
    }
  }

  Stream<List<PdfChunkRecord>> buildChunkBatches({
    required String path,
    required String documentId,
    required String title,
    int batchSize = 32,
  }) async* {
    try {
      yield* _primary.buildChunkBatches(
        path,
        documentId: documentId,
        title: title,
        batchSize: batchSize,
      );
    } on UnimplementedError {
      yield* _fallback.buildChunkBatches(
        path,
        documentId: documentId,
        title: title,
        batchSize: batchSize,
      );
    }
  }

  Future<List<PdfChunkRecord>> buildChunks({
    required String path,
    required String documentId,
    required String title,
  }) async {
    final List<PdfChunkRecord> chunks = <PdfChunkRecord>[];
    await for (final List<PdfChunkRecord> batch in buildChunkBatches(
      path: path,
      documentId: documentId,
      title: title,
    )) {
      chunks.addAll(batch);
    }
    return chunks;
  }

  Future<String?> extractPageText(String path, int pageNumber) async {
    try {
      return await _primary.extractPageText(path, pageNumber);
    } on UnimplementedError {
      return _fallback.extractPageText(path, pageNumber);
    }
  }

  Future<PdfNativeAnnotations> readPdfAnnotations(String path) =>
      _primary.readPdfAnnotations(path);

  Future<List<String>> extractDocumentText(String path) async {
    try {
      return await _primary.extractDocumentText(path);
    } on UnimplementedError {
      return _fallback.extractDocumentText(path);
    }
  }

  Future<List<PdfSearchMatch>> searchDocument(
    String path,
    Pattern query,
  ) async {
    try {
      return await _primary.searchDocument(path, query);
    } on UnimplementedError {
      return _fallback.searchDocument(path, query);
    }
  }

  Future<void> savePdfAnnotations({
    required String path,
    required List<DocumentBookmark> bookmarks,
    required List<DocumentAnnotation> annotations,
  }) => _primary.savePdfAnnotations(
    path: path,
    bookmarks: bookmarks,
    annotations: annotations,
  );

  Future<bool> fileExists(String path) => File(path).exists();
}

class PdfNativeAnnotations {
  const PdfNativeAnnotations({
    required this.bookmarks,
    required this.highlights,
  });
  final List<DocumentBookmark> bookmarks;
  final List<DocumentAnnotation> highlights;
}
