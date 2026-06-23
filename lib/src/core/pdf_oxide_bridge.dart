import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'models.dart';

abstract class PdfOxideBridge {
  Future<PdfDocumentMetadata> openDocument(String path);
  Future<String?> extractPageText(String path, int pageNumber);
  Future<List<String>> extractDocumentText(String path);
  Future<List<PdfSearchMatch>> searchDocument(String path, Pattern query);
  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  });
}

class FrbPdfOxideBridge implements PdfOxideBridge {
  const FrbPdfOxideBridge();

  @override
  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  }) {
    throw UnimplementedError(
      'flutter_rust_bridge bindings for pdf_oxide are not wired yet.',
    );
  }

  @override
  Future<List<String>> extractDocumentText(String path) {
    throw UnimplementedError(
      'flutter_rust_bridge bindings for pdf_oxide are not wired yet.',
    );
  }

  @override
  Future<String?> extractPageText(String path, int pageNumber) {
    throw UnimplementedError(
      'flutter_rust_bridge bindings for pdf_oxide are not wired yet.',
    );
  }

  @override
  Future<PdfDocumentMetadata> openDocument(String path) {
    throw UnimplementedError(
      'flutter_rust_bridge bindings for pdf_oxide are not wired yet.',
    );
  }

  @override
  Future<List<PdfSearchMatch>> searchDocument(String path, Pattern query) {
    throw UnimplementedError(
      'flutter_rust_bridge bindings for pdf_oxide are not wired yet.',
    );
  }
}

class PdfrxFallbackBridge implements PdfOxideBridge {
  const PdfrxFallbackBridge();

  @override
  Future<PdfDocumentMetadata> openDocument(String path) async {
    final PdfDocument document = await PdfDocument.openFile(path);
    try {
      return PdfDocumentMetadata(
        documentId: _documentIdFromPath(path),
        title: p.basename(path),
        pageCount: document.pages.length,
        isEncrypted: document.isEncrypted,
      );
    } finally {
      await document.dispose();
    }
  }

  @override
  Future<String?> extractPageText(String path, int pageNumber) async {
    final PdfDocument document = await PdfDocument.openFile(path);
    try {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        return null;
      }
      final PdfPageRawText? pageText =
          await document.pages[pageNumber - 1].loadText();
      return pageText?.fullText;
    } finally {
      await document.dispose();
    }
  }

  @override
  Future<List<String>> extractDocumentText(String path) async {
    final PdfDocument document = await PdfDocument.openFile(path);
    try {
      final List<String> pages = <String>[];
      for (final PdfPage page in document.pages) {
        final PdfPageRawText? pageText = await page.loadText();
        pages.add(pageText?.fullText ?? '');
      }
      return pages;
    } finally {
      await document.dispose();
    }
  }

  @override
  Future<List<PdfSearchMatch>> searchDocument(String path, Pattern query) async {
    final List<String> pages = await extractDocumentText(path);
    final List<PdfSearchMatch> matches = <PdfSearchMatch>[];
    final String needle = query.toString().toLowerCase();
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final String pageText = pages[pageIndex];
      if (needle.isEmpty) {
        continue;
      }
      if (pageText.toLowerCase().contains(needle)) {
        matches.add(
          PdfSearchMatch(
            pageNumber: pageIndex + 1,
            text: needle,
            bounds: Rect.zero,
          ),
        );
      }
    }
    return matches;
  }

  @override
  Future<List<PdfChunkRecord>> buildChunks(
    String path, {
    required String documentId,
    required String title,
    int maxCharsPerChunk = 1200,
  }) async {
    final PdfDocument document = await PdfDocument.openFile(path);
    try {
      final List<PdfChunkRecord> chunks = <PdfChunkRecord>[];
      int chunkOrder = 0;
      for (final PdfPage page in document.pages) {
        final PdfPageRawText? rawText = await page.loadText();
        final String normalized = _normalizeText(rawText?.fullText ?? '');
        if (normalized.isEmpty) {
          continue;
        }

        final List<String> pageChunks = _sliceText(
          normalized,
          maxCharsPerChunk: maxCharsPerChunk,
        );
        for (final String chunk in pageChunks) {
          chunks.add(
            PdfChunkRecord(
              id: '$documentId:${page.pageNumber}:$chunkOrder',
              documentId: documentId,
              title: title,
              pageNumber: page.pageNumber,
              chunkOrder: chunkOrder,
              text: chunk,
            ),
          );
          chunkOrder++;
        }
      }
      return chunks;
    } finally {
      await document.dispose();
    }
  }

  List<String> _sliceText(
    String text, {
    required int maxCharsPerChunk,
  }) {
    final List<String> output = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = min(start + maxCharsPerChunk, text.length);
      if (end < text.length) {
        final int nextBreak = text.lastIndexOf(' ', end);
        if (nextBreak > start + 200) {
          end = nextBreak;
        }
      }
      output.add(text.substring(start, end).trim());
      start = end;
    }
    return output.where((String item) => item.isNotEmpty).toList();
  }

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _documentIdFromPath(String path) {
    return p.basenameWithoutExtension(path).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}

class HybridPdfExtractionService {
  HybridPdfExtractionService({
    PdfOxideBridge? primary,
    PdfOxideBridge? fallback,
  })  : _primary = primary ?? const FrbPdfOxideBridge(),
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

  Future<List<PdfChunkRecord>> buildChunks({
    required String path,
    required String documentId,
    required String title,
  }) async {
    try {
      return await _primary.buildChunks(
        path,
        documentId: documentId,
        title: title,
      );
    } on UnimplementedError {
      return _fallback.buildChunks(
        path,
        documentId: documentId,
        title: title,
      );
    }
  }

  Future<bool> fileExists(String path) {
    return File(path).exists();
  }
}
