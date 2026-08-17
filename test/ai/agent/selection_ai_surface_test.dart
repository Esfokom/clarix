import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/features/ai/presentation/selection_ai_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentDisclosure disclosure(String selectedText) => AgentDisclosure(
  providerLabel: 'Private provider',
  selectedText: selectedText,
  nearbyTextBefore: 'before',
  nearbyTextAfter: 'after',
  pageNumbers: const <int>[2],
  sha256: 'digest',
);

Widget harness({
  AgentDisclosure? selection,
  ValueChanged<SelectionAiAction>? onStart,
}) => MaterialApp(
  home: Scaffold(
    body: SelectionAiCommandSurface(
      disclosure: selection,
      sharingEnabled: true,
      onStart: onStart ?? (_) {},
    ),
  ),
);

void main() {
  testWidgets(
    'selection toolbar appears only for a validated nonempty selection',
    (tester) async {
      await tester.pumpWidget(harness(selection: disclosure('selected')));
      expect(find.byKey(const Key('selection-ai-toolbar')), findsOneWidget);
      await tester.pumpWidget(harness());
      expect(find.byKey(const Key('selection-ai-toolbar')), findsNothing);
    },
  );

  testWidgets('remote run shows exact disclosure and waits for confirmation', (
    tester,
  ) async {
    var startCount = 0;
    await tester.pumpWidget(
      harness(
        selection: disclosure('private text'),
        onStart: (_) => startCount += 1,
      ),
    );
    await tester.tap(find.text('Rewrite'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-disclosure-preview')), findsOneWidget);
    expect(find.text('private text'), findsOneWidget);
    expect(find.textContaining('Pages: 2'), findsOneWidget);
    expect(startCount, 0);
    await tester.tap(find.text('Share and continue'));
    await tester.pumpAndSettle();
    expect(startCount, 1);
  });
}
