import '../../../core/clarix_rust_runtime.dart';
import '../../../core/ffi/api.dart' as ffi;
import '../../../core/models.dart';
import 'local_rag_service.dart';
import 'local_rag_store.dart';

abstract interface class LocalRagIndexer {
  Future<void> index(String documentId, List<PdfChunkRecord> chunks);
}

/// Flutter-facing adapter for the generated FRB local-RAG API.
///
/// Every native failure is represented as an unavailable/failed status and a
/// `null` retrieval result, allowing [LocalRagService] to use lexical search.
class NativeLocalRagRetriever implements LocalRagRetriever, LocalRagIndexer {
  NativeLocalRagRetriever({
    required LocalRagStore store,
    required PdfChunkReader readChunks,
    bool Function()? isNativeAvailable,
    Future<bool> Function()? ensureNativeInitialized,
  }) : _store = store,
       _readChunks = readChunks,
       _isNativeAvailable =
           isNativeAvailable ?? (() => ClarixRustRuntime.isAvailable),
       _ensureNativeInitialized =
           ensureNativeInitialized ?? ClarixRustRuntime.ensureInitialized;

  final LocalRagStore _store;
  final PdfChunkReader _readChunks;
  final bool Function() _isNativeAvailable;
  final Future<bool> Function() _ensureNativeInitialized;
  final Map<String, LocalRagIndexStatus> _statuses =
      <String, LocalRagIndexStatus>{};

  @override
  LocalRagIndexStatus statusFor(String documentId) => _isNativeAvailable()
      ? (_statuses[documentId] ?? LocalRagIndexStatus.idle)
      : LocalRagIndexStatus.unavailable;

  @override
  Future<void> index(String documentId, List<PdfChunkRecord> chunks) async {
    if (!_isNativeAvailable() && !await _ensureNativeInitialized()) {
      _statuses[documentId] = LocalRagIndexStatus.unavailable;
      return;
    }
    if (chunks.isEmpty) {
      _statuses[documentId] = LocalRagIndexStatus.idle;
      return;
    }
    _statuses[documentId] = LocalRagIndexStatus.indexing;
    try {
      final storage = await _store.directory();
      final modelCache = await _store.modelCacheDirectory();
      final ffi.NativeRagIndexResponse response = await ffi.localRagIndex(
        request: ffi.NativeRagIndexRequest(
          storageDirectory: storage.path,
          modelCacheDirectory: modelCache.path,
          documentFingerprint: documentId,
          chunks: chunks
              .map(
                (PdfChunkRecord chunk) =>
                    ffi.NativeRagChunk(id: chunk.id, text: chunk.text),
              )
              .toList(growable: false),
        ),
      );
      _statuses[documentId] = response.status == 'ready'
          ? LocalRagIndexStatus.ready
          : LocalRagIndexStatus.failed;
    } catch (_) {
      _statuses[documentId] = LocalRagIndexStatus.failed;
    }
  }

  @override
  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) async {
    if (statusFor(documentId) != LocalRagIndexStatus.ready) {
      return null;
    }
    try {
      final List<PdfChunkRecord> chunks = await _readChunks(documentId);
      final storage = await _store.directory();
      final modelCache = await _store.modelCacheDirectory();
      final ffi.NativeRagQueryResponse response = await ffi.localRagQuery(
        request: ffi.NativeRagQueryRequest(
          storageDirectory: storage.path,
          modelCacheDirectory: modelCache.path,
          documentFingerprint: documentId,
          chunkIds: chunks
              .map((PdfChunkRecord chunk) => chunk.id)
              .toList(growable: false),
          query: query,
          limit: BigInt.from(limit),
        ),
      );
      if (response.status != 'ready') {
        _statuses[documentId] = LocalRagIndexStatus.failed;
        return null;
      }
      final Map<String, PdfChunkRecord> byId = <String, PdfChunkRecord>{
        for (final PdfChunkRecord chunk in chunks) chunk.id: chunk,
      };
      return response.results
          .map((ffi.NativeRagQueryResult result) => byId[result.chunkId])
          .whereType<PdfChunkRecord>()
          .toList(growable: false);
    } catch (_) {
      _statuses[documentId] = LocalRagIndexStatus.failed;
      return null;
    }
  }
}
