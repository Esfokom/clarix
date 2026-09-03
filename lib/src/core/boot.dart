import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'clarix_logger.dart';
import 'clarix_rust_runtime.dart';
import '../features/ai/domain/local_model_profile.dart';
import '../features/ai/infrastructure/flutter_gemma_local_model_gateway.dart';
import '../features/ai/infrastructure/local_model_store.dart';

Future<void> bootstrapClarix() async {
  WidgetsFlutterBinding.ensureInitialized();
  clarixLog.i('Bootstrapping Clarix.');
  await FlutterGemma.initialize(
    inferenceEngines: const <LiteRtLmEngine>[LiteRtLmEngine()],
  );
  await _restoreInstalledLocalModels();
  await ClarixRustRuntime.ensureInitialized();
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  clarixLog.i('Clarix bootstrap complete.');
}

Future<void> _restoreInstalledLocalModels() async {
  final LocalModelStore store = LocalModelStore(SharedPreferencesAsync());
  final FlutterGemmaLocalModelGateway gateway = FlutterGemmaLocalModelGateway();
  final List<LocalModelProfile> installed = await store.reconcile(
    supportedProfiles: <LocalModelProfile>[LocalModelProfile.gemma4E2b()],
    isInstalled: gateway.isInstalled,
  );
  clarixLog.i('Restored ${installed.length} installed local model(s).');
}
