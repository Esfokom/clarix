import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/presentation/font_fallback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('font fallback requires explicit approval', (tester) async {
    var approvals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FontFallbackDialog(
          proposal: const EditorFontFallbackProposal(
            token: 'proposal-1',
            objectId: 'object-1',
            fontName: 'Arial Unicode MS',
            source: 'Windows fonts',
            embeddingAllowed: true,
            affectedCharacters: '漢',
          ),
          onApprove: (_) => approvals++,
          onReject: () {},
        ),
      ),
    );

    expect(find.textContaining('Arial Unicode MS'), findsOneWidget);
    expect(approvals, 0);
    await tester.tap(find.byKey(const Key('approve-font-fallback')));
    expect(approvals, 1);
  });
}
