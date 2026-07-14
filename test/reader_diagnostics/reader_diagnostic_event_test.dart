import 'dart:ui';

import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('event JSON contains coordinates but no sensitive document fields', () {
    final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
      sequence: 7,
      elapsedMicros: 1200,
      source: 'instrumented_pdfrx',
      type: ReaderDiagnosticEventType.scaleUpdate,
      deviceKind: 'trackpad',
      global: const ReaderDiagnosticPoint(410, 260),
      viewerLocal: const ReaderDiagnosticPoint(390, 220),
      note: 'scale update',
    );

    final Map<String, Object?> json = event.toJson();

    expect(json['sequence'], 7);
    expect(json['global'], <String, double>{'x': 410, 'y': 260});
    expect(json.keys, isNot(contains('path')));
    expect(json.keys, isNot(contains('title')));
    expect(json.keys, isNot(contains('text')));
    expect(json.keys, isNot(contains('model')));
  });

  test('points omit non-finite coordinates from diagnostic JSON', () {
    const ReaderDiagnosticPoint point = ReaderDiagnosticPoint(
      double.nan,
      double.infinity,
    );

    expect(point.isFinite, isFalse);
    expect(point.toJson(), isNull);
  });

  test('viewer snapshots contain only viewer geometry', () {
    const ReaderViewerSnapshot snapshot = ReaderViewerSnapshot(
      zoom: 1.5,
      translation: ReaderDiagnosticPoint(12, -8),
      viewportSize: Size(800, 600),
      documentSize: Size(1200, 1600),
      visibleRect: Rect.fromLTWH(10, 20, 800, 600),
      pageNumber: 3,
    );

    expect(snapshot.toJson(), <String, Object?>{
      'zoom': 1.5,
      'translation': <String, double>{'x': 12, 'y': -8},
      'viewport': <String, double>{'width': 800, 'height': 600},
      'document': <String, double>{'width': 1200, 'height': 1600},
      'visibleRect': <String, double>{
        'left': 10,
        'top': 20,
        'right': 810,
        'bottom': 620,
      },
      'pageNumber': 3,
    });
  });

  test('finite offset and matrix translation report usable coordinates', () {
    final Matrix4 matrix = Matrix4.translationValues(22, -14, 0);

    expect(isFiniteOffset(const Offset(4, 9)), isTrue);
    expect(
      isFiniteOffset(const Offset(double.nan, double.infinity)),
      isFalse,
    );
    expect(matrixTranslation(matrix), const Offset(22, -14));
  });

  test('affine camera keeps the anchor invariant', () {
    const Offset anchor = Offset(173, 91);
    const double oldScale = 1.0;
    const double newScale = 1.75;
    const Offset oldTranslation = Offset(22, -14);
    final Offset documentPoint = (anchor - oldTranslation) / oldScale;
    final Offset next = anchoredTranslation(
      anchor: anchor,
      oldTranslation: oldTranslation,
      oldScale: oldScale,
      newScale: newScale,
    );

    expect(documentPoint * newScale + next, anchor);
  });
}
