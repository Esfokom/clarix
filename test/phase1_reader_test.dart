import 'dart:io';
import 'dart:ui';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/infrastructure/document_metadata_store.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('trackpad scale is dampened from the gesture start zoom', () {
    final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
    gesture.start(startZoom: 2, anchor: const Offset(420, 315));

    final double? first = gesture.update(
      cumulativeScale: 1.5,
      minZoom: 0.25,
      maxZoom: 8,
    );
    final double? second = gesture.update(
      cumulativeScale: 1.75,
      minZoom: 0.25,
      maxZoom: 8,
    );

    expect(first, closeTo(2.65, 0.000001));
    expect(second, closeTo(2.975, 0.000001));
    expect(gesture.anchor, const Offset(420, 315));
  });

  test('trackpad scale noise remains a pan until zoom is established', () {
    final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
    gesture.start(startZoom: 2, anchor: const Offset(420, 315));

    expect(
      gesture.update(cumulativeScale: 1.009, minZoom: 0.25, maxZoom: 8),
      isNull,
    );
    expect(gesture.isZooming, isFalse);

    expect(
      gesture.update(cumulativeScale: 1.02, minZoom: 0.25, maxZoom: 8),
      isNotNull,
    );
    expect(gesture.isZooming, isTrue);

    expect(
      gesture.update(cumulativeScale: 1.001, minZoom: 0.25, maxZoom: 8),
      isNotNull,
    );
    expect(gesture.isZooming, isTrue);
  });

  test('ending a trackpad zoom clears its locked state', () {
    final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
    gesture.start(startZoom: 2, anchor: const Offset(420, 315));
    gesture.update(cumulativeScale: 1.5, minZoom: 0.25, maxZoom: 8);

    gesture.end();

    expect(gesture.anchor, isNull);
    expect(gesture.isZooming, isFalse);
    expect(
      gesture.update(cumulativeScale: 1.5, minZoom: 0.25, maxZoom: 8),
      isNull,
    );
  });

  test('instrumented focal remains at the pinch-start cursor', () {
    final Offset focal = resolveLockedPointerFocalPoint(
      lockedFocalPoint: const Offset(723.2, 544),
      reportedFocalPoint: const Offset(191.746826171875, 144.234521484375),
    );

    expect(focal, const Offset(723.2, 544));
  });

  test('reader zoom keeps the cursor fixed despite trackpad pan noise', () {
    final Offset anchor = resolveReaderZoomFocalPoint(
      trackedCursorLocal: const Offset(723.2, 544),
      reportedTrackpadFocalPoint: const Offset(
        191.746826171875,
        144.234521484375,
      ),
      viewportSize: const Size(1485.6, 844),
    );

    expect(anchor, const Offset(723.2, 544));
  });

  test(
    'reader zoom prefers the tracked cursor over trackpad focal corners',
    () {
      final Offset anchor = resolveReaderZoomFocalPoint(
        trackedCursorLocal: const Offset(237, 181),
        reportedTrackpadFocalPoint: Offset.zero,
        viewportSize: const Size(800, 600),
      );

      expect(anchor, const Offset(237, 181));
    },
  );

  test('reader zoom rejects a stale cursor outside the viewport', () {
    final Offset anchor = resolveReaderZoomFocalPoint(
      trackedCursorLocal: const Offset(920, 181),
      reportedTrackpadFocalPoint: const Offset(410, 305),
      viewportSize: const Size(800, 600),
    );

    expect(anchor, const Offset(410, 305));
  });

  test('PDF zoom anchor rejects a non-finite viewer conversion', () {
    final Offset anchor = resolvePdfZoomAnchor(
      globalPosition: const Offset(520, 340),
      fallbackLocalPosition: const Offset(400, 300),
      globalToLocal: (_) => const Offset(double.nan, double.infinity),
    );

    expect(anchor, const Offset(400, 300));
  });

  testWidgets('raw trackpad zoom ignores cumulative pan and locks the cursor', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController(zoom: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: ReaderCursorLockedPdfRegion(
            controller: controller,
            builder: (_, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    const Offset cursor = Offset(420, 315);
    final Offset documentPointBefore = controller.documentPointAt(cursor);
    final TestGesture gesture = await tester.startGesture(
      cursor,
      kind: PointerDeviceKind.trackpad,
    );

    await gesture.panZoomUpdate(
      cursor,
      pan: const Offset(-280, -200),
      scale: 1.5,
    );
    await gesture.panZoomUpdate(
      cursor,
      pan: const Offset(-470, -348),
      scale: 1.75,
    );
    await gesture.panZoomEnd();

    expect(controller.zoomCalls, hasLength(2));
    expect(
      controller.zoomCalls.map((_ZoomCall call) => call.localPosition),
      everyElement(cursor),
    );
    expect(controller.zoomCalls.first.newZoom, closeTo(2.65, 0.000001));
    expect(controller.zoomCalls.last.newZoom, closeTo(2.975, 0.000001));
    expect(controller.documentPointAt(cursor), documentPointBefore);
  });

  testWidgets('raw scale noise does not take ownership from trackpad pan', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      const Offset(420, 315),
      kind: PointerDeviceKind.trackpad,
    );

    await gesture.panZoomUpdate(
      const Offset(420, 315),
      pan: const Offset(0, -80),
      scale: 1.009,
    );
    await gesture.panZoomEnd();

    expect(controller.zoomCalls, isEmpty);
  });

  testWidgets(
    'raw trackpad owner pans through scale noise and corrects child pan',
    (WidgetTester tester) async {
      final _RecordingPdfViewerController controller =
          _RecordingPdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderCursorLockedPdfRegion(
            controller: controller,
            builder: (_, _) {
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
                  // This models pdfrx with scale disabled: non-1 scale updates
                  // are discarded, while exact-1 updates mutate its matrix.
                  if (event.scale == 1) {
                    final Matrix4 matrix = controller.value.clone()
                      ..setEntry(
                        0,
                        3,
                        controller.translation.dx + event.panDelta.dx,
                      )
                      ..setEntry(
                        1,
                        3,
                        controller.translation.dy + event.panDelta.dy,
                      );
                    controller.value = matrix;
                  }
                },
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      );
      const Offset cursor = Offset(420, 315);
      final Offset documentPointAtStart = controller.documentPointAt(cursor);
      final TestGesture gesture = await tester.startGesture(
        cursor,
        kind: PointerDeviceKind.trackpad,
      );

      await gesture.panZoomUpdate(
        cursor,
        pan: const Offset(0, -80),
        scale: 1.009,
      );
      expect(controller.translation, const Offset(0, -80));

      await gesture.panZoomUpdate(cursor, pan: const Offset(0, -100), scale: 1);
      expect(controller.translation, const Offset(0, -100));

      await gesture.panZoomUpdate(
        cursor,
        pan: const Offset(0, -130),
        scale: 1.2,
      );
      expect(controller.documentPointAt(cursor), documentPointAtStart);

      await gesture.panZoomUpdate(cursor, pan: const Offset(0, -30), scale: 1);
      await gesture.panZoomEnd();

      expect(controller.zoom, 2);
      expect(controller.translation, Offset.zero);
      expect(controller.documentPointAt(cursor), documentPointAtStart);
    },
  );

  testWidgets('trackpad pan reverses immediately after boundary clamping', (
    WidgetTester tester,
  ) async {
    final _ClampingPdfViewerController controller =
        _ClampingPdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
              if (event.scale == 1) {
                final Matrix4 matrix = controller.value.clone()
                  ..setEntry(
                    1,
                    3,
                    controller.translation.dy + event.panDelta.dy,
                  );
                controller.value = matrix;
              }
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      const Offset(420, 315),
      kind: PointerDeviceKind.trackpad,
    );

    await gesture.panZoomUpdate(
      const Offset(420, 315),
      pan: const Offset(0, -120),
      scale: 1,
    );
    expect(controller.translation.dy, -100);

    await gesture.panZoomUpdate(
      const Offset(420, 315),
      pan: const Offset(0, -115),
      scale: 1,
    );
    await gesture.panZoomEnd();

    expect(controller.translation.dy, -95);
  });

  testWidgets('invalid trackpad scale does not mutate the viewer matrix', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      const Offset(420, 315),
      kind: PointerDeviceKind.trackpad,
    );

    await gesture.panZoomUpdate(
      const Offset(420, 315),
      pan: const Offset(0, -80),
      scale: 0,
    );
    await gesture.panZoomEnd();

    expect(controller.translation, Offset.zero);
    expect(controller.zoomCalls, isEmpty);
  });

  testWidgets('pointer scale zooms incrementally around the cursor', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    const Offset cursor = Offset(420, 315);

    final Offset documentPointBefore = controller.documentPointAt(cursor);

    await tester.sendEventToBinding(
      const PointerScaleEvent(position: cursor, scale: 1.2),
    );
    await tester.pump();
    final double firstFrameZoom = controller.zoom;
    await tester.pumpAndSettle();

    // The zoom is eased towards the target instead of snapping to it, but the
    // cursor stays pinned on every intermediate frame.
    expect(firstFrameZoom, lessThan(2.26));
    expect(controller.zoomCalls.length, greaterThan(1));
    expect(
      controller.zoomCalls.map((_ZoomCall call) => call.localPosition),
      everyElement(cursor),
    );
    expect(controller.zoom, closeTo(2.26, 0.000001));
    expect(controller.documentPointAt(cursor), documentPointBefore);
  });

  testWidgets('Ctrl-wheel zooms while plain wheel remains pdfrx-owned', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    const Offset cursor = Offset(420, 315);

    await tester.sendEventToBinding(
      const PointerScrollEvent(position: cursor, scrollDelta: Offset(0, -120)),
    );
    expect(controller.zoomCalls, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(position: cursor, scrollDelta: Offset(0, -120)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.zoomCalls, isNotEmpty);
    expect(
      controller.zoomCalls.map((_ZoomCall call) => call.localPosition),
      everyElement(cursor),
    );
    expect(controller.zoom, closeTo(2.26, 0.000001));
  });

  testWidgets('a wheel glide eases towards an accumulated target', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    final ReaderViewportMotion motion = ReaderViewportMotion()
      ..attach(controller, const TestVSync());
    addTearDown(motion.detach);
    await tester.pumpWidget(const SizedBox.expand());

    motion.panBy(const Offset(0, -120));
    await tester.pump();

    // The first frame covers part of the notch rather than jumping it.
    expect(controller.translation.dy, lessThan(0));
    expect(controller.translation.dy, greaterThan(-120));

    // A second notch mid-glide extends the same target instead of restarting.
    motion.panBy(const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(controller.translation.dy, closeTo(-240, 0.5));
    expect(motion.isPanning, isFalse);
  });

  testWidgets('a glide clamped at the boundary reverses immediately', (
    WidgetTester tester,
  ) async {
    final _ClampingPdfViewerController controller =
        _ClampingPdfViewerController();
    final ReaderViewportMotion motion = ReaderViewportMotion()
      ..attach(controller, const TestVSync());
    addTearDown(motion.detach);
    await tester.pumpWidget(const SizedBox.expand());

    motion.panBy(const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(controller.translation.dy, -100);

    motion.panBy(const Offset(0, 40));
    await tester.pumpAndSettle();

    // The discarded 300px never has to be paid back.
    expect(controller.translation.dy, closeTo(-60, 0.5));
  });

  testWidgets('adapter zoom signals notify the workspace persistence hook', (
    WidgetTester tester,
  ) async {
    final _RecordingPdfViewerController controller =
        _RecordingPdfViewerController();
    int persistenceRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCursorLockedPdfRegion(
          controller: controller,
          onViewChanged: () => persistenceRequests++,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    const Offset cursor = Offset(420, 315);

    await tester.sendEventToBinding(
      const PointerScaleEvent(position: cursor, scale: 1.2),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(position: cursor, scrollDelta: Offset(0, -120)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Once per input event, plus once when each eased zoom settles on target.
    expect(persistenceRequests, greaterThanOrEqualTo(2));
  });

  test('document metadata round-trips through the sidecar store', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'clarix-metadata-',
    );
    addTearDown(() => root.delete(recursive: true));
    final DocumentMetadataStore store = DocumentMetadataStore(root: root);
    final DocumentIdentity identity = DocumentIdentity(
      fingerprint: 'a' * 64,
      path: r'C:\docs\paper.pdf',
      title: 'paper.pdf',
      byteLength: 512,
      modifiedAt: DateTime.utc(2026, 7, 14),
      pageCount: 4,
      isEncrypted: false,
    );
    final DocumentMetadata metadata = DocumentMetadata(
      identity: identity,
      bookmarks: <DocumentBookmark>[
        DocumentBookmark(
          id: 'bookmark-1',
          pageNumber: 3,
          label: 'Results',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
      annotations: <DocumentAnnotation>[
        DocumentAnnotation(
          id: 'annotation-1',
          kind: AnnotationKind.highlight,
          pageNumber: 2,
          pageRects: const <Rect>[Rect.fromLTWH(10, 20, 100, 14)],
          selectedText: 'local-first',
          note: null,
          colorValue: 0x66FFD54F,
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );

    await store.write(metadata);
    final DocumentMetadata? restored = await store.read(identity.fingerprint);

    expect(restored, isNotNull);
    expect(restored!.identity.path, identity.path);
    expect(restored.bookmarks.single.pageNumber, 3);
    expect(
      restored.annotations.single.pageRects.single,
      const Rect.fromLTWH(10, 20, 100, 14),
    );
  });

  test('document identity is stable when a file is moved', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'clarix-fingerprint-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File first = File('${root.path}${Platform.pathSeparator}one.pdf');
    final File moved = File('${root.path}${Platform.pathSeparator}two.pdf');
    await first.writeAsBytes(List<int>.generate(4096, (int i) => i % 251));

    final DocumentIdentityService identities = DocumentIdentityService();
    final DocumentIdentity before = await identities.identify(first.path);
    await first.rename(moved.path);
    final DocumentIdentity after = await identities.identify(moved.path);

    expect(after.fingerprint, before.fingerprint);
    expect(after.path, moved.path);
  });
}

class _ZoomCall {
  const _ZoomCall(this.localPosition, this.newZoom);

  final Offset localPosition;
  final double newZoom;
}

class _RecordingPdfViewerController extends PdfViewerController {
  _RecordingPdfViewerController({this.zoom = 2});

  double zoom;
  Offset translation = Offset.zero;
  final List<_ZoomCall> zoomCalls = <_ZoomCall>[];

  @override
  Matrix4 get value => Matrix4.identity()
    ..setEntry(0, 0, zoom)
    ..setEntry(1, 1, zoom)
    ..setEntry(0, 3, translation.dx)
    ..setEntry(1, 3, translation.dy);

  @override
  set value(Matrix4 matrix) {
    zoom = matrix.getMaxScaleOnAxis();
    translation = Offset(matrix.entry(0, 3), matrix.entry(1, 3));
  }

  @override
  Matrix4 makeMatrixInSafeRange(Matrix4 newValue, {bool forceClamp = false}) =>
      newValue;

  Offset documentPointAt(Offset localPosition) =>
      (localPosition - translation) / zoom;

  @override
  bool get isReady => true;

  @override
  double get currentZoom => zoom;

  @override
  double get minScale => 0.25;

  @override
  double get maxScale => 8;

  @override
  Size get viewSize => const Size(800, 600);

  @override
  Offset? globalToLocal(Offset global) => global;

  @override
  Future<void> zoomOnLocalPosition({
    required Offset localPosition,
    required double newZoom,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final Offset documentPoint = documentPointAt(localPosition);
    zoomCalls.add(_ZoomCall(localPosition, newZoom));
    zoom = newZoom;
    translation = localPosition - documentPoint * newZoom;
  }
}

class _ClampingPdfViewerController extends _RecordingPdfViewerController {
  @override
  set value(Matrix4 matrix) {
    super.value = makeMatrixInSafeRange(matrix, forceClamp: true);
  }

  @override
  Matrix4 makeMatrixInSafeRange(Matrix4 newValue, {bool forceClamp = false}) {
    final Matrix4 clamped = newValue.clone();
    clamped.setEntry(0, 3, clamped.entry(0, 3).clamp(-100, 100).toDouble());
    clamped.setEntry(1, 3, clamped.entry(1, 3).clamp(-100, 100).toDouble());
    return clamped;
  }
}
