import 'package:clarix/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
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
}
