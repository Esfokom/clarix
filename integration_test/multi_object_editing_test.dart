import 'dart:io';

import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_command_id.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_presentation_state.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'support/phase1_profile_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multi-object corpus blocks import, edit, undo, and save', (
    tester,
  ) async {
    await ClarixRustRuntime.requireInitialized();
    final fixture = phase1CorpusFile(
      'test_fixtures/editing_corpus/generated/multi-run-text.pdf',
    );
    final projectRoot = await Directory.systemTemp.createTemp(
      'clarix-multi-object-corpus-',
    );
    final gateway = BridgeEditorSessionGateway(projectRoot: projectRoot.path);
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: newEditorCommandId,
    );
    addTearDown(() async {
      await controller.close();
      if (projectRoot.existsSync()) {
        await projectRoot.delete(recursive: true);
      }
    });
    await controller.open(fixture.path);

    final scene = controller.state.scenes[1]!;
    final editable = scene.objects
        .where((object) => object.capability == 'editable')
        .toList(growable: false);
    expect(editable, isNotEmpty, reason: 'corpus page 1 must import text');

    await _backspaceTypeUndoSave(
      controller,
      object: editable.first,
      outputName: 'multi-object-corpus-saved.pdf',
    );
  });

  testWidgets('deterministic multi-object block edits end-to-end', (
    tester,
  ) async {
    await ClarixRustRuntime.requireInitialized();
    final fixture = await _writeTwoObjectLinePdf();
    addTearDown(() => fixture.parent.delete(recursive: true));
    final projectRoot = await Directory.systemTemp.createTemp(
      'clarix-multi-object-synthetic-',
    );
    final gateway = BridgeEditorSessionGateway(projectRoot: projectRoot.path);
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: newEditorCommandId,
    );
    addTearDown(() async {
      await controller.close();
      if (projectRoot.existsSync()) {
        await projectRoot.delete(recursive: true);
      }
    });
    await controller.open(fixture.path);

    final scene = controller.state.scenes[1]!;
    final joined = scene.objects.firstWhere(
      (object) =>
          object.capability == 'editable' && object.text == 'Hello world',
      orElse: () => throw StateError(
        'expected a joined multi-object block, got: '
        '${scene.objects.map((object) => object.text).toList()}',
      ),
    );

    await _backspaceTypeUndoSave(
      controller,
      object: joined,
      outputName: 'multi-object-synthetic-saved.pdf',
    );
  });
}

/// Backspaces the last character, types a marker at the start, saves, verifies
/// the saved bytes carry the edits, then undoes back to the original text.
Future<void> _backspaceTypeUndoSave(
  EditorSessionController controller, {
  required EditorSceneObject object,
  required String outputName,
}) async {
  final originalText = object.text!;
  final initialRevision = controller.state.revision;

  // Backspace: delete the final character of the block.
  controller.updateSelection(
    EditorSelection(
      objectId: object.objectId,
      range: EditorTextRange(start: originalText.length, end: originalText.length),
    ),
  );
  controller.applyLocalDelta(
    objectId: object.objectId,
    range: EditorTextRange(
      start: originalText.length - 1,
      end: originalText.length,
    ),
    replacement: '',
  );
  await controller.flushCommands();
  expect(controller.state.revision, initialRevision + 1);
  expect(
    controller.state.objects[object.objectId]!.acceptedText,
    originalText.substring(0, originalText.length - 1),
  );

  // Type: insert a marker at the start of the block.
  controller.applyLocalDelta(
    objectId: object.objectId,
    range: const EditorTextRange(start: 0, end: 0),
    replacement: 'Z',
  );
  await controller.flushCommands();
  final editedText = 'Z${originalText.substring(0, originalText.length - 1)}';
  expect(controller.state.objects[object.objectId]!.acceptedText, editedText);

  // Save and confirm the marker landed in the physical document.
  final outputPath =
      '${Directory.systemTemp.createTempSync('clarix-multi-object-out-').path}'
      '${Platform.pathSeparator}$outputName';
  final saveResult = await controller.save(
    EditorSaveRequest(
      targetPath: outputPath,
      mode: EditorSaveMode.saveAs,
      association: EditorSaveAssociation.keepOriginalAssociation,
    ),
  );
  expect(saveResult.materializedRevision, controller.state.revision);
  final saved = File(outputPath);
  expect(saved.existsSync(), isTrue);
  addTearDown(() {
    if (saved.existsSync()) saved.deleteSync();
  });

  final session = await LivePdfiumSession.open(saved.path);
  try {
    final blocks = await session.inspectTextBlocks(
      sourceRevision: 'inspect',
      pageNumbers: const <int>[1],
    );
    final pageText = blocks.map((block) => block.text).join('\n');
    expect(pageText.trimRight(), contains(editedText.trimRight()));
  } finally {
    await session.close();
  }

  // Undo twice: the typed marker, then the backspace.
  await controller.undo();
  await controller.undo();
  expect(controller.state.objects[object.objectId]!.acceptedText, originalText);
}

Future<File> _writeTwoObjectLinePdf() async {
  final directory = await Directory.systemTemp.createTemp(
    'clarix-multi-object-line-',
  );
  final file = File('${directory.path}${Platform.pathSeparator}line.pdf');
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Align(
        alignment: pw.Alignment.topLeft,
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: <pw.Widget>[
            pw.Text('Hello', style: const pw.TextStyle(fontSize: 12)),
            pw.Text('world', style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
  await file.writeAsBytes(await document.save(), flush: true);
  return file;
}
