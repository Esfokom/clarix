import 'package:clarix/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostic_crosshair.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostics_event_panel.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  testWidgets(
    'viewer chrome supplies Material controls without resizing its viewer',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            key: const Key('diagnostic-viewer-host'),
            child: DiagnosticViewerChrome(
              viewer: const ColoredBox(color: Colors.blue),
              status: 'Testing viewer chrome',
              onBack: () {},
              onOpenPdf: () {},
            ),
          ),
        ),
      );

      final Finder surface = find.byKey(const Key('diagnostic-viewer-surface'));
      final Rect hostRect = tester.getRect(
        find.byKey(const Key('diagnostic-viewer-host')),
      );

      expect(tester.getRect(surface), hostRect);
      expect(
        find.ancestor(
          of: find.byKey(const Key('diagnostic-back')),
          matching: find.byType(Material),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('diagnostic-chrome-toggle')));
      await tester.pump();

      expect(find.byKey(const Key('diagnostic-chrome-controls')), findsNothing);
      expect(tester.getRect(surface), hostRect);

      await tester.tap(find.byKey(const Key('diagnostic-chrome-toggle')));
      await tester.pump();

      expect(
        find.byKey(const Key('diagnostic-chrome-controls')),
        findsOneWidget,
      );
      expect(tester.getRect(surface), hostRect);
    },
  );
  testWidgets('stock viewer stays empty when picking is cancelled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: StockPdfrxScreen(pickPdf: () async => null)),
    );

    await tester.tap(find.byKey(const Key('stock-open-pdf')));
    await tester.pump();

    expect(
      find.text('Open a PDF to test stock pdfrx input behavior.'),
      findsOneWidget,
    );
    expect(find.byType(PdfViewer), findsNothing);
  });

  testWidgets('stock viewer uses the shared cursor-locked PDF input', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StockPdfrxScreen(pickPdf: () async => 'C:/fixtures/sample.pdf'),
      ),
    );

    await tester.tap(find.byKey(const Key('stock-open-pdf')));
    await tester.pump();

    expect(find.byType(ReaderCursorLockedPdfRegion), findsOneWidget);
    final PdfViewer viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(
      viewer.params.interactionDelegateProvider,
      isA<ReaderCursorAnchoredInteractionDelegateProvider>(),
    );
    expect(viewer.params.normalizeMatrix, isNotNull);
  });

  testWidgets('instrumented viewer uses the shared cursor-locked PDF input', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InstrumentedPdfrxScreen(
          pickPdf: () async => 'C:/fixtures/sample.pdf',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stock-open-pdf')));
    await tester.pump();

    expect(find.byType(ReaderCursorLockedPdfRegion), findsOneWidget);
    final PdfViewer viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(
      viewer.params.interactionDelegateProvider,
      isA<ReaderCursorAnchoredInteractionDelegateProvider>(),
    );
    expect(viewer.params.normalizeMatrix, isNotNull);
  });
  testWidgets('stock screen exposes only minimal control chrome', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: StockPdfrxScreen(pickPdf: () async => null)),
    );

    expect(find.byKey(const Key('diagnostic-back')), findsOneWidget);
    expect(find.byKey(const Key('stock-open-pdf')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics-event-panel')), findsNothing);
  });

  testWidgets('stock viewer can hide chrome without resizing its surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: StockPdfrxScreen(pickPdf: () async => null)),
    );
    final Rect before = tester.getRect(
      find.byKey(const Key('diagnostic-viewer-surface')),
    );

    await tester.tap(find.byKey(const Key('diagnostic-chrome-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('diagnostic-chrome-controls')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('diagnostic-viewer-surface'))),
      before,
    );
  });

  testWidgets('instrumented viewer stays empty when picking is cancelled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: InstrumentedPdfrxScreen(pickPdf: () async => null)),
    );

    await tester.tap(find.byKey(const Key('stock-open-pdf')));
    await tester.pump();

    expect(
      find.text('Open a PDF to inspect raw pdfrx input behavior.'),
      findsOneWidget,
    );
    expect(find.byType(PdfViewer), findsNothing);
  });

  testWidgets(
    'instrumented viewer can hide chrome without resizing its surface',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: InstrumentedPdfrxScreen(pickPdf: () async => null)),
      );
      final Rect before = tester.getRect(
        find.byKey(const Key('diagnostic-viewer-surface')),
      );

      await tester.tap(find.byKey(const Key('diagnostic-chrome-toggle')));
      await tester.pump();

      expect(find.byKey(const Key('diagnostic-chrome-controls')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('diagnostic-viewer-surface'))),
        before,
      );
    },
  );

  testWidgets('event panel pauses clears collapses and copies JSON', (
    WidgetTester tester,
  ) async {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleStart,
    );
    String copied = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticsEventPanel(
            recorder: recorder,
            copyText: (String value) async => copied = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('diagnostics-pause')));
    expect(recorder.paused.value, isTrue);

    await tester.tap(find.byKey(const Key('diagnostics-copy')));
    expect(copied, contains('scaleStart'));

    await tester.tap(find.byKey(const Key('diagnostics-clear')));
    expect(recorder.events.value, isEmpty);

    await tester.tap(find.byKey(const Key('diagnostics-collapse')));
    await tester.pump();
    expect(find.byKey(const Key('diagnostics-event-list')), findsNothing);
  });

  testWidgets('event panel surfaces the evicted event count', (
    WidgetTester tester,
  ) async {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      capacity: 2,
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);
    for (int index = 0; index < 3; index++) {
      recorder.record(
        source: ReaderDiagnosticSource.pointerListener,
        type: ReaderDiagnosticEventType.pointerMove,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiagnosticsEventPanel(recorder: recorder)),
      ),
    );

    expect(find.text('2 buffered · 1 evicted'), findsOneWidget);
  });

  testWidgets('cursor and focal crosshairs are independently positioned', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DiagnosticCrosshairOverlay(
            cursor: Offset(70, 80),
            focal: Offset(250, 190),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('cursor-crosshair')), findsOneWidget);
    expect(find.byKey(const Key('focal-crosshair')), findsOneWidget);
  });

  testWidgets('event panel renders only the newest 100 in newest-first order', (
    WidgetTester tester,
  ) async {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);
    for (int index = 0; index < 105; index++) {
      recorder.record(
        source: ReaderDiagnosticSource.pointerListener,
        type: ReaderDiagnosticEventType.pointerMove,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiagnosticsEventPanel(recorder: recorder)),
      ),
    );

    final ListView listView = tester.widget<ListView>(find.byType(ListView));
    final SliverChildBuilderDelegate delegate =
        listView.childrenDelegate as SliverChildBuilderDelegate;
    final BuildContext listContext = tester.element(find.byType(ListView));
    final Widget first = delegate.builder(listContext, 0)!;
    final Widget last = delegate.builder(listContext, 99)!;

    expect(delegate.estimatedChildCount, 100);
    expect(first.key, const Key('diagnostics-event-105'));
    expect(last.key, const Key('diagnostics-event-6'));
  });

  testWidgets('pointer lab renders four quadrants and separate markers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PointerTrackpadLabScreen()),
    );
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(find.text('Q3'), findsOneWidget);
    expect(find.text('Q4'), findsOneWidget);
    expect(find.byKey(const Key('pointer-lab-canvas')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics-event-panel')), findsOneWidget);
  });

  testWidgets('pointer lab hides overlays without resizing its canvas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PointerTrackpadLabScreen()),
    );
    final Rect before = tester.getRect(
      find.byKey(const Key('pointer-lab-canvas')),
    );

    await tester.tap(find.byKey(const Key('pointer-lab-overlays-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('diagnostics-event-panel')), findsNothing);
    expect(find.byKey(const Key('pointer-lab-back')), findsNothing);
    expect(tester.getRect(find.byKey(const Key('pointer-lab-canvas'))), before);
  });

  testWidgets('pointer lab panel pauses clears and copies its recorder', (
    WidgetTester tester,
  ) async {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);
    recorder.record(
      source: ReaderDiagnosticSource.pointerListener,
      type: ReaderDiagnosticEventType.scaleStart,
    );
    String copied = '';

    await tester.pumpWidget(
      MaterialApp(
        home: PointerTrackpadLabScreen(
          recorder: recorder,
          copyDiagnosticsText: (String value) async => copied = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('diagnostics-pause')));
    expect(recorder.paused.value, isTrue);

    await tester.tap(find.byKey(const Key('diagnostics-copy')));
    expect(copied, contains('scaleStart'));

    await tester.tap(find.byKey(const Key('diagnostics-clear')));
    expect(recorder.events.value, isEmpty);
  });

  testWidgets('hover moves cursor without moving focal marker', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PointerTrackpadLabScreen()),
    );
    final TestGesture gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(80, 90));
    await gesture.moveTo(const Offset(140, 150));
    await tester.pump();
    final Positioned cursor = tester.widget<Positioned>(
      find.byKey(const Key('cursor-crosshair')),
    );
    final Positioned focal = tester.widget<Positioned>(
      find.byKey(const Key('focal-crosshair')),
    );
    expect(cursor.left, isNot(focal.left));
    await gesture.removePointer();
  });

  test('pointer lab state keeps trackpad device kind for pan-zoom records', () {
    const PointerLabState original = PointerLabState(
      cursor: Offset(64, 96),
      focal: Offset(240, 180),
    );

    final PointerLabState updated = original.withDeviceKind(
      PointerDeviceKind.trackpad,
    );

    expect(updated.deviceKind, 'trackpad');
    expect(updated.cursor, original.cursor);
    expect(updated.focal, original.focal);
    expect(
      ReaderDiagnosticDeviceKind.fromRaw(updated.deviceKind),
      ReaderDiagnosticDeviceKind.trackpad,
    );
  });
}
