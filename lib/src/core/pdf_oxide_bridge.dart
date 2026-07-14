import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'models.dart';

abstract class PdfOxideBridge {
  const PdfOxideBridge();

  Future<PdfDocumentMetadata> openDocument(String path);
  Future<String?> extractPageText(String path, int pageNumber);
  Future<List<String>> extractDocumentText(String path);
  Future<List<PdfSearchMatch>> searchDocument(String path, Pattern query);
  Stream<List<PdfChunkRecord>> buildChunkBatches(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
    int batchSize = 32,
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

  Never _unavailable() {
    throw UnimplementedError(
      'Generate flutter_rust_bridge bindings from crate::api to enable pdf_oxide.',
    );
  }

  @override
  Stream<List<PdfChunkRecord>> buildChunkBatches(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
    int batchSize = 32,
  }) async* {
    _unavailable();
  }

  @override
  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  }) async => _unavailable();

  @override
  Future<List<String>> extractDocumentText(String path) async => _unavailable();

  @override
  Future<String?> extractPageText(String path, int pageNumber) async =>
      _unavailable();

  @override
  Future<PdfDocumentMetadata> openDocument(String path) async => _unavailable();

  @override
  Future<List<PdfSearchMatch>> searchDocument(
    String path,
    Pattern query,
  ) async => _unavailable();
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

  Future<bool> fileExists(String path) => File(path).exists();
}
