import 'package:clarix/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hub exposes all four diagnostic destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderDiagnosticsHub()));

    expect(find.byKey(const Key('open-stock-pdfrx')), findsOneWidget);
    expect(find.byKey(const Key('open-instrumented-pdfrx')), findsOneWidget);
    expect(find.byKey(const Key('open-pointer-lab')), findsOneWidget);
    expect(find.byKey(const Key('open-workspace')), findsOneWidget);
  });

  testWidgets('hub opens stock viewer and returns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderDiagnosticsHub()));

    await tester.tap(find.byKey(const Key('open-stock-pdfrx')));
    await tester.pumpAndSettle();
    expect(find.byType(StockPdfrxScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('diagnostic-back')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDiagnosticsHub), findsOneWidget);
  });

  testWidgets('hub opens the injected workspace destination and returns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderDiagnosticsHub(
          workspaceBuilder: (_) =>
              const Scaffold(body: Text('Workspace test double')),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-workspace')));
    await tester.pumpAndSettle();
    expect(find.text('Workspace test double'), findsOneWidget);

    Navigator.of(tester.element(find.text('Workspace test double'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDiagnosticsHub), findsOneWidget);
  });
}
