import 'package:clarix/src/features/reader/presentation/reader_selection_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders every configured highlight colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSelectionToolbar(
            anchorAbove: const Offset(120, 100),
            anchorBelow: const Offset(120, 120),
            highlightColors: const <int>[0xFFFFD54F, 0xFF80CBC4],
            onCopy: () {},
            onAskAi: () {},
            onNote: () {},
            onBookmark: () {},
            onReadAloud: () {},
            onHighlight: (_) {},
            onMoreColors: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('reader-selection-toolbar')), findsOneWidget);
    expect(find.byKey(const Key('reader-highlight-ffffd54f')), findsOneWidget);
    expect(find.byKey(const Key('reader-highlight-ff80cbc4')), findsOneWidget);
    expect(find.text('More colours'), findsOneWidget);
  });

  testWidgets('dispatches a chosen highlight colour', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSelectionToolbar(
            anchorAbove: const Offset(120, 100),
            anchorBelow: const Offset(120, 120),
            highlightColors: const <int>[0xFFFFD54F],
            onCopy: () {},
            onAskAi: () {},
            onNote: () {},
            onBookmark: () {},
            onReadAloud: () {},
            onHighlight: (int value) => selected = value,
            onMoreColors: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('reader-highlight-ffffd54f')));
    expect(selected, 0xFFFFD54F);
  });
}
