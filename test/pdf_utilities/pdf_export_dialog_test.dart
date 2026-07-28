import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'export labels visual formats and sends the chosen PDF to Word export',
    (WidgetTester tester) async {
      final List<UtilityResult> completed = <UtilityResult>[];
      final List<String> calls = <String>[];

      await tester.pumpWidget(
        _app(
          ExportPdfDialog(
            pickSource: () async => 'C:/docs/report.pdf',
            pickDestination: (UtilityFormat format, String sourcePath) async {
              expect(format, UtilityFormat.word);
              expect(sourcePath, 'C:/docs/report.pdf');
              return 'C:/docs/report.docx';
            },
            runExport:
                ({
                  required String sourcePath,
                  required UtilityFormat format,
                  required String outputPath,
                }) async {
                  calls.add('$sourcePath|$format|$outputPath');
                  return UtilityResult(outputPath: outputPath, pageCount: 1);
                },
            onCompleted: completed.add,
          ),
        ),
      );

      expect(find.text('Word (visual)'), findsOneWidget);
      expect(find.text('PowerPoint (visual)'), findsOneWidget);
      expect(
        find.textContaining('do not recreate editable page layouts'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Export'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Select PDF'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('export-format-word')));
      await tester.pump();
      await tester.tap(find.text('Export'));
      for (int attempt = 0; attempt < 20 && completed.isEmpty; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(calls, <String>[
        'C:/docs/report.pdf|UtilityFormat.word|C:/docs/report.docx',
      ]);
      expect(completed.single.outputPath, 'C:/docs/report.docx');
    },
  );
}

Widget _app(Widget child) => ProviderScope(
  child: ShadApp(
    themeMode: ThemeMode.dark,
    theme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    home: Scaffold(body: Center(child: child)),
  ),
);
