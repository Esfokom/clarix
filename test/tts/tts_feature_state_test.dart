import 'package:clarix/src/features/tts/application/tts_feature_state.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state defaults to kittenSherpa with no model or voice selected', () {
    final TtsFeatureState state = TtsFeatureState.initial();
    expect(state.activeEngine, TtsEngineKind.kittenSherpa);
    expect(state.activeModelId, isNull);
    expect(state.systemVoice, isNull);
    expect(state.availableSystemVoices, isEmpty);
  });

  test('copyWith updates the new fields independently', () {
    final TtsFeatureState state = TtsFeatureState.initial().copyWith(
      activeEngine: TtsEngineKind.system,
      activeModelId: 'vits-piper-en_US-amy-low-int8',
      systemVoice: const SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
      availableSystemVoices: const <SystemTtsVoice>[
        SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
      ],
    );
    expect(state.activeEngine, TtsEngineKind.system);
    expect(state.activeModelId, 'vits-piper-en_US-amy-low-int8');
    expect(state.systemVoice, const SystemTtsVoice(name: 'Karen', locale: 'en-AU'));
    expect(state.availableSystemVoices, hasLength(1));
  });
}
