import '../domain/ai_models.dart';
import '../domain/local_model_profile.dart';

abstract interface class LocalModelGateway {
  Future<bool> isInstalled(LocalModelProfile profile);
  Future<void> install(LocalModelProfile profile);
  Future<void> uninstall(LocalModelProfile profile);

  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
    required List<String> conversationHistory,
  });
}

class LocalModelRuntime {
  LocalModelRuntime({required this.gateway});

  final LocalModelGateway gateway;

  Future<bool> isInstalled(LocalModelProfile profile) =>
      gateway.isInstalled(profile);
  Future<void> download(LocalModelProfile profile) => gateway.install(profile);
  Future<void> delete(LocalModelProfile profile) => gateway.uninstall(profile);

  Future<void> sendPrompt({
    required LocalModelProfile profile,
    required String prompt,
    required List<CitationSnippet> documentSnippets,
    List<String> conversationHistory = const <String>[],
    required void Function(String token) onToken,
  }) async {
    await for (final String token in gateway.generate(
      profile: profile,
      prompt: _groundedPrompt(prompt, documentSnippets),
      systemInstruction: _localSystemInstruction,
      conversationHistory: conversationHistory,
    )) {
      onToken(token);
    }
  }
}

String _groundedPrompt(String prompt, List<CitationSnippet> snippets) {
  if (snippets.isEmpty) return prompt;
  final excerpts = snippets
      .take(3)
      .map(
        (CitationSnippet snippet) =>
            '[${snippet.label}, page ${snippet.pageNumber}]\n'
            '${_truncateSnippet(snippet.snippet)}',
      )
      .join('\n\n');
  return 'Use these retrieved PDF passages to answer the question. Cite page '
      'numbers when you rely on them.\n\n$excerpts\n\n'
      'Question: $prompt';
}

String _truncateSnippet(String snippet) {
  const int maximumCharacters = 600;
  if (snippet.length <= maximumCharacters) return snippet;
  return '${snippet.substring(0, maximumCharacters)}…';
}

const String _localSystemInstruction =
    'You are Clarix, a helpful document assistant. Be concise and accurate.';
