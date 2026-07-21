import '../../../core/ffi/api.dart' as ffi;
import '../../../core/ffi/frb_generated.dart' as frb;
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
  }) : _store = store,
       _readChunks = readChunks,
       _isNativeAvailable =
           isNativeAvailable ?? (() => LocalRagNativeRuntime.isAvailable);

  final LocalRagStore _store;
  final PdfChunkReader _readChunks;
  final bool Function() _isNativeAvailable;
  LocalRagIndexStatus _status = LocalRagIndexStatus.idle;

  @override
  LocalRagIndexStatus get status =>
      _isNativeAvailable() ? _status : LocalRagIndexStatus.unavailable;

  @override
  Future<void> index(String documentId, List<PdfChunkRecord> chunks) async {
    if (!_isNativeAvailable()) {
      _status = LocalRagIndexStatus.unavailable;
      return;
    }
    if (chunks.isEmpty) {
      _status = LocalRagIndexStatus.idle;
      return;
    }
    _status = LocalRagIndexStatus.indexing;
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
      _status = response.status == 'ready'
          ? LocalRagIndexStatus.ready
          : LocalRagIndexStatus.failed;
    } catch (_) {
      _status = LocalRagIndexStatus.failed;
    }
  }

  @override
  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) async {
    if (status != LocalRagIndexStatus.ready) {
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
        _status = LocalRagIndexStatus.failed;
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
      _status = LocalRagIndexStatus.failed;
      return null;
    }
  }
}

class LocalRagNativeRuntime {
  LocalRagNativeRuntime._();

  static bool _available = false;
  static bool get isAvailable => _available;

  static Future<void> initialize() async {
    try {
      await frb.RustLib.init();
      _available = true;
    } catch (_) {
      _available = false;
    }
  }
}
