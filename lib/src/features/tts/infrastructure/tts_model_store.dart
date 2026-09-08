import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/tts_models.dart';

/// Downloads, extracts, and tracks on-disk installation of [TtsModelSpec]
/// voice packs published by the sherpa-onnx project.
class TtsModelStore {
  TtsModelStore({Future<Directory> Function()? directoryProvider, Dio? client})
    : _directoryProvider = directoryProvider ?? _defaultModelsDirectory,
      _client = client ?? Dio();

  final Future<Directory> Function() _directoryProvider;
  final Dio _client;

  static Future<Directory> _defaultModelsDirectory() async {
    Directory root;
    try {
      root = await getApplicationSupportDirectory();
    } catch (_) {
      root = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}clarix');
    }
    final Directory dir = Directory(p.join(root.path, 'clarix', 'tts_models'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelsRoot() => _directoryProvider();

  Future<String> _installDir(TtsModelSpec spec) async {
    final Directory root = await modelsRoot();
    return p.join(root.path, spec.id);
  }

  Future<bool> isInstalled(TtsModelSpec spec) async {
    final String dir = await _installDir(spec);
    final bool model = await File(p.join(dir, spec.modelFileName)).exists();
    final bool voices = spec.voicesFileName == null
        ? true
        : await File(p.join(dir, spec.voicesFileName!)).exists();
    final bool tokens = await File(p.join(dir, spec.tokensFileName)).exists();
    final bool dataDir = await Directory(p.join(dir, spec.dataDirName)).exists();
    return model && voices && tokens && dataDir;
  }

  /// Absolute paths to the files sherpa-onnx expects for [spec]. Only valid
  /// once [isInstalled] returns true.
  Future<TtsInstalledModelPaths> paths(TtsModelSpec spec) async {
    final String dir = await _installDir(spec);
    return TtsInstalledModelPaths(
      model: p.join(dir, spec.modelFileName),
      voices: spec.voicesFileName == null ? null : p.join(dir, spec.voicesFileName!),
      tokens: p.join(dir, spec.tokensFileName),
      dataDir: p.join(dir, spec.dataDirName),
    );
  }

  /// Downloads and extracts [spec]'s archive, reporting progress in `[0, 1]`
  /// for the download phase. Extraction has no meaningful sub-progress and is
  /// reported as a single indeterminate step via [onExtracting].
  Future<void> install(
    TtsModelSpec spec, {
    void Function(double progress)? onDownloadProgress,
    void Function()? onExtracting,
  }) async {
    final Directory root = await modelsRoot();
    final File archiveFile = File(p.join(root.path, '${spec.id}.tar.bz2'));
    try {
      await _client.download(
        spec.downloadUrl,
        archiveFile.path,
        onReceiveProgress: (int received, int total) {
          if (total <= 0 || onDownloadProgress == null) return;
          onDownloadProgress(received / total);
        },
      );

      onExtracting?.call();
      final List<int> compressed = await archiveFile.readAsBytes();
      final List<int> tarBytes = BZip2Decoder().decodeBytes(compressed);
      final Archive archive = TarDecoder().decodeBytes(tarBytes);

      for (final ArchiveFile entry in archive) {
        if (!entry.isFile) continue;
        final File output = File(p.join(root.path, entry.name));
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content as List<int>, flush: true);
      }
    } finally {
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
    }
  }

  Future<void> delete(TtsModelSpec spec) async {
    final Directory dir = Directory(await _installDir(spec));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

class TtsInstalledModelPaths {
  const TtsInstalledModelPaths({
    required this.model,
    this.voices,
    required this.tokens,
    required this.dataDir,
  });

  final String model;
  final String? voices;
  final String tokens;
  final String dataDir;
}
