import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

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

  testWidgets('shows the responding model and a copy control for an answer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(<ComposerMessage>[
                _message('assistant', 'A local answer.', modelLabel: 'Gemma 4'),
              ]),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Responded by Gemma 4'), findsOneWidget);
    expect(
      find.byKey(const Key('copy-assistant-response-assistant')),
      findsOneWidget,
    );
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
                  selectedProviderId: 'gemma-local',
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

      expect(find.byKey(const Key('ai-runtime-picker-label')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-runtime-picker')));
      await tester.pumpAndSettle();

      expect(find.text('Gemma 4 E2B (Local)'), findsNWidgets(2));
      expect(find.text('DeepSeek'), findsOneWidget);
    },
  );

  testWidgets('switches models without disturbing an open conversation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(
                <ComposerMessage>[_message('user', 'Existing question')],
                selectedProviderId: 'deepseek',
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
    await tester.tap(find.text('Gemma 4 E2B (Local)').last);
    await tester.pumpAndSettle();

    // No confirmation, and the transcript stays put.
    expect(find.text('Start a new conversation?'), findsNothing);
    expect(find.byKey(const Key('user-message-bubble')), findsOneWidget);
  });

  testWidgets('keeps the runtime picker inside the composer', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(
                const <ComposerMessage>[],
                selectedProviderId: 'deepseek',
                providers: <AiProviderProfile>[_remoteProfile],
              ),
              documentContext: null,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('document-composer')),
        matching: find.byKey(const Key('ai-runtime-picker')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows conversation history inside the pane, not a dialog', (
    tester,
  ) async {
    final DateTime now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationStoreProvider.overrideWith(
            (ref) async => _FakeConversationStore(<ConversationThread>[
              ConversationThread(
                id: 'thread-a',
                documentId: 'document',
                title: 'Revenue breakdown',
                createdAt: now.subtract(const Duration(hours: 5)),
                updatedAt: now.subtract(const Duration(hours: 3)),
              ),
              ConversationThread(
                id: 'thread-b',
                documentId: 'document',
                title: 'Methodology questions',
                createdAt: now.subtract(const Duration(days: 4)),
                updatedAt: now.subtract(const Duration(days: 2)),
              ),
            ]),
          ),
        ],
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(<ComposerMessage>[
                _message('user', 'Existing question'),
              ], activeConversationId: 'thread-a'),
              documentContext: _documentContext,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ai-conversation-history')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('ai-history-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-thread-thread-a')),
      findsOneWidget,
    );
    expect(find.text('Revenue breakdown'), findsOneWidget);
    expect(find.text('Methodology questions'), findsOneWidget);
    expect(find.text('3h ago'), findsOneWidget);
    expect(find.text('2d ago'), findsOneWidget);

    // The transcript is replaced while history is open.
    expect(find.byKey(const Key('user-message-bubble')), findsNothing);

    // Composing belongs to the transcript; history pins a new conversation
    // where the composer would be.
    expect(find.byKey(const Key('document-composer')), findsNothing);
    expect(find.byKey(const Key('ai-new-conversation')), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);

    // The conversation that was open reads as the current one.
    expect(find.byIcon(LucideIcons.messageSquareDot), findsOneWidget);
  });

  testWidgets('a pinned new conversation returns to the composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationStoreProvider.overrideWith(
            (ref) async => _FakeConversationStore(<ConversationThread>[
              ConversationThread(
                id: 'thread-a',
                documentId: 'document',
                title: 'Revenue breakdown',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ]),
          ),
        ],
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(const <ComposerMessage>[]),
              documentContext: _documentContext,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ai-conversation-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-composer')), findsNothing);

    await tester.tap(find.byKey(const Key('ai-new-conversation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-history-panel')), findsNothing);
    expect(find.byKey(const Key('document-composer')), findsOneWidget);
  });

  testWidgets('reports context usage as a ring in the composer', (
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

    expect(
      find.descendant(
        of: find.byKey(const Key('document-composer')),
        matching: find.byKey(const Key('ai-context-usage')),
      ),
      findsOneWidget,
    );
    expect(find.text('Document context'), findsNothing);
  });

  testWidgets('an empty history explains itself in the pane', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationStoreProvider.overrideWith(
            (ref) async =>
                _FakeConversationStore(const <ConversationThread>[]),
          ),
        ],
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              aiState: _state(const <ComposerMessage>[]),
              documentContext: _documentContext,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ai-conversation-history')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-history-empty')), findsOneWidget);
  });

  test('conversation timestamps read chronologically', () {
    final DateTime now = DateTime(2026, 3, 12, 14);
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      'Just now',
    );
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(minutes: 8)),
        now: now,
      ),
      '8m ago',
    );
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(hours: 6)),
        now: now,
      ),
      '6h ago',
    );
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(days: 1)),
        now: now,
      ),
      'Yesterday',
    );
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(days: 40)),
        now: now,
      ),
      '31 Jan',
    );
    expect(
      formatConversationTimestamp(
        now.subtract(const Duration(days: 400)),
        now: now,
      ),
      '5 Feb 2025',
    );
  });
}

class _FakeConversationStore extends ConversationStore {
  _FakeConversationStore(this.threads);

  final List<ConversationThread> threads;

  @override
  Future<List<ConversationThread>> listThreads(String documentId) async =>
      threads;
}

const AiDocumentContext _documentContext = AiDocumentContext(
  tabId: 'tab',
  documentId: 'document',
  title: 'Paper',
  filePath: r'C:\docs\paper.pdf',
);

AiFeatureState _state(
  List<ComposerMessage> messages, {
  bool chatBusy = false,
  String? statusMessage,
  String? selectedProviderId,
  String? activeConversationId,
  List<LocalModelProfile> localModels = const <LocalModelProfile>[],
  List<AiProviderProfile> providers = const <AiProviderProfile>[],
}) => AiFeatureState(
  chat: AiWorkspaceState.initial().copyWith(
    providerReady: true,
    chatBusy: chatBusy,
    statusMessage: statusMessage,
    selectedProviderId: selectedProviderId,
    activeConversationId: activeConversationId,
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
  String? modelLabel,
}) => ComposerMessage(
  id: role,
  role: role,
  text: text,
  createdAt: DateTime.utc(2026),
  citations: citations,
  modelLabel: modelLabel,
);
