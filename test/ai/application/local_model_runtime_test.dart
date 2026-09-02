import 'package:clarix/src/features/ai/application/local_model_runtime.dart';
import 'package:clarix/src/features/ai/domain/ai_models.dart';
import 'package:clarix/src/features/ai/domain/local_model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final LocalModelProfile profile = LocalModelProfile.gemma4(
    id: 'local-gemma-4-e2b',
    label: 'Gemma 4 E2B',
    modelFileName: 'gemma-4-E2B-it.litertlm',
  );

  test('streams a grounded prompt through the selected local model', () async {
    final _FakeGateway gateway = _FakeGateway();
    final LocalModelRuntime runtime = LocalModelRuntime(gateway: gateway);
    final List<String> tokens = <String>[];

    await runtime.sendPrompt(
      profile: profile,
      prompt: 'What does the report conclude?',
      documentSnippets: const <CitationSnippet>[
        CitationSnippet(
          documentId: 'document',
          label: 'Report',
          pageNumber: 3,
          snippet: 'The conclusion is positive.',
        ),
      ],
      onToken: tokens.add,
    );

    expect(tokens, <String>['Local ', 'answer']);
    expect(gateway.profile, profile);
    expect(gateway.prompt, 'What does the report conclude?');
    expect(gateway.systemInstruction, contains('The conclusion is positive.'));
  });

  test(
    'downloads the selected Gemma profile through the local gateway',
    () async {
      final _FakeGateway gateway = _FakeGateway();
      final LocalModelRuntime runtime = LocalModelRuntime(gateway: gateway);

      await runtime.download(profile);

      expect(gateway.downloadedProfile, profile);
    },
  );
}

class _FakeGateway implements LocalModelGateway {
  LocalModelProfile? downloadedProfile;
  LocalModelProfile? profile;
  String? prompt;
  String? systemInstruction;

  @override
  Future<void> install(LocalModelProfile profile) async {
    downloadedProfile = profile;
  }

  @override
  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
  }) async* {
    this.profile = profile;
    this.prompt = prompt;
    this.systemInstruction = systemInstruction;
    yield 'Local ';
    yield 'answer';
  }
}
