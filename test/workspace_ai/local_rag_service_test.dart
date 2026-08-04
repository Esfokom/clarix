import 'dart:io';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/infrastructure/local_rag_native_retriever.dart';
import 'package:clarix/src/features/workspace/infrastructure/local_rag_service.dart';
import 'package:clarix/src/features/workspace/infrastructure/local_rag_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String documentId = 'document-1';
  final List<PdfChunkRecord> chunks = <PdfChunkRecord>[
    _chunk(id: 'first', order: 2, text: 'Alpha contract terms.'),
    _chunk(id: 'second', order: 1, text: 'alpha alpha obligations.'),
    _chunk(id: 'third', order: 0, text: 'Unrelated content.'),
  ];

  test('uses ranked native results when its index is ready', () async {
    final LocalRagService service = LocalRagService(
      readChunks: (_) async => chunks,
      nativeRetriever: _FakeRetriever(
        status: LocalRagIndexStatus.ready,
        result: <PdfChunkRecord>[chunks[2], chunks[0]],
      ),
    );

    final List<PdfChunkRecord> result = await service.retrieve(
      documentId,
      'alpha',
    );

    expect(result.map((PdfChunkRecord chunk) => chunk.id), <String>[
      'third',
      'first',
    ]);
  });

  test('removes duplicate native chunks before returning context', () async {
    final LocalRagService service = LocalRagService(
      readChunks: (_) async => chunks,
      nativeRetriever: _FakeRetriever(
        status: LocalRagIndexStatus.ready,
        result: <PdfChunkRecord>[chunks[0], chunks[0], chunks[1]],
      ),
    );

    final List<PdfChunkRecord> result = await service.retrieve(
      documentId,
      'alpha',
    );

    expect(result.map((PdfChunkRecord chunk) => chunk.id), <String>[
      'first',
      'second',
    ]);
  });

  test(
    'uses case-insensitive lexical ranking with chunk-order tie breaks',
    () async {
      final LocalRagService service = LocalRagService(
        readChunks: (_) async => chunks,
        nativeRetriever: _FakeRetriever(
          status: LocalRagIndexStatus.unavailable,
        ),
      );

      final List<PdfChunkRecord> result = await service.retrieve(
        documentId,
        'ALPHA',
      );

      expect(result.map((PdfChunkRecord chunk) => chunk.id), <String>[
        'second',
        'first',
      ]);
    },
  );

  test('returns no lexical results for a blank query', () async {
    final LocalRagService service = LocalRagService(
      readChunks: (_) async => chunks,
    );

    expect(await service.retrieve(documentId, '  \n  '), isEmpty);
  });

  test(
    'returns no results for a blank query when native retrieval is ready',
    () async {
      final LocalRagService service = LocalRagService(
        readChunks: (_) async => chunks,
        nativeRetriever: _FakeRetriever(
          status: LocalRagIndexStatus.ready,
          result: <PdfChunkRecord>[chunks[0]],
        ),
      );

      expect(await service.retrieve(documentId, '  \n  '), isEmpty);
    },
  );

  test(
    'falls back to lexical results when ready native retrieval throws',
    () async {
      final LocalRagService service = LocalRagService(
        readChunks: (_) async => chunks,
        nativeRetriever: _ThrowingRetriever(),
      );

      final List<PdfChunkRecord> result = await service.retrieve(
        documentId,
        'alpha',
      );

      expect(result.map((PdfChunkRecord chunk) => chunk.id), <String>[
        'second',
        'first',
      ]);
    },
  );

  test(
    'uses lexical retrieval when the native runtime is unavailable',
    () async {
      final LocalRagService service = LocalRagService(
        readChunks: (_) async => chunks,
        nativeRetriever: NativeLocalRagRetriever(
          store: LocalRagStore(
            directoryProvider: () async => Directory.systemTemp,
          ),
          readChunks: (_) async => const <PdfChunkRecord>[],
          isNativeAvailable: () => false,
          ensureNativeInitialized: () async => false,
        ),
      );

      final List<PdfChunkRecord> result = await service.retrieve(
        documentId,
        'alpha',
      );

      expect(result.map((PdfChunkRecord chunk) => chunk.id), <String>[
        'second',
        'first',
      ]);
    },
  );

  test(
    'persists a versioned manifest with native index compatibility data',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp('rag');
      addTearDown(() => directory.delete(recursive: true));
      final LocalRagStore store = LocalRagStore(
        directoryProvider: () async => directory,
      );
      const LocalRagManifest manifest = LocalRagManifest(
        documentFingerprint: 'fingerprint',
        modelId: 'all-MiniLM-L6-v2',
        vectorDimensions: 384,
        chunkIds: <String>['first', 'second'],
      );

      await store.saveManifest(documentId, manifest);

      expect(await store.readManifest(documentId), manifest);
      expect((await store.readManifestJson(documentId))?['version'], 1);
    },
  );
}

PdfChunkRecord _chunk({
  required String id,
  required int order,
  required String text,
}) => PdfChunkRecord(
  id: id,
  documentId: 'document-1',
  title: 'contract.pdf',
  pageNumber: 1,
  chunkOrder: order,
  text: text,
);

class _FakeRetriever implements LocalRagRetriever {
  _FakeRetriever({required this.status, this.result});

  final LocalRagIndexStatus status;

  @override
  LocalRagIndexStatus statusFor(String documentId) => status;
  final List<PdfChunkRecord>? result;

  @override
  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) async => result;
}

class _ThrowingRetriever implements LocalRagRetriever {
  @override
  LocalRagIndexStatus statusFor(String documentId) => LocalRagIndexStatus.ready;

  @override
  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) => Future<List<PdfChunkRecord>?>.error(StateError('native unavailable'));
}
