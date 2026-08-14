import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projection result defensively owns native layout collections', () {
    final lines = <PdfNativeLine>[
      const PdfNativeLine(
        range: PdfTextRange(0, 4),
        bounds: PdfBox(10, 20, 42, 32),
      ),
    ];
    final characters = <PdfNativeCharacterBox>[
      const PdfNativeCharacterBox(offset: 0, bounds: PdfBox(10, 20, 18, 32)),
    ];
    final pages = <int>[1];

    final result = PdfNativeProjectionResult(
      requestedRevision: 7,
      appliedRevision: 7,
      block: _block(),
      lines: lines,
      characters: characters,
      affectedPages: pages,
    );
    lines.clear();
    characters.clear();
    pages.clear();

    expect(result.lines, hasLength(1));
    expect(result.characters.single.offset, 0);
    expect(result.affectedPages, const <int>[1]);
    expect(() => result.affectedPages.add(2), throwsUnsupportedError);
  });

  test('projection result rejects character offsets outside block text', () {
    expect(
      () => PdfNativeProjectionResult(
        requestedRevision: 2,
        appliedRevision: 2,
        block: _block(),
        lines: const <PdfNativeLine>[],
        characters: const <PdfNativeCharacterBox>[
          PdfNativeCharacterBox(offset: 5, bounds: PdfBox(10, 20, 18, 32)),
        ],
        affectedPages: const <int>[1],
      ),
      throwsRangeError,
    );
  });
}

PdfTextBlock _block() => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'source',
  ),
  text: 'Edit',
  originalText: 'Edit',
  runs: const <PdfTextRun>[
    PdfTextRun(
      range: PdfTextRange(0, 4),
      style: PdfTextStyle(
        fontFamily: 'Helvetica',
        fontSize: 12,
        fillColorValue: 0xff000000,
        fontWeight: 400,
        italic: false,
        underline: false,
        baselineShift: 0,
        alignment: PdfTextAlignment.left,
        characterSpacing: 0,
        lineSpacing: 0,
        horizontalScaling: 1,
      ),
    ),
  ],
  bounds: const PdfBox(10, 20, 42, 32),
  transform: const PdfTransform(1, 0, 0, 1, 10, 20),
  baseline: 20,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: PdfTextCapability.values,
  readOnlyReason: null,
);
