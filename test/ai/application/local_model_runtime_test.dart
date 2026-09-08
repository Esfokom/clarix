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
    expect(gateway.prompt, contains('What does the report conclude?'));
    expect(gateway.prompt, contains('The conclusion is positive.'));
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

  test(
    'uninstalls the selected Gemma profile through the local gateway',
    () async {
      final _FakeGateway gateway = _FakeGateway();
      final LocalModelRuntime runtime = LocalModelRuntime(gateway: gateway);

      await runtime.delete(profile);

      expect(gateway.deletedProfile, profile);
    },
  );

  test(
    'checks whether Flutter Gemma still has a local model installed',
    () async {
      final _FakeGateway gateway = _FakeGateway()..installed = true;
      final LocalModelRuntime runtime = LocalModelRuntime(gateway: gateway);

      expect(await runtime.isInstalled(profile), isTrue);
      expect(gateway.checkedProfile, profile);
    },
  );
}

class _FakeGateway implements LocalModelGateway {
  LocalModelProfile? downloadedProfile;
  LocalModelProfile? deletedProfile;
  LocalModelProfile? profile;
  String? prompt;
  String? systemInstruction;
  LocalModelProfile? checkedProfile;
  bool installed = false;

  @override
  Future<bool> isInstalled(LocalModelProfile profile) async {
    checkedProfile = profile;
    return installed;
  }

  @override
  Future<void> install(LocalModelProfile profile) async {
    downloadedProfile = profile;
  }

  @override
  Future<void> uninstall(LocalModelProfile profile) async {
    deletedProfile = profile;
  }

  @override
  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
    required List<String> conversationHistory,
  }) async* {
    this.profile = profile;
    this.prompt = prompt;
    this.systemInstruction = systemInstruction;
    yield 'Local ';
    yield 'answer';
  }
}
