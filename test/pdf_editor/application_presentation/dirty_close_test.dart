import 'package:clarix/src/features/pdf_editor/domain/editor_close_choice.dart';
import 'package:clarix/src/features/pdf_editor/presentation/dirty_close_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dirty close offers all recovery-safe choices', (tester) async {
    final choices = <EditorCloseChoice>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DirtyCloseDialog(onChoice: choices.add, onCancel: () {}),
      ),
    );

    expect(find.text('Save PDF'), findsOneWidget);
    expect(find.text('Keep Recoverable Project'), findsOneWidget);
    expect(find.text('Discard to Recovery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keep-recoverable-project')));
    expect(choices, <EditorCloseChoice>[
      EditorCloseChoice.keepRecoverableProject,
    ]);
  });
}
