import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/app.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart';
import 'package:clarix/src/features/workspace/presentation/screens/workspace_screen.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('Clarix launches directly into the workspace', (tester) async {
    final SharedPreferencesAsyncPlatform? previousPreferencesPlatform =
        SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(
      () =>
          SharedPreferencesAsyncPlatform.instance = previousPreferencesPlatform,
    );
    tester.view.physicalSize = const Size(1500, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ClarixApp());
    await tester.pump();
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(find.byType(ReaderDiagnosticsHub), findsNothing);
  });

  test('workspace session round-trips through json', () {
    final session = WorkspaceSession.initial().copyWith(
      tabs: <DocumentTabState>[
        DocumentTabState.create(
          id: 'tab-1',
          documentId: 'doc-1',
          filePath: 'C:/docs/report.pdf',
          title: 'report.pdf',
        ).copyWith(currentPage: 8),
      ],
      activeTabId: 'tab-1',
    );
    final restored = WorkspaceSession.fromJson(session.toJson());
    expect(restored.activeTabId, 'tab-1');
    expect(restored.tabs.single.currentPage, 8);
  });

  test('vertical PDF scrollbar geometry matches visible document ratio', () {
    final geometry = calculatePdfScrollbarGeometry(
      axis: PdfScrollbarAxis.vertical,
      viewportSize: const Size(800, 600),
      visibleRect: const Rect.fromLTWH(0, 250, 800, 500),
      documentSize: const Size(800, 2000),
    );
    expect(geometry, isNotNull);
    expect(geometry!.thumbExtent, 150);
    expect(geometry.thumbLeading, closeTo(75, 0.001));
  });

  test('PDF zoom anchor falls back to center when conversion fails', () {
    expect(
      resolvePdfZoomAnchor(
        globalPosition: const Offset(520, 340),
        fallbackLocalPosition: const Offset(400, 300),
        globalToLocal: (_) => null,
      ),
      const Offset(400, 300),
    );
  });
}
