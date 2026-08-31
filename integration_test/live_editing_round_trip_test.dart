import 'dart:io';

import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_command_id.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/presentation/session_text_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing mutates saved PDF bytes and reopened text', (
    tester,
  ) async {
    await ClarixRustRuntime.requireInitialized();
    final fixture = File(
      '${Directory.current.path}${Platform.pathSeparator}'
      'test_fixtures${Platform.pathSeparator}editing_corpus${Platform.pathSeparator}'
      'generated${Platform.pathSeparator}standard-latin.pdf',
    );
    final root = await Directory.systemTemp.createTemp(
      'clarix-live-round-trip-',
    );
    final output = File('${root.path}${Platform.pathSeparator}edited.pdf');
    final controller = EditorSessionController(
      gateway: BridgeEditorSessionGateway(projectRoot: root.path),
      commandIds: newEditorCommandId,
    );
    addTearDown(() async {
      await controller.close();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    await controller.open(fixture.path);
    final object = controller.state.scenes[1]!.objects.firstWhere(
      (candidate) =>
          candidate.capability == 'editable' && candidate.text!.isNotEmpty,
    );
    final original = object.text!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamBuilder(
            stream: controller.changes,
            initialData: controller.state,
            builder: (context, snapshot) {
              final document = snapshot.data!;
              final currentObject = document.scenes[1]!.objects.firstWhere(
                (candidate) => candidate.objectId == object.objectId,
              );
              return SessionTextInput(
                session: controller,
                object: currentObject,
                text:
                    document.visibleText(currentObject.objectId) ??
                    currentObject.text ??
                    '',
                selection: EditorSelection(
                  objectId: currentObject.objectId,
                  range: const EditorTextRange(start: 1, end: 1),
                ),
                onSelectionChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('session-text-input')), findsOneWidget);

    // The input client receives a deletion first, then a replacement keystroke.
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: original.substring(1),
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
    await controller.flushCommands();
    await tester.pump();
    // A semantic-only checkpoint advances the Rust revision without applying
    // PDFium operations. The following keypress proves the live revision was
    // acknowledged before the physical edit is prepared.
    await controller.submitCommand(
      const EditorCommand(kind: EditorCommandKind.createCheckpoint),
    );
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: 'x${original.substring(1)}',
        selection: const TextSelection.collapsed(offset: 1),
      ),
    );
    await controller.flushCommands();
    await tester.pump();
    expect(controller.state.errorCode, isNull);
    await controller.undo();
    await controller.redo();
    await controller.flushCommands();

    await controller.save(
      EditorSaveRequest(
        targetPath: output.path,
        mode: EditorSaveMode.saveAs,
        association: EditorSaveAssociation.keepOriginalAssociation,
      ),
    );
    expect(output.existsSync(), isTrue);

    final reopened = EditorSessionController(
      gateway: BridgeEditorSessionGateway(projectRoot: root.path),
      commandIds: newEditorCommandId,
    );
    addTearDown(reopened.close);
    await reopened.open(output.path);
    final savedText = reopened.state.scenes[1]!.objects
        .firstWhere((candidate) => candidate.objectId == object.objectId)
        .text;
    expect(savedText, isNot(original));
    expect(savedText, startsWith('x'));
  });
}
