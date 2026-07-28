import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'clarix_logger.dart';
import 'clarix_rust_runtime.dart';

Future<void> bootstrapClarix() async {
  WidgetsFlutterBinding.ensureInitialized();
  clarixLog.i('Bootstrapping Clarix.');
  await ClarixRustRuntime.ensureInitialized();
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  clarixLog.i('Clarix bootstrap complete.');
}
