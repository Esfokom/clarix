import 'dart:async';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/application/ai_agent_runtime.dart';
import 'package:clarix/src/features/workspace/domain/ai_provider.dart';
import 'package:clarix/src/features/workspace/infrastructure/local_rag_service.dart';
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
      localRag: LocalRagService(readChunks: (_) async => chunks),
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
      localRag: LocalRagService(readChunks: (_) async => chunks),
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

  test('grounds the answer in ranked, page-labelled passages', () async {
    final List<PdfChunkRecord> rankedChunks = <PdfChunkRecord>[
      const PdfChunkRecord(
        id: 'unrelated-first',
        documentId: 'document-1',
        title: 'contract.pdf',
        pageNumber: 1,
        chunkOrder: 0,
        text: 'This first chunk is unrelated.',
      ),
      const PdfChunkRecord(
        id: 'termination',
        documentId: 'document-1',
        title: 'contract.pdf',
        pageNumber: 8,
        chunkOrder: 1,
        text: 'Termination requires thirty days written notice.',
      ),
    ];
    final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
      <AiProviderEvent>[
        const AiTextDelta('Thirty days.'),
        const AiCompletionFinished(),
      ],
    ]);
    final AiAgentRuntime runtime = AiAgentRuntime(
      provider: provider,
      localRag: LocalRagService(readChunks: (_) async => rankedChunks),
    );

    final AiAgentReply reply = await runtime.run(
      AiAgentRequest(
        profile: profile,
        apiKey: 'sk-test',
        prompt: 'What does termination require?',
        documentIds: const <String>['document-1'],
      ),
    );

    final String sent = provider.requests.single.messages
        .map((AiChatMessage message) => message.content)
        .join('\n');
    expect(sent, contains('[source 1, page 8]'));
    expect(sent, contains('thirty days written notice'));
    expect(sent, isNot(contains('This first chunk is unrelated')));
    expect(reply.citations.single.pageNumber, 8);
  });

  test(
    'requires document evidence and labels supplementary knowledge',
    () async {
      final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
        <AiProviderEvent>[const AiCompletionFinished()],
      ]);
      final AiAgentRuntime runtime = AiAgentRuntime(
        provider: provider,
        localRag: LocalRagService(readChunks: (_) async => chunks),
      );

      await runtime.run(
        AiAgentRequest(
          profile: profile,
          apiKey: 'sk-test',
          prompt: 'What does the document say?',
          documentIds: const <String>['document-1'],
        ),
      );

      final String instruction = provider.requests.single.messages
          .firstWhere((AiChatMessage message) => message.role == 'system')
          .content;
      expect(instruction, contains('Do not use "From the document"'));
      expect(
        instruction,
        contains('*(General context, not stated in the document: …)*'),
      );
      expect(instruction, contains('does not establish a point'));
    },
  );

  test('limits shared passages to six and 1500 characters each', () async {
    final List<PdfChunkRecord> manyChunks = List<PdfChunkRecord>.generate(
      7,
      (int index) => PdfChunkRecord(
        id: 'chunk-$index',
        documentId: 'document-1',
        title: 'contract.pdf',
        pageNumber: index + 1,
        chunkOrder: index,
        text: 'termination ${'x' * 1600}',
      ),
    );
    final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
      <AiProviderEvent>[const AiCompletionFinished()],
    ]);
    final AiAgentRuntime runtime = AiAgentRuntime(
      provider: provider,
      localRag: LocalRagService(readChunks: (_) async => manyChunks),
    );

    final AiAgentReply reply = await runtime.run(
      AiAgentRequest(
        profile: profile,
        apiKey: 'sk-test',
        prompt: 'termination',
        documentIds: const <String>['document-1'],
      ),
    );

    expect(reply.citations, hasLength(6));
    expect(
      reply.citations.every(
        (CitationSnippet citation) => citation.snippet.length <= 1500,
      ),
      isTrue,
    );
    expect(
      provider.requests.single.messages
              .where((AiChatMessage message) => message.role == 'system')
              .singleWhere(
                (AiChatMessage message) => message.content.contains('[source'),
              )
              .content
              .split('[source')
              .length -
          1,
      6,
    );
  });

  test('does not expose document tools when no evidence is shared', () async {
    final _FakeProvider provider = _FakeProvider(<List<AiProviderEvent>>[
      <AiProviderEvent>[const AiCompletionFinished()],
    ]);
    final AiAgentRuntime runtime = AiAgentRuntime(
      provider: provider,
      localRag: LocalRagService(readChunks: (_) async => chunks),
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

    expect(provider.requests.single.tools, isEmpty);
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
