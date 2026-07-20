import 'dart:convert';
import 'dart:ui';

import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart';
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
      pan: const ReaderDiagnosticPoint(18, -9),
      panDelta: const ReaderDiagnosticPoint(3, -2),
      note: 'scale_update',
    );

    final Map<String, Object?> json = event.toJson();

    expect(json['sequence'], 7);
    expect(json['deviceKind'], 'trackpad');
    expect(json['global'], <String, double>{'x': 410, 'y': 260});
    expect(json['pan'], <String, double>{'x': 18, 'y': -9});
    expect(json['panDelta'], <String, double>{'x': 3, 'y': -2});
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
      panDelta: const ReaderDiagnosticPoint(double.nan, double.infinity),
      before: snapshot,
    );

    final Map<String, Object?> json = event.toJson();
    final Map<String, Object?> before = json['before']! as Map<String, Object?>;

    expect(json['scale'], isNull);
    expect(json['panDelta'], isNull);
    expect(before['zoom'], isNull);
    expect(before['translation'], isNull);
    expect(before['viewport'], <String, Object?>{'width': null, 'height': 600});
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
    expect(isFiniteOffset(const Offset(double.nan, double.infinity)), isFalse);
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

  test('mixed pan and zoom moves one anchor by exactly the focal delta', () {
    const Offset previousAnchor = Offset(173, 91);
    const Offset focalDelta = Offset(14, -9);
    final Offset currentAnchor = previousAnchor + focalDelta;
    const double oldScale = 1.25;
    const double newScale = 1.8;
    const Offset oldTranslation = Offset(22, -14);
    final Offset documentPoint = (previousAnchor - oldTranslation) / oldScale;

    final Offset next = anchoredPanZoomTranslation(
      previousAnchor: previousAnchor,
      currentAnchor: currentAnchor,
      oldTranslation: oldTranslation,
      oldScale: oldScale,
      newScale: newScale,
    );

    expect(documentPoint * newScale + next, currentAnchor);
    expect(documentPoint * newScale + next - previousAnchor, focalDelta);
  });

  test(
    'pointer lab keeps an off-center local focal point fixed while zooming',
    () {
      const Size canvasSize = Size(800, 600);
      const Offset localFocalPoint = Offset(620, 180);
      const Offset oldTranslation = Offset(24, -36);
      const double oldScale = 1.25;
      const double newScale = 2.5;
      final Offset anchor = canvasCenteredFocalPoint(
        localFocalPoint: localFocalPoint,
        canvasSize: canvasSize,
      );
      final Offset worldPoint = (anchor - oldTranslation) / oldScale;
      final Offset nextTranslation = anchoredTranslation(
        anchor: anchor,
        oldTranslation: oldTranslation,
        oldScale: oldScale,
        newScale: newScale,
      );
      final Offset renderedAfter =
          canvasSize.center(Offset.zero) +
          nextTranslation +
          worldPoint * newScale;

      expect(renderedAfter.dx, closeTo(localFocalPoint.dx, 0.000001));
      expect(renderedAfter.dy, closeTo(localFocalPoint.dy, 0.000001));
    },
  );

  test('pinch locks to its starting cursor despite cumulative pan noise', () {
    const Offset anchor = Offset(323.2, 244);
    const Offset oldTranslation = Offset.zero;
    const double oldScale = 1;
    const double newScale = 1.72;
    final Offset worldPoint = (anchor - oldTranslation) / oldScale;

    final Offset nextTranslation = trackpadGestureTranslation(
      zoomAnchor: anchor,
      focalPointDelta: const Offset(-531.453173828125, -399.765478515625),
      oldTranslation: oldTranslation,
      oldScale: oldScale,
      newScale: newScale,
      zoomAnchorLocked: true,
    );

    expect(worldPoint * newScale + nextTranslation, anchor);
  });

  test('two-finger pan still applies while no pinch scale is detected', () {
    const Offset oldTranslation = Offset(22, -14);
    const Offset panDelta = Offset(18, -7);

    final Offset nextTranslation = trackpadGestureTranslation(
      zoomAnchor: const Offset(100, 80),
      focalPointDelta: panDelta,
      oldTranslation: oldTranslation,
      oldScale: 1,
      newScale: 1,
      zoomAnchorLocked: false,
    );

    expect(nextTranslation, oldTranslation + panDelta);
  });

  test('pinch mode remains locked after scale returns near one', () {
    expect(
      shouldLockTrackpadZoomAnchor(alreadyLocked: false, cumulativeScale: 1.2),
      isTrue,
    );
    expect(
      shouldLockTrackpadZoomAnchor(alreadyLocked: true, cumulativeScale: 1.001),
      isTrue,
    );
  });

  test(
    'controller snapshots serialize typed boundary state for both values',
    () {
      final ReaderDiagnosticEvent near = ReaderDiagnosticEvent(
        sequence: 1,
        elapsedMicros: 2,
        source: ReaderDiagnosticSource.controllerListener,
        type: ReaderDiagnosticEventType.controllerSnapshot,
        nearBoundary: true,
      );
      final ReaderDiagnosticEvent away = ReaderDiagnosticEvent(
        sequence: 2,
        elapsedMicros: 3,
        source: ReaderDiagnosticSource.controllerListener,
        type: ReaderDiagnosticEventType.controllerSnapshot,
        nearBoundary: false,
      );

      expect(near.toJson()['nearBoundary'], isTrue);
      expect(away.toJson()['nearBoundary'], isFalse);
      expect(jsonEncode(near.toJson()), isNot(contains('near_boundary')));
    },
  );
}
