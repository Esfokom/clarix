import 'dart:io';

import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Drive target for the block-inspection harness.
///
/// Opens a real PDF through [LivePdfiumSession] and prints per-page text-block
/// import statistics (block counts, single- vs multi-object blocks, editable
/// blocks, and per-block object/text detail) so block-import regressions are
/// observable on real documents before interactive editing is exercised.
///
/// Usage:
///   flutter drive -d windows --profile `
///     --driver test_driver/integration_test.dart `
///     --target tool/editing_phase1/inspect_blocks.dart `
///     "--dart-define=PDF=`<path-to-pdf>`"
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('inspect text blocks', (tester) async {
    const pdfPath = String.fromEnvironment('PDF');
    if (pdfPath.isEmpty) {
      throw StateError('inspect_blocks requires --dart-define=PDF=<path>');
    }
    if (!File(pdfPath).existsSync()) {
      throw StateError('PDF file not found: $pdfPath');
    }

    await ClarixRustRuntime.requireInitialized();

    // Page count comes from a short-lived pdfrx document; the inspection
    // itself runs through the session's own document below.
    final document = await PdfDocument.openFile(pdfPath);
    final pageCount = document.pages.length;
    await document.dispose();
    debugPrint('[inspect] $pdfPath: $pageCount pages');

    final session = await LivePdfiumSession.open(pdfPath);
    try {
      final blocks = await session.inspectTextBlocks(
        sourceRevision: 'inspect',
        pageNumbers: List<int>.generate(pageCount, (index) => index + 1),
      );
      for (var pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
        final pageBlocks = blocks
            .where((block) => block.locator.pageNumber == pageNumber)
            .toList(growable: false);
        final singleObject = pageBlocks
            .where((block) => block.objectPaths.length == 1)
            .length;
        final multiObject = pageBlocks
            .where((block) => block.objectPaths.length > 1)
            .length;
        final editable = pageBlocks.where((block) => block.isEditable).length;
        debugPrint(
          '[inspect] page $pageNumber: blocks=${pageBlocks.length} '
          'single=$singleObject multi=$multiObject editable=$editable',
        );
        for (var index = 0; index < pageBlocks.length; index += 1) {
          final block = pageBlocks[index];
          final preview = block.text.length <= 40
              ? block.text
              : '${block.text.substring(0, 40)}...';
          debugPrint(
            '[inspect]   block ${index + 1}: '
            'objects=${block.objectPaths.length} chars=${block.text.length} '
            '"$preview"',
          );
        }
      }
    } finally {
      await session.close();
    }
  });
}
