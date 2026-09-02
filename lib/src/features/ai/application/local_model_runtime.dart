import '../domain/ai_models.dart';
import '../domain/local_model_profile.dart';

abstract interface class LocalModelGateway {
  Future<void> install(LocalModelProfile profile);

  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
  });
}

class LocalModelRuntime {
  LocalModelRuntime({required this.gateway});

  final LocalModelGateway gateway;

  Future<void> download(LocalModelProfile profile) => gateway.install(profile);

  Future<void> sendPrompt({
    required LocalModelProfile profile,
    required String prompt,
    required List<CitationSnippet> documentSnippets,
    required void Function(String token) onToken,
  }) async {
    await for (final String token in gateway.generate(
      profile: profile,
      prompt: prompt,
      systemInstruction: _documentContext(documentSnippets),
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
