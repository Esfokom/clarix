import 'dart:io';
import 'dart:math' as math;

import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/core/editing/editor_command_id.dart';
import 'package:clarix/src/features/workspace/editing/application/editor_session_controller.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/phase1_profile_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 1 native large-document scenes remain bounded', (
    tester,
  ) async {
    await ClarixRustRuntime.requireInitialized();
    final projectRoot = await Directory.systemTemp.createTemp(
      'clarix-phase1-large-',
    );
    final source = await writeBlankPdfCorpus(projectRoot, 1_000);
    final controller = EditorSessionController(
      gateway: BridgeEditorSessionGateway(projectRoot: projectRoot.path),
      commandIds: newEditorCommandId,
      maxResidentScenes: 8,
    );
    await controller.open(source.path);
    expect(controller.state.pageCount, 1_000);

    final scroll = ScrollController();
    final frameTimings = <FrameTiming>[];
    void recordFrames(List<FrameTiming> timings) =>
        frameTimings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(recordFrames);
    addTearDown(() async {
      SchedulerBinding.instance.removeTimingsCallback(recordFrames);
      scroll.dispose();
      await controller.close();
      if (projectRoot.existsSync()) {
        await projectRoot.delete(recursive: true);
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: scroll,
          itemExtent: 24,
          itemCount: 1_000,
          itemBuilder: (context, index) => SizedBox(
            key: ValueKey<String>('phase1-large-page-${index + 1}'),
            height: 24,
          ),
        ),
      ),
    );
    await tester.pump();

    final indexedSceneLatencies = <int>[];
    final unindexedSceneLatencies = <int>[];
    final residentSamples = <int>[];
    final memorySamples = <int>[];
    final visited = <int>{};
    var sceneRequests = 1; // EditorSessionController.open requests page one.
    for (final (pass, pages) in <Iterable<int>>[
      Iterable<int>.generate(1_000, (index) => index + 1),
      Iterable<int>.generate(1_000, (index) => 1_000 - index),
    ].indexed) {
      for (final page in pages) {
        final stopwatch = Stopwatch()..start();
        await controller.refreshPage(page, force: true);
        final elapsed = stopwatch.elapsedMicroseconds;
        if (pass == 0 && page != 1) {
          unindexedSceneLatencies.add(elapsed);
        } else {
          indexedSceneLatencies.add(elapsed);
        }
        sceneRequests++;
        visited.add(page);
        final targetOffset = math.min(
          (page - 1) * 24.0,
          scroll.position.maxScrollExtent,
        );
        scroll.jumpTo(targetOffset);
        await tester.pump();
        if (page % 50 == 0) {
          residentSamples.add(controller.state.scenes.length);
          memorySamples.add(ProcessInfo.currentRss);
        }
      }
    }

    final memoryWarmTail = memorySamples[memorySamples.length ~/ 2];
    final memoryFinal = memorySamples.last;
    expect(visited.length, 1_000);
    expect(sceneRequests, 2_001);
    expect(unindexedSceneLatencies.length, 999);
    expect(indexedSceneLatencies.length, 1_001);
    expect(controller.state.scenes.length, lessThanOrEqualTo(8));
    expect(residentSamples.every((sample) => sample <= 8), isTrue);

    final frameBuildMicros = frameTimings
        .map((timing) => timing.buildDuration.inMicroseconds)
        .toList();
    final frameRasterMicros = frameTimings
        .map((timing) => timing.rasterDuration.inMicroseconds)
        .toList();
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['phase1LargeDocument'] = <String, Object>{
      'pageCount': 1_000,
      'sceneRequests': sceneRequests,
      'p95IndexedSceneRequestMicros': percentile95(indexedSceneLatencies),
      'p95UnindexedSceneRequestMicros': percentile95(unindexedSceneLatencies),
      'p95FrameBuildMicros': percentile95(frameBuildMicros),
      'p95FrameRasterMicros': percentile95(frameRasterMicros),
      'frames': frameTimings.length,
      'residentSceneCount': residentSamples.last,
      'patchBytes': 0,
      'memoryWarmTailBytes': memoryWarmTail,
      'memoryFinalBytes': memoryFinal,
      'memoryTailGrowthBytes': memoryFinal - memoryWarmTail,
    };
  });
}
