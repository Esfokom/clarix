import 'dart:io';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/infrastructure/local_rag_native_retriever.dart';
import 'package:clarix/src/features/ai/infrastructure/local_rag_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String documentId = 'document-1';
  final List<PdfChunkRecord> chunks = <PdfChunkRecord>[
    const PdfChunkRecord(
      id: 'chunk-1',
      documentId: documentId,
      title: 'contract.pdf',
      pageNumber: 1,
      chunkOrder: 0,
      text: 'Termination requires notice.',
    ),
  ];

  test('restores a validated cached index without rebuilding it', () async {
    final _FakeGateway gateway = _FakeGateway(validateStatus: 'ready');
    final NativeLocalRagRetriever retriever = _retriever(gateway);

    final LocalRagIndexStatus status = await retriever.ensureReady(
      documentId,
      chunks,
    );

    expect(status, LocalRagIndexStatus.ready);
    expect(gateway.validateCalls, 1);
    expect(gateway.indexCalls, 0);
  });

  test(
    'coalesces concurrent cache misses into one native index build',
    () async {
      final _FakeGateway gateway = _FakeGateway(validateStatus: 'idle');
      final NativeLocalRagRetriever retriever = _retriever(gateway);

      final List<LocalRagIndexStatus> statuses =
          await Future.wait(<Future<LocalRagIndexStatus>>[
            retriever.ensureReady(documentId, chunks),
            retriever.ensureReady(documentId, chunks),
          ]);

      expect(statuses, <LocalRagIndexStatus>[
        LocalRagIndexStatus.ready,
        LocalRagIndexStatus.ready,
      ]);
      expect(gateway.validateCalls, 1);
      expect(gateway.indexCalls, 1);
    },
  );
}

NativeLocalRagRetriever _retriever(_FakeGateway gateway) =>
    NativeLocalRagRetriever(
      store: LocalRagStore(directoryProvider: () async => Directory.systemTemp),
      readChunks: (_) async => const <PdfChunkRecord>[],
      gateway: gateway,
      isNativeAvailable: () => true,
    );

class _FakeGateway implements NativeRagGateway {
  _FakeGateway({required this.validateStatus});

  final String validateStatus;
  int validateCalls = 0;
  int indexCalls = 0;

  @override
  Future<String> index({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  }) async {
    indexCalls++;
    return 'ready';
  }

  @override
  Future<String> validate({
    required String storageDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  }) async {
    validateCalls++;
    return validateStatus;
  }

  @override
  Future<List<String>?> query({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<String> chunkIds,
    required String query,
    required int limit,
  }) => throw UnimplementedError();
}
