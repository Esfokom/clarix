import 'dart:async';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/application/ai_agent_runtime.dart';
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
  final List<PdfChunkRecord> chunks = <PdfChunkRecord>[
    const PdfChunkRecord(
      id: 'chunk-1',
      documentId: 'document-1',
      title: 'contract.pdf',
      pageNumber: 4,
      chunkOrder: 0,
      text: 'The termination clause is here.',
    ),
  ];

  test('does not send passages when provider sharing is disabled', () async {
    final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
      <AiProviderEvent>[
        const AiTextDelta('Answer'),
        const AiCompletionFinished(),
      ],
    ]);
    final AiAgentRuntime runtime = AiAgentRuntime(
      provider: provider,
      readChunks: (_) async => chunks,
    );

    await runtime.run(
      AiAgentRequest(
        profile: AiProviderProfile.create(
          id: profile.id,
          label: profile.label,
          baseUrl: profile.baseUrl,
          modelId: profile.modelId,
          shareRetrievedPassages: false,
        ),
        apiKey: 'sk-test',
        prompt: 'What is termination?',
        documentIds: const <String>['document-1'],
      ),
    );

    expect(
      provider.requests.single.messages
          .map((AiChatMessage item) => item.content)
          .join(),
      isNot(contains('[source')),
    );
  });

  test('executes valid search tool and completes next model round', () async {
    final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
      <AiProviderEvent>[
        const AiCompletionFinished(
          toolCalls: <AiToolCall>[
            AiToolCall(
              id: 'call_1',
              name: 'search_document',
              argumentsJson: '{"query":"termination"}',
            ),
          ],
        ),
      ],
      <AiProviderEvent>[
        const AiTextDelta('It is on page 4.'),
        const AiCompletionFinished(),
      ],
    ]);
    final AiAgentRuntime runtime = AiAgentRuntime(
      provider: provider,
      readChunks: (_) async => chunks,
    );

    final AiAgentReply reply = await runtime.run(
      AiAgentRequest(
        profile: profile,
        apiKey: 'sk-test',
        prompt: 'Find termination',
        documentIds: const <String>['document-1'],
      ),
    );

    expect(reply.text, 'It is on page 4.');
    expect(reply.citations.single.pageNumber, 4);
    expect(provider.requests, hasLength(2));
    expect(provider.requests.last.messages.last.role, 'tool');
  });
}

class _FakeProvider extends OpenAiCompatibleProvider {
  _FakeProvider(this.responses) : super(transport: _NoopTransport());

  final List<List<AiProviderEvent>> responses;
  final List<OpenAiChatRequest> requests = <OpenAiChatRequest>[];

  @override
  Stream<AiProviderEvent> streamChat(OpenAiChatRequest request) {
    requests.add(request);
    return Stream<AiProviderEvent>.fromIterable(responses.removeAt(0));
  }
}

class _NoopTransport implements OpenAiTransport {
  @override
  void cancel() {}
  @override
  Future<OpenAiTransportResponse> post(OpenAiTransportRequest request) =>
      throw UnimplementedError();
}
