import '../../../core/clarix_rust_runtime.dart';
import '../../../core/ffi/api.dart' as ffi;
import '../../../core/models.dart';
import 'local_rag_service.dart';
import 'local_rag_store.dart';

abstract interface class LocalRagIndexer {
  Future<void> index(String documentId, List<PdfChunkRecord> chunks);
}

abstract interface class NativeRagGateway {
  Future<String> validate({
    required String storageDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  });

  Future<String> index({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  });

  Future<List<String>?> query({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<String> chunkIds,
    required String query,
    required int limit,
  });
}

class FrbNativeRagGateway implements NativeRagGateway {
  const FrbNativeRagGateway();

  ffi.NativeRagIndexRequest _indexRequest({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  }) => ffi.NativeRagIndexRequest(
    storageDirectory: storageDirectory,
    modelCacheDirectory: modelCacheDirectory,
    documentFingerprint: documentFingerprint,
    chunks: chunks
        .map(
          (PdfChunkRecord chunk) =>
              ffi.NativeRagChunk(id: chunk.id, text: chunk.text),
        )
        .toList(growable: false),
  );

  @override
  Future<String> validate({
    required String storageDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  }) async => (await ffi.localRagValidate(
    request: _indexRequest(
      storageDirectory: storageDirectory,
      modelCacheDirectory: '',
      documentFingerprint: documentFingerprint,
      chunks: chunks,
    ),
  )).status;

  @override
  Future<String> index({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<PdfChunkRecord> chunks,
  }) async => (await ffi.localRagIndex(
    request: _indexRequest(
      storageDirectory: storageDirectory,
      modelCacheDirectory: modelCacheDirectory,
      documentFingerprint: documentFingerprint,
      chunks: chunks,
    ),
  )).status;

  @override
  Future<List<String>?> query({
    required String storageDirectory,
    required String modelCacheDirectory,
    required String documentFingerprint,
    required List<String> chunkIds,
    required String query,
    required int limit,
  }) async {
    final ffi.NativeRagQueryResponse response = await ffi.localRagQuery(
      request: ffi.NativeRagQueryRequest(
        storageDirectory: storageDirectory,
        modelCacheDirectory: modelCacheDirectory,
        documentFingerprint: documentFingerprint,
        chunkIds: chunkIds,
        query: query,
        limit: BigInt.from(limit),
      ),
    );
    if (response.status != 'ready') return null;
    return response.results
        .map((ffi.NativeRagQueryResult item) => item.chunkId)
        .toList(growable: false);
  }
}

class NativeLocalRagRetriever implements LocalRagRetriever, LocalRagIndexer {
  NativeLocalRagRetriever({
    required this._store,
    required this._readChunks,
    NativeRagGateway? gateway,
    bool Function()? isNativeAvailable,
    Future<bool> Function()? ensureNativeInitialized,
  }) : _gateway = gateway ?? const FrbNativeRagGateway(),
       _isNativeAvailable =
           isNativeAvailable ?? (() => ClarixRustRuntime.isAvailable),
       _ensureNativeInitialized =
           ensureNativeInitialized ?? ClarixRustRuntime.ensureInitialized;

  final LocalRagStore _store;
  final PdfChunkReader _readChunks;
  final NativeRagGateway _gateway;
  final bool Function() _isNativeAvailable;
  final Future<bool> Function() _ensureNativeInitialized;
  final Map<String, LocalRagIndexStatus> _statuses =
      <String, LocalRagIndexStatus>{};
  final Map<String, Future<LocalRagIndexStatus>> _inFlight =
      <String, Future<LocalRagIndexStatus>>{};

  @override
  LocalRagIndexStatus statusFor(String documentId) => _isNativeAvailable()
      ? (_statuses[documentId] ?? LocalRagIndexStatus.idle)
      : LocalRagIndexStatus.unavailable;

  Future<LocalRagIndexStatus> ensureReady(
    String documentId,
    List<PdfChunkRecord> chunks,
  ) {
    if (chunks.isEmpty) {
      _statuses[documentId] = LocalRagIndexStatus.idle;
      return Future<LocalRagIndexStatus>.value(LocalRagIndexStatus.idle);
    }
    final Future<LocalRagIndexStatus>? current = _inFlight[documentId];
    if (current != null) return current;
    final Future<LocalRagIndexStatus> task = _prepare(documentId, chunks);
    _inFlight[documentId] = task;
    return task.whenComplete(() => _inFlight.remove(documentId));
  }

  Future<LocalRagIndexStatus> _prepare(
    String documentId,
    List<PdfChunkRecord> chunks,
  ) async {
    if (!_isNativeAvailable() && !await _ensureNativeInitialized()) {
      return _statuses[documentId] = LocalRagIndexStatus.unavailable;
    }
    _statuses[documentId] = LocalRagIndexStatus.indexing;
    try {
      final storage = await _store.directory();
      final String validated = await _gateway.validate(
        storageDirectory: storage.path,
        documentFingerprint: documentId,
        chunks: chunks,
      );
      if (validated == 'ready') {
        return _statuses[documentId] = LocalRagIndexStatus.ready;
      }
      if (validated != 'idle') {
        return _statuses[documentId] = LocalRagIndexStatus.failed;
      }
      final modelCache = await _store.modelCacheDirectory();
      final String indexed = await _gateway.index(
        storageDirectory: storage.path,
        modelCacheDirectory: modelCache.path,
        documentFingerprint: documentId,
        chunks: chunks,
      );
      return _statuses[documentId] = indexed == 'ready'
          ? LocalRagIndexStatus.ready
          : LocalRagIndexStatus.failed;
    } catch (_) {
      return _statuses[documentId] = LocalRagIndexStatus.failed;
    }
  }

  @override
  Future<void> index(String documentId, List<PdfChunkRecord> chunks) async {
    await ensureReady(documentId, chunks);
  }

  @override
  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) async {
    if (statusFor(documentId) != LocalRagIndexStatus.ready) return null;
    try {
      final List<PdfChunkRecord> chunks = await _readChunks(documentId);
      final storage = await _store.directory();
      final modelCache = await _store.modelCacheDirectory();
      final List<String>? ids = await _gateway.query(
        storageDirectory: storage.path,
        modelCacheDirectory: modelCache.path,
        documentFingerprint: documentId,
        chunkIds: chunks
            .map((PdfChunkRecord item) => item.id)
            .toList(growable: false),
        query: query,
        limit: limit,
      );
      if (ids == null) {
        _statuses[documentId] = LocalRagIndexStatus.failed;
        return null;
      }
      final Map<String, PdfChunkRecord> byId = <String, PdfChunkRecord>{
        for (final PdfChunkRecord chunk in chunks) chunk.id: chunk,
      };
      return ids
          .map((String id) => byId[id])
          .whereType<PdfChunkRecord>()
          .toList(growable: false);
    } catch (_) {
      _statuses[documentId] = LocalRagIndexStatus.failed;
      return null;
    }
  }
}
