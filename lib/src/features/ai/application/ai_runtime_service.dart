import '../../../core/clarix_logger.dart';
import 'dart:convert';
import 'dart:io';
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import '../infrastructure/local_model_store.dart';
import 'local_model_runtime.dart';

class AiRuntimeService {
  AiRuntimeService({
    required this.providerProfiles,
    required this.localModels,
    required this.localRuntime,
    RemoteChatGateway? remoteGateway,
    Future<void> Function()? ensureNativeReady,
  }) : remoteGateway = remoteGateway ?? DartOpenAiCompatibleGateway();

  final ProviderProfileStore providerProfiles;
  final LocalModelStore localModels;
  final LocalModelRuntime localRuntime;
  final RemoteChatGateway remoteGateway;

  Future<void> testProvider(AiProviderProfile profile, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('Enter an API key before testing this provider.');
    }
    await remoteGateway
        .stream(
          profile: profile,
          apiKey: apiKey.trim(),
          messages: const <RemoteChatMessage>[
            RemoteChatMessage(role: 'user', content: 'Reply with OK.'),
          ],
        )
        .first;
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required String profileId,
    required List<CitationSnippet> documentSnippets,
    List<RemoteChatMessage> conversationHistory = const <RemoteChatMessage>[],
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final localProfile = (await localModels.readAll())
        .where((item) => item.id == profileId)
        .firstOrNull;
    if (localProfile != null) {
      onStatus?.call(
        AiRuntimePhase.loadingInference,
        'Loading ${localProfile.label} into device memory. '
        'The first response may take a minute.',
      );
      final buffer = StringBuffer();
      var receivedFirstToken = false;
      await localRuntime.sendPrompt(
        profile: localProfile,
        prompt: prompt,
        documentSnippets: documentSnippets,
        conversationHistory: conversationHistory
            .map(
              (RemoteChatMessage message) =>
                  '${message.role}: ${message.content}',
            )
            .toList(growable: false),
        onToken: (String token) {
          if (!receivedFirstToken) {
            receivedFirstToken = true;
            onStatus?.call(
              AiRuntimePhase.generating,
              'Generating with ${localProfile.label} on this device.',
            );
          }
          buffer.write(token);
          onToken(token);
        },
      );
      return AiReply(
        text: buffer.toString(),
        citations: const <CitationSnippet>[],
      );
    }
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      clarixLog.w('AI runtime rejected prompt: selected provider is missing.');
      throw StateError('Select a remote AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id);
    if (key == null || key.isEmpty) {
      clarixLog.w(
        'AI runtime rejected prompt: ${profile.label} has no API key.',
      );
      throw StateError('Add an API key for ${profile.label}.');
    }
    clarixLog.i(
      'AI runtime prepared ${profile.label} streaming request '
      '(model=${profile.modelId}, endpoint=${profile.baseUrl}).',
    );
    onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}.');
    final buffer = StringBuffer();
    await for (final text in remoteGateway.stream(
      profile: profile,
      apiKey: key,
      messages: <RemoteChatMessage>[
        if (documentSnippets.isNotEmpty)
          RemoteChatMessage(
            role: 'system',
            content: _documentContext(documentSnippets),
          ),
        ...conversationHistory,
        RemoteChatMessage(role: 'user', content: prompt),
      ],
    )) {
      buffer.write(text);
      onToken(text);
    }
    return AiReply(
      text: buffer.toString(),
      citations: const <CitationSnippet>[],
    );
  }

  Future<void> stopGeneration() async {}
  Future<void> dispose() async {}
}

class RemoteChatMessage {
  const RemoteChatMessage({required this.role, required this.content});
  final String role;
  final String content;
}

abstract interface class RemoteChatGateway {
  Stream<String> stream({
    required AiProviderProfile profile,
    required String apiKey,
    required List<RemoteChatMessage> messages,
  });
}

class DartOpenAiCompatibleGateway implements RemoteChatGateway {
  @override
  Stream<String> stream({
    required AiProviderProfile profile,
    required String apiKey,
    required List<RemoteChatMessage> messages,
  }) async* {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(
        profile.chatCompletionsUri,
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.contentType = ContentType.json;
      profile.headers.forEach(request.headers.set);
      request.write(
        jsonEncode(<String, Object>{
          'model': profile.modelId,
          'messages': messages
              .map(
                (RemoteChatMessage message) => <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
              )
              .toList(growable: false),
          'stream': true,
        }),
      );
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Provider returned HTTP ${response.statusCode}.');
      }
      await for (final String line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final String data = line.substring(5).trim();
        if (data == '[DONE]') return;
        final dynamic decoded = jsonDecode(data);
        String? text;
        if (decoded is Map) {
          final Object? choices = decoded['choices'];
          if (choices is List && choices.isNotEmpty) {
            final Object? first = choices.first;
            if (first is Map && first['delta'] is Map) {
              text = (first['delta'] as Map)['content'] as String?;
            }
          }
        }
        if (text != null && text.isNotEmpty) yield text;
      }
    } finally {
      client.close(force: true);
    }
  }
}

String _documentContext(List<CitationSnippet> snippets) {
  final String excerpts = snippets
      .map(
        (CitationSnippet snippet) =>
            '[${snippet.label}, page ${snippet.pageNumber}]\n${snippet.snippet}',
      )
      .join('\n\n');
  return 'Answer using the supplied PDF excerpts when relevant. '
      'Mention page numbers when you rely on an excerpt.\n\n$excerpts';
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
