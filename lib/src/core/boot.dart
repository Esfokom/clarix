import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'clarix_logger.dart';
import '../features/workspace/infrastructure/local_rag_native_retriever.dart';

Future<void> bootstrapClarix() async {
  WidgetsFlutterBinding.ensureInitialized();
  clarixLog.i('Bootstrapping Clarix.');
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  // Native RAG is opportunistic. A missing/invalid desktop DLL must never
  // prevent the PDF workspace from starting; Dart lexical retrieval remains
  // available until the native runtime initializes successfully.
  await LocalRagNativeRuntime.initialize();
  clarixLog.i('Clarix bootstrap complete.');
}
