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
                _message('assistant', r'## Answer\n$$\frac{a}{b}$$'),
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
  });
}

WorkspaceFeatureState _state(List<ComposerMessage> messages) =>
    WorkspaceFeatureState(
      session: WorkspaceSession.initial(),
      aiState: AiWorkspaceState.initial().copyWith(
        providerReady: true,
        messages: messages,
      ),
      outlines: const <String, List<OutlineNodeState>>{},
      documentMetadata: const <String, DocumentMetadata>{},
      composerExpanded: false,
      bannerMessage: null,
    );

ComposerMessage _message(String role, String text) => ComposerMessage(
  id: role,
  role: role,
  text: text,
  createdAt: DateTime.utc(2026),
  citations: const <CitationSnippet>[],
);
