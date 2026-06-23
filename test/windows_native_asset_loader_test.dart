import 'dart:io';

import 'package:clarix/flutter_gemma_windows_native_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'copies flutter gemma DLL bundle into the executable directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'clarix-gemma-native-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final nativeRoot = Directory(
        p.join(root.path, 'flutter_gemma', 'native'),
      );
      final bundleDir = Directory(p.join(nativeRoot.path, 'windows_x86_64'));
      await bundleDir.create(recursive: true);

      final sourceFiles = <String, String>{
        'StreamProxy.dll': 'proxy-bytes',
        'LiteRtLm.dll': 'engine-bytes',
        'LiteRt.dll': 'runtime-bytes',
      };

      for (final entry in sourceFiles.entries) {
        await File(
          p.join(bundleDir.path, entry.key),
        ).writeAsString(entry.value);
      }

      final executableDir = Directory(p.join(root.path, 'exe'));
      await executableDir.create();
      await File(
        p.join(executableDir.path, 'StreamProxy.dll'),
      ).writeAsString('old-bytes');

      await ensureFlutterGemmaWindowsNativeAssets(
        nativeAssetsRoot: nativeRoot,
        executableDir: executableDir,
      );

      for (final entry in sourceFiles.entries) {
        expect(
          await File(p.join(executableDir.path, entry.key)).readAsString(),
          entry.value,
        );
      }
    },
  );
}
