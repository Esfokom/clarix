import 'dart:io';

import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_command_id.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_presentation_state.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/presentation/clean_patch_layer.dart';
import 'package:clarix/src/features/pdf_editor/presentation/editor_hit_test.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_edit_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/phase1_profile_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Phase 1 native typing preserves focus viewport and page identity',
    (tester) async {
      await ClarixRustRuntime.requireInitialized();
      final fixture = phase1CorpusFile(
        'test_fixtures/editing_corpus/generated/standard-latin.pdf',
      );
      final projectRoot = await Directory.systemTemp.createTemp(
        'clarix-phase1-profile-',
      );
      final gateway = BridgeEditorSessionGateway(projectRoot: projectRoot.path);
      final controller = EditorSessionController(
        gateway: gateway,
        commandIds: newEditorCommandId,
      );
      await controller.open(fixture.path);
      final initialRevision = controller.state.revision;
      final scene = controller.state.scenes[1]!;
      final object = scene.objects.firstWhere(
        (candidate) => candidate.capability == 'editable',
      );
      final originalText = object.text!;
      controller.updateSelection(
        EditorSelection(
          objectId: object.objectId,
          range: const EditorTextRange(start: 1, end: 1),
        ),
      );

      final nativePatch = await controller.cleanPatch(object.objectId, 144);
      final patch = (await tester.runAsync(
        () => CleanPatchDecoder.decodeRgba(
          handle: nativePatch.handle,
          objectId: nativePatch.objectId,
          bounds: nativePatch.bounds,
          dpi: nativePatch.dpi,
          bleedPoints: nativePatch.bleedPoints,
          width: nativePatch.width,
          height: nativePatch.height,
          rgbaBytes: nativePatch.rgbaBytes,
        ),
      ))!;
      final scroll = ScrollController(initialScrollOffset: 240);
      final frameTimings = <FrameTiming>[];
      void recordFrames(List<FrameTiming> timings) =>
          frameTimings.addAll(timings);
      SchedulerBinding.instance.addTimingsCallback(recordFrames);
      addTearDown(() async {
        SchedulerBinding.instance.removeTimingsCallback(recordFrames);
        patch.image.dispose();
        scroll.dispose();
        await controller.close();
        if (projectRoot.existsSync()) {
          await projectRoot.delete(recursive: true);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: <Widget>[
              const SizedBox(height: 800),
              KeyedSubtree(
                key: const ValueKey<String>('pdfrx-page-1'),
                child: StreamBuilder(
                  stream: controller.changes,
                  initialData: controller.state,
                  builder: (context, snapshot) {
                    final document = snapshot.data!;
                    return PageEditScene(
                      scene: scene,
                      document: document,
                      displaySize: Size(scene.width, scene.height),
                      cleanPatches: <String, CleanPatchAsset>{
                        object.objectId: patch,
                      },
                      session: controller,
                    );
                  },
                ),
              ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      );
      await tester.pump();
      final editor = find.byKey(const Key('clarix-native-editor'));
      expect(editor, findsOneWidget);
      final focus = tester.widget<TextField>(editor).focusNode!;
      final pageElement = tester.element(
        find.byKey(const ValueKey<String>('pdfrx-page-1')),
      );
      final initialOffset = scroll.offset;
      final commandLatencies = <int>[];
      final localPaintLatencies = <int>[];
      var pageReloadCount = 0;
      var viewportShiftCount = 0;
      var focusChangeCount = 0;
      void recordFocusChange() => focusChangeCount++;
      focus.addListener(recordFocusChange);
      addTearDown(() => focus.removeListener(recordFocusChange));

      for (var index = 0; index < 1_000; index++) {
        final durableStopwatch = Stopwatch()..start();
        final paintStopwatch = Stopwatch()..start();
        await tester.enterText(editor, index.isEven ? 'x' : 'a');
        await tester.pump();
        localPaintLatencies.add(paintStopwatch.elapsedMicroseconds);
        await controller.flushCommands();
        commandLatencies.add(durableStopwatch.elapsedMicroseconds);
        if (scroll.offset != initialOffset) viewportShiftCount++;
        if (!identical(
          pageElement,
          tester.element(find.byKey(const ValueKey<String>('pdfrx-page-1'))),
        )) {
          pageReloadCount++;
        }
      }
      final beforeComposition = controller.state.revision;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'text',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      await tester.pump();
      expect(controller.state.revision, beforeComposition);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'text',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange.empty,
        ),
      );
      await controller.flushCommands();
      await tester.pump();
      expect(controller.state.revision, beforeComposition + 1);

      final sceneObject = controller.state.scenes[1]!.objects.firstWhere(
        (candidate) => candidate.objectId == object.objectId,
      );
      final hitIndex = EditorHitTestIndex(
        pageSize: Size(scene.width, scene.height),
        displaySize: Size(scene.width, scene.height),
        objects: <EditorObjectHitGeometry>[
          EditorObjectHitGeometry.fromObject(sceneObject),
        ],
      );
      final caretLatencies = <int>[];
      for (var index = 0; index < 10_000; index++) {
        final caretTimer = Stopwatch()..start();
        hitIndex.hitTest(Offset((index % 100).toDouble(), scene.height - 10));
        caretLatencies.add(caretTimer.elapsedMicroseconds);
      }
      await controller.undo();
      await controller.redo();

      final outputPath =
          Platform.environment['CLARIX_PHASE1_PROFILE_OUTPUT'] ??
          '${Directory.current.path}${Platform.pathSeparator}build'
              '${Platform.pathSeparator}editing_phase1'
              '${Platform.pathSeparator}profile-saved.pdf';
      final output = File(outputPath);
      await output.parent.create(recursive: true);
      final saveResult = await controller.save(
        EditorSaveRequest(
          targetPath: output.path,
          mode: EditorSaveMode.saveAs,
          association: EditorSaveAssociation.keepOriginalAssociation,
        ),
      );
      await tester.pump();

      final expectedRevision = initialRevision + 1_003;
      expect(controller.state.revision, expectedRevision);
      expect(saveResult.materializedRevision, expectedRevision);
      expect(output.existsSync(), isTrue);
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, initialOffset);
      expect(focusChangeCount, 0);
      expect(pageReloadCount, 0);
      expect(viewportShiftCount, 0);
      expect(
        identical(
          pageElement,
          tester.element(find.byKey(const ValueKey<String>('pdfrx-page-1'))),
        ),
        isTrue,
      );

      final buildMicros = frameTimings
          .map((timing) => timing.buildDuration.inMicroseconds)
          .toList();
      final rasterMicros = frameTimings
          .map((timing) => timing.rasterDuration.inMicroseconds)
          .toList();
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['phase1Editing'] = <String, Object>{
        'commands': 1_003,
        'p95LocalPaintMicros': percentile95(localPaintLatencies),
        'p95CommandRoundTripMicros': percentile95(commandLatencies),
        'p95FrameBuildMicros': percentile95(buildMicros),
        'p95FrameRasterMicros': percentile95(rasterMicros),
        'frames': frameTimings.length,
        'pageReloadCount': pageReloadCount,
        'viewportShiftCount': viewportShiftCount,
        'focusChangeCount': focusChangeCount,
        'initialRevision': initialRevision,
        'finalRevision': controller.state.revision,
        'imeCompositionCommits': 1,
        'undoRedoCommands': 2,
        'warmCaretLookups': 10_000,
        'p95WarmCaretLookupMicros': percentile95(caretLatencies),
        'cleanPatchBytes': nativePatch.rgbaBytes.length,
        'savedPdfPath': output.absolute.path,
        'expectedText': 'text',
        'oldText': originalText,
      };
    },
  );
}
