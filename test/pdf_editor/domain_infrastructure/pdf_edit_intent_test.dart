import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'domain values compare by value and never expose mutable collections',
    () {
      final PdfTextBlockLocator locator = PdfTextBlockLocator(
        pageNumber: 3,
        objectPath: <int>[1, 4],
        textDigest: 'text',
        geometryDigest: 'geometry',
        fontFingerprint: 'font',
        sourceRevision: 'sha256:a',
      );
      final PdfTextBlockLocator equivalent = PdfTextBlockLocator(
        pageNumber: 3,
        objectPath: <int>[1, 4],
        textDigest: 'text',
        geometryDigest: 'geometry',
        fontFingerprint: 'font',
        sourceRevision: 'sha256:a',
      );

      expect(locator, equivalent);
      expect(() => locator.objectPath.add(8), throwsUnsupportedError);
    },
  );

  test('text blocks expose an explicit unsupported-content reason', () {
    final PdfTextBlock block = PdfTextBlock(
      locator: testLocator,
      text: 'Outline',
      originalText: 'Outline',
      runs: const <PdfTextRun>[],
      bounds: const PdfBox(0, 0, 40, 12),
      transform: const PdfTransform(1, 0, 0, 1, 0, 0),
      baseline: 0,
      writingDirection: PdfWritingDirection.leftToRight,
      capabilities: const <PdfTextCapability>[],
      readOnlyReason: PdfReadOnlyReason.vectorOutline,
    );

    expect(block.isEditable, isFalse);
    expect(block.readOnlyReason, PdfReadOnlyReason.vectorOutline);
  });

  test(
    'replacement intent preserves the document revision and UTF-16 range',
    () {
      final ReplacePdfTextIntent intent = ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'sha256:a',
        locator: testLocator,
        range: PdfTextRange(1, 3),
        replacement: 'Z',
      );

      expect(intent.documentId, 'doc');
      expect(intent.documentRevision, 'sha256:a');
      expect(intent.range.length, 2);
      expect(intent.affectedLocators, <PdfTextBlockLocator>[testLocator]);
    },
  );

  test('edit result carries either applied command ids or a typed failure', () {
    final PdfEditResult applied = PdfEditResult.applied(
      revision: 'sha256:b',
      commandIds: <String>['c1'],
      affectedLocators: <PdfTextBlockLocator>[testLocator],
    );
    final PdfEditResult rejected = PdfEditResult.failure(
      PdfRevisionConflictFailure(expected: 'sha256:b', actual: 'sha256:a'),
    );

    expect(applied.isSuccess, isTrue);
    expect(applied.commandIds, <String>['c1']);
    expect(rejected.isSuccess, isFalse);
    expect(rejected.failure, isA<PdfRevisionConflictFailure>());
  });

  test(
    'intents commands and results compare structurally and expose immutable views',
    () {
      final ReplacePdfTextIntent first = ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'sha256:a',
        locator: testLocator,
        range: const PdfTextRange(0, 1),
        replacement: 'B',
      );
      final ReplacePdfTextIntent equivalent = ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'sha256:a',
        locator: testLocator,
        range: const PdfTextRange(0, 1),
        replacement: 'B',
      );
      final ReplacePdfTextCommand command = ReplacePdfTextCommand(
        id: 'c1',
        provenance: PdfCommandProvenance.manual,
        locator: testLocator,
        before: 'A',
        after: 'B',
        range: const PdfTextRange(0, 1),
      );
      final PdfEditResult result = PdfEditResult.applied(
        revision: 'sha256:b',
        commandIds: <String>['c1'],
        affectedLocators: <PdfTextBlockLocator>[testLocator],
      );
      final PdfEditResult equivalentResult = PdfEditResult.applied(
        revision: 'sha256:b',
        commandIds: <String>['c1'],
        affectedLocators: <PdfTextBlockLocator>[testLocator],
      );

      expect(first, equivalent);
      expect(result, equivalentResult);
      expect(
        () => first.affectedLocators.add(testLocator),
        throwsUnsupportedError,
      );
      expect(() => first.affectedPages.add(2), throwsUnsupportedError);
      expect(
        () => command.affectedLocators.add(testLocator),
        throwsUnsupportedError,
      );
    },
  );
}

final PdfTextBlockLocator testLocator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: <int>[0],
  textDigest: 'text',
  geometryDigest: 'geometry',
  fontFingerprint: 'font',
  sourceRevision: 'sha256:a',
);
