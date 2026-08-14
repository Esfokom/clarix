import 'dart:math' as math;

import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_page_object.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rotate undo and redo restore exact affine matrices', () async {
    const source = PdfTransform(1, 0.2, -0.3, 1.4, 18, 27);
    final controller = PdfEditingController(commandId: () => 'rotate-1')
      ..registerSession('tab', _session(source));

    final result = await controller.dispatch(
      RotatePdfPageObjectIntent(
        documentId: 'doc',
        documentRevision: 'rev',
        locator: _locator,
        radians: math.pi / 6,
      ),
      provenance: PdfCommandProvenance.manual,
    );
    expect(result.isSuccess, isTrue);
    final rotated = controller.sessionFor('tab').pageObjects.single.transform;
    expect(rotated, isNot(source));

    await controller.undo('tab');
    expect(controller.sessionFor('tab').pageObjects.single.transform, source);
    await controller.redo('tab');
    expect(controller.sessionFor('tab').pageObjects.single.transform, rotated);
  });

  test('nested form transform fails before history mutation', () async {
    final locked = _object(const PdfTransform(1, 0, 0, 1, 0, 0), locked: true);
    final controller = PdfEditingController(commandId: () => 'move-1')
      ..registerSession(
        'tab',
        PdfEditingSession.empty(
          'doc',
          sourceRevision: 'rev',
        ).withPageObjects(<PdfPageObject>[locked]),
      );

    final result = await controller.dispatch(
      MovePdfPageObjectIntent(
        documentId: 'doc',
        documentRevision: 'rev',
        locator: _locator,
        transform: const PdfTransform(1, 0, 0, 1, 12, 5),
      ),
      provenance: PdfCommandProvenance.manual,
    );

    expect(result.failure, isA<PdfReadOnlyPageObjectFailure>());
    expect(controller.sessionFor('tab').commands, isEmpty);
  });
}

final _locator = PdfPageObjectLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  type: PdfPageObjectType.text,
  contentDigest: 'content',
  geometryDigest: 'geometry',
  sourceRevision: 'rev',
);

PdfPageObject _object(PdfTransform transform, {bool locked = false}) =>
    PdfPageObject(
      locator: _locator,
      bounds: const PdfBox(0, 0, 100, 20),
      transform: transform,
      capabilities: locked
          ? const <PdfPageObjectCapability>{PdfPageObjectCapability.inspect}
          : const <PdfPageObjectCapability>{
              PdfPageObjectCapability.inspect,
              PdfPageObjectCapability.move,
              PdfPageObjectCapability.resize,
              PdfPageObjectCapability.rotate,
            },
      readOnlyReason: locked
          ? PdfPageObjectReadOnlyReason.sharedFormObject
          : null,
    );

PdfEditingSession _session(PdfTransform transform) => PdfEditingSession.empty(
  'doc',
  sourceRevision: 'rev',
).withPageObjects(<PdfPageObject>[_object(transform)]);
