import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_scene_host.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'scrolling requests visible page plus two warm pages each way',
    (tester) async {
      final gateway = LifecycleGateway(pageCount: 500);
      final controller = EditorSessionController(
        gateway: gateway,
        commandIds: () => 'unused',
      );
      await controller.open('fixture.pdf');
      final surface = LifecycleSurface();
      final lifecycle = PageSceneLifecycle(
        surface: surface,
        controller: controller,
      )..start();

      await tester.pumpWidget(
        MaterialApp(home: PageSceneHost(lifecycle: lifecycle, pageNumber: 137)),
      );
      surface.show(137);
      await tester.pump();
      await tester.pump();

      expect(
        gateway.requestedPages,
        containsAll(<int>[135, 136, 137, 138, 139]),
      );
      expect(gateway.priorities[137], EditorViewportPriority.visible);
      expect(gateway.priorities[135], EditorViewportPriority.preload);
      expect(
        find.byKey(const ValueKey<String>('page-edit-scene-137')),
        findsOneWidget,
      );

      surface.show(140);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('page-edit-scene-137')),
        findsNothing,
      );
      expect(controller.state.scenes[137], isNotNull);

      for (var page = 1; page <= 20; page += 1) {
        await controller.refreshPage(page, force: true);
      }
      expect(controller.state.scenes.length, lessThanOrEqualTo(8));
      expect(controller.state.scenes[20], isNotNull);

      lifecycle.dispose();
      surface.dispose();
      await tester.runAsync(controller.close);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}

class LifecycleSurface extends ChangeNotifier implements PageSurface {
  final Object _identity = Object();
  PageSurfaceViewport _viewport = PageSurfaceViewport.empty();

  void show(int pageNumber) {
    _viewport = PageSurfaceViewport(
      visiblePages: <int>{pageNumber},
      visibleDocumentRect: Rect.fromLTWH(0, pageNumber * 800, 600, 800),
      zoom: 1,
      anchorPage: pageNumber,
    );
    notifyListeners();
  }

  @override
  Object get identity => _identity;

  @override
  PageSurfaceViewport get viewport => _viewport;

  @override
  Offset documentToPage(int pageNumber, Offset documentOffset) =>
      documentOffset;

  @override
  Rect pageRect(int pageNumber) => Rect.fromLTWH(0, pageNumber * 800, 600, 800);

  @override
  Size pageSize(int pageNumber) => const Size(600, 800);

  @override
  Offset pageToDocument(int pageNumber, Offset pageOffset) => pageOffset;

  @override
  Future<void> showPage(int pageNumber) async => show(pageNumber);
}

class LifecycleGateway implements EditorSessionGateway {
  LifecycleGateway({required this.pageCount});

  final int pageCount;
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  final List<int> requestedPages = <int>[];
  final Map<int, EditorViewportPriority> priorities =
      <int, EditorViewportPriority>{};

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'session',
        documentId: 'document',
        sourceFingerprint: 'fingerprint',
        revision: 0,
        pageCount: pageCount,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async {
    requestedPages.add(pageNumber);
    priorities[pageNumber] = priority;
    return EditorPageScene(
      schemaVersion: 1,
      pageId: 'page-$pageNumber',
      pageNumber: pageNumber,
      width: 600,
      height: 800,
      revision: expectedRevision,
      objects: const <EditorSceneObject>[],
    );
  }

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
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
