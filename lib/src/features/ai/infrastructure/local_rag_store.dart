import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LocalRagIndexStatus { idle, indexing, ready, unavailable, failed }

class LocalRagManifest {
  const LocalRagManifest({
    this.version = currentVersion,
    required this.documentFingerprint,
    required this.modelId,
    required this.vectorDimensions,
    required this.chunkIds,
  });

  static const int currentVersion = 1;

  final int version;
  final String documentFingerprint;
  final String modelId;
  final int vectorDimensions;
  final List<String> chunkIds;

  Map<String, Object> toJson() => <String, Object>{
    'version': version,
    'documentFingerprint': documentFingerprint,
    'modelId': modelId,
    'vectorDimensions': vectorDimensions,
    'chunkIds': chunkIds,
  };

  factory LocalRagManifest.fromJson(Map<String, dynamic> json) =>
      LocalRagManifest(
        version: json['version'] as int,
        documentFingerprint: json['documentFingerprint'] as String,
        modelId: json['modelId'] as String,
        vectorDimensions: json['vectorDimensions'] as int,
        chunkIds: (json['chunkIds'] as List<dynamic>).cast<String>().toList(
          growable: false,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is LocalRagManifest &&
      version == other.version &&
      documentFingerprint == other.documentFingerprint &&
      modelId == other.modelId &&
      vectorDimensions == other.vectorDimensions &&
      _sameChunkIds(other.chunkIds);

  bool _sameChunkIds(List<String> other) =>
      chunkIds.length == other.length &&
      chunkIds.indexed.every((entry) => entry.$2 == other[entry.$1]);

  @override
  int get hashCode => Object.hash(
    version,
    documentFingerprint,
    modelId,
    vectorDimensions,
    Object.hashAll(chunkIds),
  );
}

class LocalRagStore {
  LocalRagStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final Future<Directory> Function() _directoryProvider;

  static Future<Directory> _defaultDirectory() async {
    Directory root;
    try {
      root = await getApplicationSupportDirectory();
    } catch (_) {
      root = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}clarix',
      );
    }
    final Directory directory = Directory(p.join(root.path, 'clarix', 'rag'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> saveManifest(
    String documentId,
    LocalRagManifest manifest,
  ) async {
    final File target = await _manifestFile(documentId);
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(manifest.toJson()));
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }

  /// The native index and its downloaded embedding assets live below the same
  /// app-support root as the Dart manifest. The directories are created before
  /// a background task starts so Rust receives explicit, stable paths.
  Future<Directory> directory() => _directoryProvider();

  Future<Directory> modelCacheDirectory() async {
    final Directory root = await directory();
    final Directory cache = Directory(p.join(root.path, 'models'));
    await cache.create(recursive: true);
    return cache;
  }

  Future<LocalRagManifest?> readManifest(String documentId) async {
    final Map<String, dynamic>? json = await readManifestJson(documentId);
    return json == null ? null : LocalRagManifest.fromJson(json);
  }

  Future<Map<String, dynamic>?> readManifestJson(String documentId) async {
    final File target = await _manifestFile(documentId);
    if (!await target.exists()) {
      return null;
    }
    return jsonDecode(await target.readAsString()) as Map<String, dynamic>;
  }

  Future<void> clearCache() async {
    final Directory directory = await _directoryProvider();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<File> _manifestFile(String documentId) async {
    final Directory directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File(p.join(directory.path, '$documentId.manifest.json'));
  }
}
