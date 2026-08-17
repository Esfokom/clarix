import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_save_state.dart';
import 'package:clarix/src/features/pdf_editor/presentation/save_conflict_dialog.dart';
import 'package:clarix/src/features/pdf_editor/presentation/save_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets('save commits IME composition before native materialization', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness(text: 'one two');
    await harness.open(selectionOffset: 4);
    await tester.pumpWidget(harness.widget());
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'one xtwo',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 4, end: 5),
      ),
    );
    await tester.pump();
    expect(harness.gateway.requests, isEmpty);

    await harness.controller.save(
      const EditorSaveRequest(
        targetPath: 'fixture.pdf',
        mode: EditorSaveMode.save,
        association: EditorSaveAssociation.followNewSource,
      ),
    );
    await tester.pump();

    expect(harness.gateway.calls, <String>['submit', 'save']);
    expect(harness.controller.state.save.phase, EditorSavePhase.clean);
    await tester.runAsync(harness.controller.close);
  });

  testWidgets('source conflict offers Save As and rebase', (tester) async {
    var saveAs = 0;
    var rebase = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SaveConflictDialog(
          errorCode: 'source_changed',
          onSaveAs: () => saveAs++,
          onRebase: () => rebase++,
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('Save As'), findsOneWidget);
    expect(find.text('Rebase'), findsOneWidget);
    await tester.tap(find.byKey(const Key('native-save-as')));
    expect(saveAs, 1);
    expect(rebase, 0);
  });

  test(
    'validation failure preserves accepted state and recoverable project',
    () async {
      final harness = NativeEditorTestHarness(text: 'Original');
      await harness.open();
      harness.gateway.saveError = Exception(
        'save_failed:validation_failed:ValidateTemp:invalid output',
      );

      await expectLater(
        harness.controller.save(
          const EditorSaveRequest(
            targetPath: 'fixture.pdf',
            mode: EditorSaveMode.save,
            association: EditorSaveAssociation.followNewSource,
          ),
        ),
        throwsException,
      );

      expect(harness.controller.state.visibleText(harnessObjectId), 'Original');
      expect(harness.controller.state.save.phase, EditorSavePhase.failed);
      expect(harness.controller.state.save.errorCode, 'validation_failed');
      await harness.controller.close();
    },
  );

  testWidgets('locked file offers retry and Save As', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SaveConflictDialog(
          errorCode: 'sharing_violation',
          onRetry: () => retried = true,
          onSaveAs: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Save As'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-native-save')));
    expect(retried, isTrue);
  });

  testWidgets('cancel disables once atomic replacement starts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SaveProgressDialog(stage: 'ReplaceOrMove', onCancel: null),
      ),
    );
    expect(
      tester.widget<TextButton>(find.byKey(const Key('cancel-save'))).onPressed,
      isNull,
    );
  });

  testWidgets('Save As requires an explicit association choice', (
    tester,
  ) async {
    var association = '';
    await tester.pumpWidget(
      MaterialApp(
        home: SaveAsAssociationDialog(
          onKeepOriginal: () => association = 'original',
          onFollowNewSource: () => association = 'copy',
          onCancel: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('follow-new-source')));
    expect(association, 'copy');
  });
}
