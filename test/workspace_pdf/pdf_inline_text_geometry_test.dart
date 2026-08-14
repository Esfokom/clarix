import 'dart:math' as math;

import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_inline_text_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps PDF font points baseline and rotation into overlay space', () {
    final block = _block();
    final geometry = PdfInlineTextGeometry.resolve(
      block: block,
      pageSize: const Size(612, 792),
      overlaySize: const Size(1224, 1584),
    );

    expect(geometry.fontSize, closeTo(24, 0.01));
    expect(geometry.angleRadians, closeTo(math.pi / 6, 0.01));
    expect(geometry.baselineY, closeTo(1344, 0.01));
  });
}

PdfTextBlock _block() {
  final locator = PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'revision',
  );
  const angle = math.pi / 6;
  return PdfTextBlock(
    locator: locator,
    text: 'Text',
    originalText: 'Text',
    runs: <PdfTextRun>[
      PdfTextRun(
        range: const PdfTextRange(0, 4),
        style: const PdfTextStyle(
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
    bounds: const PdfBox(10, 100, 80, 130),
    transform: PdfTransform(
      math.cos(angle),
      math.sin(angle),
      -math.sin(angle),
      math.cos(angle),
      10,
      120,
    ),
    baseline: 120,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: PdfTextCapability.values,
    readOnlyReason: null,
  );
}
