import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('uses a document-only empty state and expanded composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(const <ComposerMessage>[]),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('ai-empty-title')), findsOneWidget);
    expect(find.text('Current PDF'), findsNothing);
    expect(find.byKey(const Key('document-composer')), findsOneWidget);
    final TextField input = tester.widget<TextField>(
      find.byKey(const Key('document-composer-input')),
    );
    expect(input.minLines, 3);
    expect(input.maxLines, 6);
  });

  testWidgets('disables sending until native document context is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(const <ComposerMessage>[]),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    final TextField input = tester.widget<TextField>(
      find.byKey(const Key('document-composer-input')),
    );
    final IconButton send = tester.widget<IconButton>(
      find.byKey(const Key('document-composer-send')),
    );

    expect(input.enabled, isFalse);
    expect(send.onPressed, isNull);
  });

  testWidgets('renders Markdown and math in both chat roles', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(<ComposerMessage>[
                _message('user', r'# Question\n- **Bold** with $x^2$'),
                _message(
                  'assistant',
                  r'## Answer\n$$\frac{a}{b}$$',
                  citations: const <CitationSnippet>[
                    CitationSnippet(
                      documentId: 'document',
                      label: 'Document',
                      pageNumber: 2,
                      snippet: 'Supporting passage',
                    ),
                  ],
                ),
              ]),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsNWidgets(2));
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('**Bold**'), findsNothing);
    expect(find.byKey(const Key('user-message-bubble')), findsOneWidget);
    expect(find.byKey(const Key('assistant-message-content')), findsOneWidget);
    expect(find.byKey(const Key('citation-page-2')), findsNothing);
  });

  testWidgets(
    'renders assistant page references inline and starts ranges at the first page',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadApp(
            home: Scaffold(
              body: AiSidePane(
                aiState: _state(<ComposerMessage>[
                  _message(
                    'assistant',
                    'Case study (page 2). Organizational structure (pages 7–8).',
                  ),
                ]),
                documentContext: null,
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('inline-page-reference-2')), findsOneWidget);
      expect(find.byKey(const Key('inline-page-reference-7')), findsOneWidget);
      expect(find.byKey(const Key('citation-page-2')), findsNothing);
      expect(find.byKey(const Key('citation-page-7')), findsNothing);
    },
  );

  testWidgets(
    'does not add citation UI when assistant prose has no page reference',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadApp(
            home: Scaffold(
              body: AiSidePane(
                aiState: _state(<ComposerMessage>[
                  _message(
                    'assistant',
                    'This is a document overview without page references.',
                  ),
                ]),
                documentContext: null,
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('inline-page-reference-2')), findsNothing);
      expect(find.byKey(const Key('citation-page-2')), findsNothing);
    },
  );

  testWidgets('uses a neutral composer loader while a response is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(
                const <ComposerMessage>[],
                chatBusy: true,
                statusMessage: 'Contacting DeepSeek.',
              ),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('composer-loader')), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Contacting DeepSeek.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Tracing'), findsOneWidget);
  });

  testWidgets(
    'offers downloaded local Gemma and remote providers in the runtime picker',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadApp(
            home: Scaffold(
              body: AiSidePane(
                aiState: _state(
                  const <ComposerMessage>[],
                  localModels: <LocalModelProfile>[
                    LocalModelProfile.gemma4(
                      id: 'gemma-local',
                      label: 'Gemma 4 E2B (Local)',
                      modelFileName: 'gemma-4-E2B-it.litertlm',
                    ),
                  ],
                  providers: <AiProviderProfile>[_remoteProfile],
                ),
                documentContext: null,
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('ai-runtime-picker')));
      await tester.pumpAndSettle();

      expect(find.text('Gemma 4 E2B (Local)'), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
    },
  );
}

AiFeatureState _state(
  List<ComposerMessage> messages, {
  bool chatBusy = false,
  String? statusMessage,
  List<LocalModelProfile> localModels = const <LocalModelProfile>[],
  List<AiProviderProfile> providers = const <AiProviderProfile>[],
}) => AiFeatureState(
  chat: AiWorkspaceState.initial().copyWith(
    providerReady: true,
    chatBusy: chatBusy,
    statusMessage: statusMessage,
    messages: messages,
  ),
  providerProfiles: providers,
  localModels: localModels,
);

final AiProviderProfile _remoteProfile = AiProviderProfile.create(
  id: 'deepseek',
  label: 'DeepSeek',
  baseUrl: 'https://api.deepseek.com/v1',
  modelId: 'deepseek-chat',
  shareRetrievedPassages: false,
);

ComposerMessage _message(
  String role,
  String text, {
  List<CitationSnippet> citations = const <CitationSnippet>[],
}) => ComposerMessage(
  id: role,
  role: role,
  text: text,
  createdAt: DateTime.utc(2026),
  citations: citations,
);
