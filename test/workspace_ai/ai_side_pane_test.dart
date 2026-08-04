import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/ai_side_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('renders Markdown and math in both chat roles', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              state: _state(<ComposerMessage>[
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
              activeTab: DocumentTabState.create(
                id: 'tab',
                documentId: 'document',
                filePath: 'document.pdf',
                title: 'document.pdf',
              ),
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
    expect(find.byKey(const Key('citation-page-2')), findsOneWidget);
  });

  testWidgets('uses a neutral composer loader while a response is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ShadApp(
          home: Scaffold(
            body: AiSidePane(
              state: _state(
                const <ComposerMessage>[],
                chatBusy: true,
                statusMessage: 'Contacting DeepSeek.',
              ),
              activeTab: DocumentTabState.create(
                id: 'tab',
                documentId: 'document',
                filePath: 'document.pdf',
                title: 'document.pdf',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('composer-loader')), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Contacting DeepSeek.'), findsNothing);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Tracing'), findsOneWidget);
  });
}

WorkspaceFeatureState _state(
  List<ComposerMessage> messages, {
  bool chatBusy = false,
  String? statusMessage,
}) => WorkspaceFeatureState(
  session: WorkspaceSession.initial(),
  aiState: AiWorkspaceState.initial().copyWith(
    providerReady: true,
    chatBusy: chatBusy,
    statusMessage: statusMessage,
    messages: messages,
  ),
  outlines: const <String, List<OutlineNodeState>>{},
  documentMetadata: const <String, DocumentMetadata>{},
  composerExpanded: false,
  bannerMessage: null,
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
