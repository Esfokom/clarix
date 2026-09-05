import 'dart:io';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/tts_engine_worker.dart';

class TtsSegment {
  const TtsSegment({
    required this.index,
    required this.total,
    required this.pageNumber,
    required this.filePath,
  });

  final int index;
  final int total;
  final int pageNumber;
  final String filePath;
}

/// Turns a document's indexed text into synthesized speech, one chunk at a
/// time, so playback can begin before the whole document is spoken.
class TtsReaderService {
  TtsReaderService({required DocumentChunkStore chunkStore})
    // ignore: prefer_initializing_formals
    : _chunkStore = chunkStore;

  final DocumentChunkStore _chunkStore;

  Future<List<PdfChunkRecord>> loadReadableChunks(String documentId) async {
    final List<PdfChunkRecord> chunks = await _chunkStore.readChunks(
      documentId,
    );
    final List<PdfChunkRecord> sorted = List<PdfChunkRecord>.of(chunks)
      ..sort((PdfChunkRecord a, PdfChunkRecord b) {
        final int byPage = a.pageNumber.compareTo(b.pageNumber);
        if (byPage != 0) return byPage;
        return a.chunkOrder.compareTo(b.chunkOrder);
      });
    return sorted
        .where((PdfChunkRecord chunk) => chunk.text.trim().isNotEmpty)
        .toList(growable: false);
  }

  Stream<TtsSegment> synthesize({
    required List<PdfChunkRecord> chunks,
    required TtsEngineWorker engine,
    required int sid,
    required double speed,
    required Directory outputDir,
    required bool Function() isCancelled,
  }) async* {
    for (int i = 0; i < chunks.length; i++) {
      if (isCancelled()) return;
      final PdfChunkRecord chunk = chunks[i];
      final String outputPath = p.join(outputDir.path, 'segment_$i.wav');
      await engine.synthesizeToFile(
        text: chunk.text,
        sid: sid,
        speed: speed,
        outputPath: outputPath,
      );
      if (isCancelled()) return;
      yield TtsSegment(
        index: i,
        total: chunks.length,
        pageNumber: chunk.pageNumber,
        filePath: outputPath,
      );
    }
  }
}
