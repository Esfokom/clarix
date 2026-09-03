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
      prompt: prompt,
      systemInstruction: _documentContext(documentSnippets),
      conversationHistory: conversationHistory,
    )) {
      onToken(token);
    }
  }
}

String _documentContext(List<CitationSnippet> snippets) {
  if (snippets.isEmpty) {
    return 'You are Clarix, a helpful document assistant. Be concise and accurate.';
  }
  final String excerpts = snippets
      .map(
        (CitationSnippet snippet) =>
            '[${snippet.label}, page ${snippet.pageNumber}]\n${snippet.snippet}',
      )
      .join('\n\n');
  return 'You are Clarix, a helpful document assistant. Answer using the '
      'supplied PDF excerpts when relevant. Mention page numbers when you '
      'rely on an excerpt.\n\n$excerpts';
}
