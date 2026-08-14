import 'dart:math' as math;
import 'package:clarix/src/features/workspace/domain/pdf_page_object.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rotation preserves scale and keeps the requested center fixed', () {
    const source = PdfTransform(2, 0, 0, 3, 20, 30);
    const center = Offset(50, 60);
    final transformedCenter = source.transformPoint(center);

    final rotated = source.rotatedAround(
      radians: math.pi / 2,
      center: transformedCenter,
    );

    expect(
      rotated.transformPoint(center).dx,
      closeTo(transformedCenter.dx, 0.0001),
    );
    expect(
      rotated.transformPoint(center).dy,
      closeTo(transformedCenter.dy, 0.0001),
    );
    expect(
      rotated.determinant.abs(),
      closeTo(source.determinant.abs(), 0.0001),
    );
  });

  test('inverse transform recovers the original point', () {
    const source = PdfTransform(1.2, 0.4, -0.2, 0.8, 14, -9);
    const point = Offset(37, 81);

    expect(
      source.inverseTransformPoint(source.transformPoint(point)).dx,
      closeTo(point.dx, 0.0001),
    );
    expect(
      source.inverseTransformPoint(source.transformPoint(point)).dy,
      closeTo(point.dy, 0.0001),
    );
  });

  test('singular matrices cannot be inverted', () {
    const source = PdfTransform(1, 2, 2, 4, 0, 0);
    expect(
      () => source.inverseTransformPoint(Offset.zero),
      throwsA(isA<PdfInvalidTransformFailure>()),
    );
  });

  test('nested form object is inspectable but not transformable', () {
    final object = PdfPageObject(
      locator: PdfPageObjectLocator(
        pageNumber: 1,
        objectPath: const <int>[3, 0],
        type: PdfPageObjectType.form,
        contentDigest: 'content',
        geometryDigest: 'geometry',
        sourceRevision: 'revision',
      ),
      bounds: const PdfBox(0, 0, 100, 20),
      transform: const PdfTransform(1, 0, 0, 1, 0, 0),
      capabilities: const <PdfPageObjectCapability>{
        PdfPageObjectCapability.inspect,
      },
      readOnlyReason: PdfPageObjectReadOnlyReason.sharedFormObject,
    );

    expect(object.capabilities, contains(PdfPageObjectCapability.inspect));
    expect(object.capabilities, isNot(contains(PdfPageObjectCapability.move)));
    expect(object.readOnlyReason, PdfPageObjectReadOnlyReason.sharedFormObject);
    expect(
      () => object.requireCapability(PdfPageObjectCapability.rotate),
      throwsA(isA<PdfReadOnlyPageObjectFailure>()),
    );
  });

  test('locator and capabilities are immutable value objects', () {
    final path = <int>[4];
    final capabilities = <PdfPageObjectCapability>{
      PdfPageObjectCapability.inspect,
      PdfPageObjectCapability.move,
    };
    final object = PdfPageObject(
      locator: PdfPageObjectLocator(
        pageNumber: 2,
        objectPath: path,
        type: PdfPageObjectType.image,
        contentDigest: 'content',
        geometryDigest: 'geometry',
        sourceRevision: 'revision',
      ),
      bounds: const PdfBox(10, 20, 30, 40),
      transform: const PdfTransform(1, 0, 0, 1, 10, 20),
      capabilities: capabilities,
    );
    path.add(9);
    capabilities.clear();

    expect(object.locator.objectPath, const <int>[4]);
    expect(object.capabilities, contains(PdfPageObjectCapability.move));
    expect(() => object.capabilities.clear(), throwsUnsupportedError);
  });
}
