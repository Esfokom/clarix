import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/ai_provider.dart';

class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const <AiToolCall>[],
  });

  const AiChatMessage.user(String content)
    : this(role: 'user', content: content);

  const AiChatMessage.system(String content)
    : this(role: 'system', content: content);

  const AiChatMessage.tool({
    required String toolCallId,
    required String content,
  }) : this(role: 'tool', content: content, toolCallId: toolCallId);

  AiChatMessage.assistantToolCalls(List<AiToolCall> toolCalls)
    : this(role: 'assistant', content: '', toolCalls: toolCalls);

  final String role;
  final String content;
  final String? toolCallId;
  final List<AiToolCall> toolCalls;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role,
    'content': content,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls
          .map(
            (AiToolCall call) => <String, dynamic>{
              'id': call.id,
              'type': 'function',
              'function': <String, dynamic>{
                'name': call.name,
                'arguments': call.argumentsJson,
              },
            },
          )
          .toList(),
  };
}

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

sealed class AiProviderEvent {
  const AiProviderEvent();
}

class AiTextDelta extends AiProviderEvent {
  const AiTextDelta(this.text);
  final String text;
}

class AiCompletionFinished extends AiProviderEvent {
  const AiCompletionFinished({this.toolCalls = const <AiToolCall>[]});
  final List<AiToolCall> toolCalls;
}

class AiProviderException implements Exception {
  const AiProviderException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class OpenAiChatRequest {
  const OpenAiChatRequest({
    required this.profile,
    required this.apiKey,
    required this.messages,
    this.tools = const <Map<String, dynamic>>[],
  });

  final AiProviderProfile profile;
  final String apiKey;
  final List<AiChatMessage> messages;
  final List<Map<String, dynamic>> tools;
}

class OpenAiTransportRequest {
  const OpenAiTransportRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class OpenAiTransportResponse {
  const OpenAiTransportResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Stream<List<int>> body;
}

abstract interface class OpenAiTransport {
  Future<OpenAiTransportResponse> post(OpenAiTransportRequest request);
  void cancel();
}

class IoOpenAiTransport implements OpenAiTransport {
  IoOpenAiTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  HttpClientRequest? _activeRequest;

  @override
  Future<OpenAiTransportResponse> post(OpenAiTransportRequest request) async {
    final HttpClientRequest active = await _client.postUrl(request.uri);
    _activeRequest = active;
    request.headers.forEach(active.headers.set);
    active.write(request.body);
    final HttpClientResponse response = await active.close();
    return OpenAiTransportResponse(
      statusCode: response.statusCode,
      body: response,
    );
  }

  @override
  void cancel() {
    _activeRequest?.abort();
    _activeRequest = null;
  }
}

class OpenAiCompatibleProvider {
  OpenAiCompatibleProvider({OpenAiTransport? transport})
    : _transport = transport ?? IoOpenAiTransport();

  final OpenAiTransport _transport;

  Future<void> testCredentials({
    required AiProviderProfile profile,
    required String apiKey,
  }) async {
    await streamChat(
      OpenAiChatRequest(
        profile: profile,
        apiKey: apiKey,
        messages: const <AiChatMessage>[AiChatMessage.user('Reply with OK.')],
      ),
    ).drain<void>();
  }

  Stream<AiProviderEvent> streamChat(OpenAiChatRequest request) async* {
    final OpenAiTransportResponse response = await _transport.post(
      OpenAiTransportRequest(
        uri: request.profile.chatCompletionsUri,
        headers: <String, String>{
          'accept': 'text/event-stream',
          'content-type': 'application/json',
          'authorization': 'Bearer ${request.apiKey}',
          ...request.profile.headers,
        },
        body: jsonEncode(<String, dynamic>{
          'model': request.profile.modelId,
          'stream': true,
          'messages': request.messages
              .map((AiChatMessage item) => item.toJson())
              .toList(),
          if (request.tools.isNotEmpty) 'tools': request.tools,
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String body = await utf8.decoder.bind(response.body).join();
      throw AiProviderException(
        response.statusCode,
        _errorMessage(response.statusCode, body),
      );
    }

    final Map<int, _ToolCallAccumulator> calls = <int, _ToolCallAccumulator>{};
    await for (final String line
        in utf8.decoder.bind(response.body).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final String data = line.substring('data: '.length);
      if (data == '[DONE]') {
        yield AiCompletionFinished(
          toolCalls: calls.values
              .map((item) => item.build())
              .toList(growable: false),
        );
        return;
      }
      final dynamic decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        throw const AiProviderException(
          0,
          'The provider sent an invalid streaming response.',
        );
      }
      if (decoded is! Map<String, dynamic>) continue;
      final Object? choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        continue;
      }
      final Object? delta = (choices.first as Map<Object?, Object?>)['delta'];
      if (delta is! Map) continue;
      final Object? content = delta['content'];
      if (content is String && content.isNotEmpty) yield AiTextDelta(content);
      final Object? rawCalls = delta['tool_calls'];
      if (rawCalls is List) {
        for (final Object? rawCall in rawCalls) {
          if (rawCall is! Map) continue;
          final int index = rawCall['index'] as int? ?? 0;
          calls.putIfAbsent(index, _ToolCallAccumulator.new).append(rawCall);
        }
      }
    }
    throw const AiProviderException(
      0,
      'The provider closed the stream before completion.',
    );
  }

  void cancel() => _transport.cancel();

  String _errorMessage(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      return 'The provider rejected this API key.';
    }
    if (statusCode == 429) {
      return 'The provider is rate limiting requests. Try again shortly.';
    }
    if (statusCode >= 500) return 'The provider is temporarily unavailable.';
    return body.isEmpty
        ? 'The provider request failed (HTTP $statusCode).'
        : 'The provider request failed (HTTP $statusCode).';
  }
}

class _ToolCallAccumulator {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  void append(Map<Object?, Object?> raw) {
    final Object? rawId = raw['id'];
    if (rawId is String) id = rawId;
    final Object? function = raw['function'];
    if (function is! Map) return;
    final Object? rawName = function['name'];
    if (rawName is String) name = rawName;
    final Object? rawArguments = function['arguments'];
    if (rawArguments is String) arguments.write(rawArguments);
  }

  AiToolCall build() =>
      AiToolCall(id: id, name: name, argumentsJson: arguments.toString());
}
