import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/tts_model_store.dart';
import 'tts_feature_state.dart';
import 'tts_notifier.dart';
import 'tts_reader_service.dart';

final ttsModelStoreProvider = Provider<TtsModelStore>((Ref ref) => TtsModelStore());

final ttsReaderServiceProvider = Provider<TtsReaderService>(
  (Ref ref) => TtsReaderService(chunkStore: ref.watch(chunkStoreProvider)),
);

final ttsNotifierProvider =
    AsyncNotifierProvider<TtsNotifier, TtsFeatureState>(TtsNotifier.new);
