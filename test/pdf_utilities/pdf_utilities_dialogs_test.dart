import 'package:clarix/src/core/ffi/api.dart';
import 'package:clarix/src/features/utilities/application/pdf_utility_service.dart';
import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:clarix/src/features/utilities/infrastructure/document_conversion_service.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  late _FakePdfComposeNative native;
  late PdfUtilityService service;
  late List<UtilityResult> openedResults;

  setUp(() {
    native = _FakePdfComposeNative();
    service = PdfUtilityService(native: native, fileExists: (_) async => true);
    openedResults = <UtilityResult>[];
  });

  testWidgets('combine adds, reorders, and removes selected PDFs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CombinePdfDialog(
          service: service,
          pickSources: () async => <String>[
            'C:/docs/alpha.pdf',
            'C:/docs/bravo.pdf',
            'C:/docs/charlie.pdf',
          ],
          pickDestination: () async => 'C:/docs/combined.pdf',
          onCompleted: openedResults.add,
        ),
      ),
    );

    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Combine'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Add PDFs'));
    await tester.pump();
    expect(find.text('alpha.pdf'), findsOneWidget);
    expect(find.text('bravo.pdf'), findsOneWidget);
    expect(find.text('charlie.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('combine-move-up-1')));
    await tester.pump();
    expect(_selectedFileLabels(tester), <String>[
      'bravo.pdf',
      'alpha.pdf',
      'charlie.pdf',
    ]);

    await tester.drag(
      find.byKey(const Key('combine-drag-2')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(_selectedFileLabels(tester), <String>[
      'bravo.pdf',
      'charlie.pdf',
      'alpha.pdf',
    ]);

    await tester.tap(find.byKey(const Key('combine-remove-1')));
    await tester.pump();
    expect(find.text('charlie.pdf'), findsNothing);
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('combine opens only the successful generated result', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CombinePdfDialog(
          service: service,
          pickSources: () async => <String>[
            'C:/docs/alpha.pdf',
            'C:/docs/bravo.pdf',
          ],
          pickDestination: () async => 'C:/docs/combined.pdf',
          onCompleted: openedResults.add,
        ),
      ),
    );

    await tester.tap(find.text('Add PDFs'));
    await tester.pump();
    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();

    expect(
      native.requests.single.sources.map(
        (NativePdfSource source) => source.path,
      ),
      <String>['C:/docs/alpha.pdf', 'C:/docs/bravo.pdf'],
    );
    expect(openedResults.single.outputPath, 'C:/docs/combined.pdf');
  });

  testWidgets('combine failure stays open and does not open an output', (
    WidgetTester tester,
  ) async {
    native.error = StateError('write failed');
    await tester.pumpWidget(
      _app(
        CombinePdfDialog(
          service: service,
          pickSources: () async => <String>['a.pdf', 'b.pdf'],
          pickDestination: () async => 'out.pdf',
          onCompleted: openedResults.add,
        ),
      ),
    );

    await tester.tap(find.text('Add PDFs'));
    await tester.pump();
    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();

    expect(find.textContaining('write failed'), findsOneWidget);
    expect(openedResults, isEmpty);
    expect(find.text('Combine PDF files'), findsOneWidget);
  });

  testWidgets('extract validates pages against the loaded PDF page count', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ExtractPagesDialog(
          service: service,
          pickSource: () async => 'C:/docs/source.pdf',
          pickDestination: () async => 'C:/docs/extracted.pdf',
          loadPageCount: (_) async => 7,
          onCompleted: openedResults.add,
        ),
      ),
    );

    await tester.tap(find.text('Select PDF'));
    await tester.pump();
    expect(find.text('source.pdf'), findsOneWidget);
    expect(find.text('7 pages'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('extract-page-selection')),
      '1-3, 8',
    );
    await tester.pump();
    expect(find.text('Page selection is outside 1-7.'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Extract'))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('extract-page-selection')),
      '3-4, 1, 3',
    );
    await tester.pump();
    expect(find.text('3 pages selected'), findsOneWidget);

    await tester.tap(find.text('Extract'));
    await tester.pumpAndSettle();
    expect(
      native.requests.single.sources.single.pages.map(
        (BigInt page) => page.toInt(),
      ),
      <int>[3, 4, 1],
    );
    expect(openedResults.single.outputPath, 'C:/docs/extracted.pdf');
  });

  testWidgets('extract rejects a source whose page count cannot be loaded', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ExtractPagesDialog(
          service: service,
          pickSource: () async => 'C:/docs/encrypted.pdf',
          pickDestination: () async => 'C:/docs/extracted.pdf',
          loadPageCount: (_) async =>
              throw const FormatException('The PDF is encrypted.'),
          onCompleted: openedResults.add,
        ),
      ),
    );

    await tester.tap(find.text('Select PDF'));
    await tester.pump();

    expect(find.text('null pages'), findsNothing);
    expect(
      find.text('Could not load encrypted.pdf: The PDF is encrypted.'),
      findsOneWidget,
    );
    expect(find.text('Select PDF'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Extract'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('convert selects and removes supported local sources', (
    WidgetTester tester,
  ) async {
    final _FakeDirectPdfConverter direct = _FakeDirectPdfConverter();
    await tester.pumpWidget(
      _app(
        ConvertToPdfDialog(
          service: DocumentConversionService(
            direct: direct,
            office: _FakeOfficePdfConverter(),
          ),
          pickSources: () async => <String>[
            'C:/docs/notes.md',
            'C:/docs/photo.png',
          ],
          pickOutputDirectory: () async => r'C:\output',
          onCompleted: (_) {},
        ),
      ),
    );

    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Convert'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Add files'));
    await tester.pump();

    expect(find.text('notes.md'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Convert'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('convert-remove-0')));
    await tester.pump();
    expect(find.text('notes.md'), findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
  });

  testWidgets('convert sends the selected batch to the output directory', (
    WidgetTester tester,
  ) async {
    final _FakeDirectPdfConverter direct = _FakeDirectPdfConverter();
    final List<List<UtilityResult>> completed = <List<UtilityResult>>[];
    await tester.pumpWidget(
      _app(
        ConvertToPdfDialog(
          service: DocumentConversionService(
            direct: direct,
            office: _FakeOfficePdfConverter(),
          ),
          pickSources: () async => <String>[
            'C:/docs/notes.md',
            'C:/docs/photo.png',
          ],
          pickOutputDirectory: () async => r'C:\output',
          onCompleted: completed.add,
        ),
      ),
    );

    await tester.tap(find.text('Add files'));
    await tester.pump();
    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();

    expect(direct.markdownCalls, <String>[
      r'C:/docs/notes.md|C:\output\notes.pdf',
    ]);
    expect(direct.imageCalls, <String>[
      r'C:/docs/photo.png|C:\output\photo.pdf',
    ]);
    expect(
      completed.single.map((UtilityResult result) => result.outputPath),
      <String>[r'C:\output\notes.pdf', r'C:\output\photo.pdf'],
    );
  });

  testWidgets('convert failure stays open and does not publish outputs', (
    WidgetTester tester,
  ) async {
    final _FakeDirectPdfConverter direct = _FakeDirectPdfConverter()
      ..error = const UtilityFailure('Markdown input is unreadable.');
    final List<List<UtilityResult>> completed = <List<UtilityResult>>[];
    await tester.pumpWidget(
      _app(
        ConvertToPdfDialog(
          service: DocumentConversionService(
            direct: direct,
            office: _FakeOfficePdfConverter(),
          ),
          pickSources: () async => <String>['C:/docs/notes.md'],
          pickOutputDirectory: () async => 'C:/output',
          onCompleted: completed.add,
        ),
      ),
    );

    await tester.tap(find.text('Add files'));
    await tester.pump();
    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();

    expect(find.text('Markdown input is unreadable.'), findsOneWidget);
    expect(completed, isEmpty);
    expect(find.text('Convert files to PDF'), findsOneWidget);
  });
}

List<String> _selectedFileLabels(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('combine-selected-files')),
        matching: find.byType(Text),
      ),
    )
    .map((Text widget) => widget.data)
    .whereType<String>()
    .where(
      (String text) =>
          text.endsWith('.pdf') && !text.contains('/') && !text.contains('\\'),
    )
    .toList(growable: false);

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

final class _FakePdfComposeNative implements PdfComposeNative {
  final List<NativePdfComposeRequest> requests = <NativePdfComposeRequest>[];
  Object? error;

  @override
  Future<NativePdfComposeResponse> compose(
    NativePdfComposeRequest request,
  ) async {
    requests.add(request);
    if (error != null) {
      throw error!;
    }
    return NativePdfComposeResponse(
      outputPath: request.outputPath,
      pageCount: BigInt.from(
        request.sources.fold<int>(
          0,
          (int total, NativePdfSource source) =>
              total + (source.pages.isEmpty ? 1 : source.pages.length),
        ),
      ),
      message: null,
    );
  }
}

final class _FakeDirectPdfConverter implements DirectPdfConverter {
  final List<String> imageCalls = <String>[];
  final List<String> textCalls = <String>[];
  final List<String> markdownCalls = <String>[];
  Object? error;

  @override
  Future<int> imagesToPdf(List<String> sourcePaths, String outputPath) async {
    _throwIfNeeded();
    imageCalls.add('${sourcePaths.single}|$outputPath');
    return sourcePaths.length;
  }

  @override
  Future<int> markdownToPdf(String sourcePath, String outputPath) async {
    _throwIfNeeded();
    markdownCalls.add('$sourcePath|$outputPath');
    return 1;
  }

  @override
  Future<int> textToPdf(String sourcePath, String outputPath) async {
    _throwIfNeeded();
    textCalls.add('$sourcePath|$outputPath');
    return 1;
  }

  void _throwIfNeeded() {
    if (error != null) {
      throw error!;
    }
  }
}

final class _FakeOfficePdfConverter implements OfficePdfConverter {
  @override
  Future<void> convert(String inputPath, String outputPath) async {}
}
