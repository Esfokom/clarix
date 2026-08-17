import 'package:clarix/src/features/pdf_editor/presentation/recovery_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recovered project banner exposes review without data loss', (
    tester,
  ) async {
    var reviewed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecoveryBanner(
            revision: 7,
            onReview: () => reviewed = true,
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('revision 7'), findsOneWidget);
    await tester.tap(find.text('Review edits'));
    expect(reviewed, isTrue);
  });
}
