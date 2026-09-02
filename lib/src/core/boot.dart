import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'clarix_logger.dart';
import 'clarix_rust_runtime.dart';

Future<void> bootstrapClarix() async {
  WidgetsFlutterBinding.ensureInitialized();
  clarixLog.i('Bootstrapping Clarix.');
  await FlutterGemma.initialize(
    inferenceEngines: const <LiteRtLmEngine>[LiteRtLmEngine()],
  );
  await ClarixRustRuntime.ensureInitialized();
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  clarixLog.i('Clarix bootstrap complete.');
}
