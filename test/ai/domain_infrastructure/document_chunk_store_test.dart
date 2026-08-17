import 'dart:io';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/infrastructure/document_chunk_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'detects persisted chunks without reading their full contents',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'clarix-chunks',
      );
      addTearDown(() => root.delete(recursive: true));
      final DocumentChunkStore store = DocumentChunkStore(
        directoryProvider: () async => root,
      );

      expect(await store.hasChunks('document-1'), isFalse);

      await store.saveChunks('document-1', const <PdfChunkRecord>[
        PdfChunkRecord(
          id: 'one',
          documentId: 'document-1',
          title: 'document.pdf',
          pageNumber: 1,
          chunkOrder: 0,
          text: 'Cached text.',
        ),
      ]);

      expect(await store.hasChunks('document-1'), isTrue);
    },
  );
}
