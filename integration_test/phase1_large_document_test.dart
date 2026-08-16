import 'dart:async';
import 'dart:io';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/application/editor_session_controller.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 1 large-document scenes remain bounded and measurable', (
    tester,
  ) async {
    final gateway = _LargeDocumentGateway();
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: () => 'unused',
    );
    await controller.open('phase1-large-document.pdf');
    addTearDown(controller.close);
    final samples = <int>[];
    final residentSamples = <int>[];
    final memorySamples = <int>[];

    for (final pages in <Iterable<int>>[
      Iterable<int>.generate(1_000, (index) => index + 1),
      Iterable<int>.generate(1_000, (index) => 1_000 - index),
    ]) {
      for (final page in pages) {
        final stopwatch = Stopwatch()..start();
        await controller.refreshPage(page, force: true);
        samples.add(stopwatch.elapsedMicroseconds);
        if (page % 50 == 0) {
          residentSamples.add(controller.state.scenes.length);
          memorySamples.add(ProcessInfo.currentRss);
        }
      }
    }

    samples.sort();
    final p95 = samples[(samples.length * 0.95).floor()];
    final firstTail = memorySamples[memorySamples.length ~/ 2];
    final finalMemory = memorySamples.last;
    expect(gateway.requestedPages.toSet().length, 1_000);
    expect(gateway.requestedPages.length, 2_001);
    expect(controller.state.scenes.length, lessThanOrEqualTo(8));
    expect(residentSamples.every((sample) => sample <= 8), isTrue);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['phase1LargeDocument'] = <String, Object>{
      'pageCount': 1_000,
      'sceneRequests': gateway.requestedPages.length,
      'p95SceneRequestMicros': p95,
      'residentSceneCount': residentSamples.last,
      'patchBytes': 0,
      'memoryWarmTailBytes': firstTail,
      'memoryFinalBytes': finalMemory,
      'memoryTailGrowthBytes': finalMemory - firstTail,
    };
  });
}

class _LargeDocumentGateway implements EditorSessionGateway {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  final List<int> requestedPages = <int>[];

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      const EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'large-session',
        documentId: 'large-document',
        sourceFingerprint: 'large-fingerprint',
        revision: 0,
        pageCount: 1_000,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async {
    requestedPages.add(pageNumber);
    return EditorPageScene(
      schemaVersion: 1,
      pageId: 'page-$pageNumber',
      pageNumber: pageNumber,
      width: 612,
      height: 792,
      revision: expectedRevision,
      objects: const <EditorSceneObject>[],
    );
  }

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      throw UnimplementedError();
}
