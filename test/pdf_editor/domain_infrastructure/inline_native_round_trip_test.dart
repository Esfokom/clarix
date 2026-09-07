import 'dart:io';

import 'package:clarix/src/core/ffi/frb_generated.dart';
import 'package:clarix/src/core/ffi/editing_api.dart' as native;
import 'package:clarix/src/core/editing/editor_bridge.dart';
import 'package:clarix/src/core/editing/editor_command_id.dart';
import 'package:clarix/src/core/editing/frb_native_editor_port.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pdf_text_fixture.dart';

void main() {
  final library = File(
    'rust/target/x86_64-pc-windows-msvc/release/clarix_pdf_oxide.dll',
  );
  test(
    'real editor typing, geometry, history and save round trip',
    () async {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(library.absolute.path),
      );
      final file = await PdfTextFixture.singleBlock('Hello world');
      final root = await Directory.systemTemp.createTemp(
        'clarix-inline-roundtrip-',
      );
      final controller = EditorSessionController(
        gateway: BridgeEditorSessionGateway.forTest(
          projectRoot: root.path,
          openLivePdfiumSession: LivePdfiumSession.open,
          openBridgeSession: (sourcePath, {projectRoot}) async =>
              EditorBridgeSession.forTest(
                FrbNativeEditorPort(
                  await native.NativeEditorSession.openLivePdfium(
                    request: native.NativeOpenEditorRequest(
                      sourcePath: sourcePath,
                      projectRoot: projectRoot,
                    ),
                  ),
                ),
              ),
        ),
        commandIds: newEditorCommandId,
      );
      addTearDown(() async {
        await controller.close();
        await file.parent.delete(recursive: true);
        // Rust opaque handles can keep the journal open until finalization.
        // Windows releases it when this test process exits.
        try {
          await root.delete(recursive: true);
        } on FileSystemException {}
      });
      await controller.open(file.path);
      final object = controller.state.scenes[1]!.objects.single;
      expect(object.characterBoxes, isNotEmpty);
      controller.applyLocalDelta(
        objectId: object.objectId,
        range: const EditorTextRange(start: 0, end: 5),
        replacement: 'Goodbye',
      );
      await controller.flushCommands();
      expect(controller.state.errorCode, isNull);
      expect(controller.state.scenes[1]!.objects.single.text, 'Goodbye world');
      await controller.undo();
      expect(controller.state.visibleText(object.objectId), 'Hello world');
      await controller.redo();
      expect(controller.state.visibleText(object.objectId), 'Goodbye world');
      await controller.submitCommand(
        EditorCommand(
          kind: EditorCommandKind.moveObject,
          objectId: object.objectId,
          transform: const EditorAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: 1,
            e: 20,
            f: -10,
          ),
        ),
      );
      expect(controller.state.errorCode, isNull);
      final moved = controller.state.scenes[1]!.objects.single;
      expect(moved.transform.e, 20);
      await controller.submitCommand(
        EditorCommand(
          kind: EditorCommandKind.rotateObject,
          objectId: object.objectId,
          radians: 0.1,
          centerX: moved.bounds.left,
          centerY: moved.bounds.bottom,
        ),
      );
      await controller.undo();
      final output = File('${root.path}/saved.pdf');
      await controller.save(
        EditorSaveRequest(
          targetPath: output.path,
          mode: EditorSaveMode.saveAs,
          association: EditorSaveAssociation.keepOriginalAssociation,
        ),
      );
      final reopened = await LivePdfiumSession.open(output.path);
      try {
        final blocks = await reopened.inspectTextBlocks(
          sourceRevision: 'saved',
          pageNumbers: [1],
        );
        expect(blocks.single.text.trimRight(), 'Goodbye world');
      } finally {
        await reopened.close();
      }
    },
    skip: !Platform.isWindows || !library.existsSync()
        ? 'Requires the existing Windows debug runtime; does not build Rust.'
        : false,
  );
}
