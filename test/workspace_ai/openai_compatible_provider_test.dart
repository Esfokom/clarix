import 'dart:convert';

import 'package:clarix/src/features/workspace/domain/ai_provider.dart';
import 'package:clarix/src/features/workspace/infrastructure/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AiProviderProfile profile = AiProviderProfile.create(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    modelId: 'gpt-5',
    shareRetrievedPassages: true,
  );

  test('encodes streaming chat completions request with tools', () async {
    final _FakeTransport transport = _FakeTransport(<String>['data: [DONE]\n']);
    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider(
      transport: transport,
    );

    await provider
        .streamChat(
          OpenAiChatRequest(
            profile: profile,
            apiKey: 'sk-test',
            messages: const <AiChatMessage>[
              AiChatMessage.user('Where is the clause?'),
            ],
            tools: <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'function',
                'function': <String, dynamic>{'name': 'search_document'},
              },
            ],
          ),
        )
        .drain<void>();

    expect(transport.request!.uri, profile.chatCompletionsUri);
    expect(transport.request!.headers['authorization'], 'Bearer sk-test');
    final Map<String, dynamic> body =
        jsonDecode(transport.request!.body) as Map<String, dynamic>;
    expect(body['stream'], isTrue);
    expect(
      (body['tools'] as List<dynamic>).single,
      containsPair('type', 'function'),
    );
  });

  test('streams text then tool call fragments before completion', () async {
    final _FakeTransport transport = _FakeTransport(<String>[
      'data: {"choices":[{"delta":{"content":"Hello "}}]}\n',
      'data: ${jsonEncode(<String, dynamic>{
        'choices': <Object>[
          <String, dynamic>{
            'delta': <String, dynamic>{
              'content': 'world',
              'tool_calls': <Object>[
                <String, dynamic>{
                  'index': 0,
                  'id': 'call_1',
                  'function': <String, String>{'name': 'search_document', 'arguments': r'{"query":"term'},
                },
              ],
            },
          },
        ],
      })}\n',
      'data: ${jsonEncode(<String, dynamic>{
        'choices': <Object>[
          <String, dynamic>{
            'delta': <String, dynamic>{
              'tool_calls': <Object>[
                <String, dynamic>{
                  'index': 0,
                  'function': <String, String>{'arguments': r'ination"}'},
                },
              ],
            },
          },
        ],
      })}\n',
      'data: [DONE]\n',
    ]);
    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider(
      transport: transport,
    );

    final List<AiProviderEvent> events = await provider
        .streamChat(
          OpenAiChatRequest(
            profile: profile,
            apiKey: 'sk-test',
            messages: const <AiChatMessage>[AiChatMessage.user('Find it')],
          ),
        )
        .toList();

    expect(
      events
          .whereType<AiTextDelta>()
          .map((AiTextDelta item) => item.text)
          .join(),
      'Hello world',
    );
    final AiCompletionFinished completed = events.last as AiCompletionFinished;
    expect(completed.toolCalls.single.name, 'search_document');
    expect(completed.toolCalls.single.argumentsJson, '{"query":"termination"}');
  });
}

class _FakeTransport implements OpenAiTransport {
  _FakeTransport(this.lines);

  final List<String> lines;
  OpenAiTransportRequest? request;

  @override
  Future<OpenAiTransportResponse> post(OpenAiTransportRequest value) async {
    request = value;
    return OpenAiTransportResponse(
      statusCode: 200,
      body: Stream<List<int>>.fromIterable(lines.map(utf8.encode)),
    );
  }

  @override
  void cancel() {}
}
