import 'dart:io';

import 'package:path/path.dart' as p;

import 'clarix_logger.dart';
import 'models.dart';

class LocalGemmaModelStore {
  const LocalGemmaModelStore();

  String? get storageDirectoryPath {
    if (Platform.isWindows) {
      final String? local = Platform.environment['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty && p.isAbsolute(local)) {
        return p.join(local, 'clarix_legacy_models');
      }

      final String? userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null &&
          userProfile.isNotEmpty &&
          p.isAbsolute(userProfile)) {
        return p.join(userProfile, 'AppData', 'Local', 'clarix_legacy_models');
      }
      return null;
    }

    return null;
  }

  String? pathForFilename(String filename) {
    final String? storagePath = storageDirectoryPath;
    if (storagePath == null || filename.isEmpty) {
      return null;
    }
    return p.join(storagePath, filename);
  }

  String? installedPathSync(ModelCatalogItem item) {
    final String? path = pathForFilename(item.filename);
    if (path == null) {
      return null;
    }
    if (File(path).existsSync()) {
      clarixLog.i('Local model detected: ${item.id} at $path');
      return path;
    }
    return null;
  }

  int fileSizeSync(String path) {
    try {
      return File(path).lengthSync();
    } catch (error, stackTrace) {
      clarixLog.w(
        'Unable to read local model size at $path',
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  Future<void> reveal(String path) async {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    final String target = type == FileSystemEntityType.directory
        ? path
        : p.dirname(path);

    clarixLog.i('Opening model location: $path');
    if (Platform.isWindows) {
      if (type == FileSystemEntityType.file) {
        await Process.start('explorer.exe', <String>['/select,$path']);
      } else {
        await Process.start('explorer.exe', <String>[target]);
      }
      return;
    }

    if (Platform.isMacOS) {
      await Process.start('open', <String>[target]);
      return;
    }

    if (Platform.isLinux) {
      await Process.start('xdg-open', <String>[target]);
    }
  }
}
