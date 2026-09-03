import 'package:clarix/src/features/ai/infrastructure/voice_input_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('persists and clears the selected microphone device ID', () async {
    final VoiceInputSettingsStore store = VoiceInputSettingsStore(
      SharedPreferencesAsync(),
    );

    await store.saveSelectedDeviceId('usb-mic');
    expect(await store.readSelectedDeviceId(), 'usb-mic');

    await store.saveSelectedDeviceId(null);
    expect(await store.readSelectedDeviceId(), isNull);
  });
}
