import 'dart:convert';
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
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleUpdate,
      deviceKind: ReaderDiagnosticDeviceKind.trackpad,
      global: const ReaderDiagnosticPoint(410, 260),
      viewerLocal: const ReaderDiagnosticPoint(390, 220),
      note: 'scale_update',
    );

    final Map<String, Object?> json = event.toJson();

    expect(json['sequence'], 7);
    expect(json['deviceKind'], 'trackpad');
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

  test('non-finite event and snapshot numbers are JSON-safe', () {
    const ReaderViewerSnapshot snapshot = ReaderViewerSnapshot(
      zoom: double.nan,
      translation: ReaderDiagnosticPoint(double.infinity, 12),
      viewportSize: Size(double.infinity, 600),
      documentSize: Size(1200, double.nan),
      visibleRect: Rect.fromLTRB(10, double.nan, 810, double.infinity),
      pageNumber: 3,
    );
    final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
      sequence: 1,
      elapsedMicros: 2,
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleUpdate,
      scale: double.nan,
      before: snapshot,
    );

    final Map<String, Object?> json = event.toJson();
    final Map<String, Object?> before = json['before']! as Map<String, Object?>;

    expect(json['scale'], isNull);
    expect(before['zoom'], isNull);
    expect(before['translation'], isNull);
    expect(before['viewport'], <String, Object?>{
      'width': null,
      'height': 600,
    });
    expect(before['document'], <String, Object?>{
      'width': 1200,
      'height': null,
    });
    expect(before['visibleRect'], <String, Object?>{
      'left': 10,
      'top': null,
      'right': 810,
      'bottom': null,
    });
    expect(jsonEncode(json), isNotEmpty);
  });

  test('raw source and note values cannot leak through event JSON', () {
    const List<String> unsafeValues = <String>[
      r'C:\private\patient-report.pdf',
      'Confidential report title',
      'Extracted document text is private.',
      'gemma-4-e4b-it',
    ];

    for (final String unsafeValue in unsafeValues) {
      final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
        sequence: 1,
        elapsedMicros: 2,
        source: ReaderDiagnosticSource.fromRaw(unsafeValue),
        type: ReaderDiagnosticEventType.viewerError,
        note: unsafeValue,
      );
      final Map<String, Object?> json = event.toJson();
      final String encoded = jsonEncode(json);

      expect(event.source, ReaderDiagnosticSource.unknown);
      expect(json['source'], 'unknown');
      expect(json['note'], isNull);
      expect(encoded, isNot(contains(unsafeValue)));
    }
  });

  test('sanitized notes retain the Task 3 near-boundary marker', () {
    final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
      sequence: 1,
      elapsedMicros: 2,
      source: ReaderDiagnosticSource.controllerListener,
      type: ReaderDiagnosticEventType.controllerSnapshot,
      note: readerDiagnosticNearBoundaryNote,
    );

    expect(event.toJson()['note'], readerDiagnosticNearBoundaryNote);
  });

  test('device kinds use allowlisted JSON values', () {
    expect(ReaderDiagnosticDeviceKind.mouse.jsonValue, 'mouse');
    expect(ReaderDiagnosticDeviceKind.touch.jsonValue, 'touch');
    expect(ReaderDiagnosticDeviceKind.stylus.jsonValue, 'stylus');
    expect(
      ReaderDiagnosticDeviceKind.invertedStylus.jsonValue,
      'invertedStylus',
    );
    expect(ReaderDiagnosticDeviceKind.trackpad.jsonValue, 'trackpad');
  });

  test('raw device kinds cannot leak through event JSON', () {
    const List<String> unsafeValues = <String>[
      r'C:\private\patient-report.pdf',
      'Confidential document title',
      'Extracted document text is private.',
      'gemma-4-e4b-it',
    ];

    for (final String unsafeValue in unsafeValues) {
      final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
        sequence: 1,
        elapsedMicros: 2,
        source: ReaderDiagnosticSource.instrumentedPdfrx,
        type: ReaderDiagnosticEventType.pointerMove,
        deviceKind: ReaderDiagnosticDeviceKind.fromRaw(unsafeValue),
      );
      final String encoded = jsonEncode(event.toJson());

      expect(event.deviceKind, ReaderDiagnosticDeviceKind.unknown);
      expect(event.toJson()['deviceKind'], 'unknown');
      expect(encoded, isNot(contains(unsafeValue)));
    }
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
