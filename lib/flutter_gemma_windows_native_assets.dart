import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Best-effort workaround for `flutter_gemma` on Windows.
///
/// `flutter_gemma` stores its native DLL bundle in the Flutter Gemma cache,
/// but the desktop FFI loader resolves `StreamProxy.dll` by name. On Windows
/// debug builds that means the DLLs must live beside the executable.
///
/// This helper copies the cached DLL bundle into the running app's executable
/// directory before Flutter Gemma initializes.
Future<void> ensureFlutterGemmaWindowsNativeAssets({
  Directory? nativeAssetsRoot,
  Directory? executableDir,
}) async {
  if (!Platform.isWindows && nativeAssetsRoot == null) {
    return;
  }

  final sourceRoot = nativeAssetsRoot ?? _defaultNativeAssetsRoot();
  if (sourceRoot == null || !sourceRoot.existsSync()) {
    return;
  }

  final bundleDir = _findDllBundle(sourceRoot);
  if (bundleDir == null) {
    debugPrint(
      '[FlutterGemmaWindowsNativeAssets] No DLL bundle found under ${sourceRoot.path}',
    );
    return;
  }

  final targetDir = executableDir ?? File(Platform.resolvedExecutable).parent;
  if (!targetDir.existsSync()) {
    return;
  }

  if (p.equals(p.normalize(bundleDir.path), p.normalize(targetDir.path))) {
    return;
  }

  try {
    var copiedCount = 0;
    for (final entity in bundleDir.listSync(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.dll') {
        continue;
      }

      final targetFile = File(p.join(targetDir.path, p.basename(entity.path)));
      await targetFile.parent.create(recursive: true);
      await entity.copy(targetFile.path);
      copiedCount++;
    }

    debugPrint(
      '[FlutterGemmaWindowsNativeAssets] Copied $copiedCount DLL(s) from ${bundleDir.path} to ${targetDir.path}',
    );
  } catch (e) {
    debugPrint(
      '[FlutterGemmaWindowsNativeAssets] Failed to copy DLLs from ${bundleDir.path} to ${targetDir.path}: $e',
    );
  }
}

Directory? _defaultNativeAssetsRoot() {
  final localAppData =
      Platform.environment['LOCALAPPDATA'] ??
      '${Platform.environment['USERPROFILE'] ?? ''}\\AppData\\Local';
  if (localAppData.isEmpty) {
    return null;
  }
  final root = Directory(p.join(localAppData, 'flutter_gemma', 'native'));
  return root;
}

Directory? _findDllBundle(Directory nativeAssetsRoot) {
  for (final entity in nativeAssetsRoot.listSync(recursive: true)) {
    if (entity is File &&
        p.basename(entity.path).toLowerCase() == 'streamproxy.dll') {
      return entity.parent;
    }
  }

  return null;
}
