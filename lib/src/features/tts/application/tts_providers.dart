import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/tts_model_store.dart';
import '../infrastructure/tts_preferences_store.dart';
import 'tts_feature_state.dart';
import 'tts_notifier.dart';

final ttsModelStoreProvider = Provider<TtsModelStore>((Ref ref) => TtsModelStore());

final ttsSharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final ttsPreferencesStoreProvider = Provider<TtsPreferencesStore>(
  (Ref ref) => TtsPreferencesStore(ref.watch(ttsSharedPreferencesProvider)),
);

final ttsNotifierProvider =
    AsyncNotifierProvider<TtsNotifier, TtsFeatureState>(TtsNotifier.new);
