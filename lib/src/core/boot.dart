import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import '../../flutter_gemma_windows_native_assets.dart';
import 'clarix_logger.dart';

Future<void> bootstrapClarix() async {
  WidgetsFlutterBinding.ensureInitialized();
  clarixLog.i('Bootstrapping Clarix.');
  await ensureFlutterGemmaWindowsNativeAssets();
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  await FlutterGemma.initialize(
    maxDownloadRetries: 10,
    huggingFaceToken: "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",
  );
  clarixLog.i('Clarix bootstrap complete.');
}
