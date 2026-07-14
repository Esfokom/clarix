import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
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
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: [LiteRtEmbeddingBackend()],
    vectorStore: QdrantVectorStore(),
    maxDownloadRetries: 10,
  );
  clarixLog.i('Clarix bootstrap complete.');
}
