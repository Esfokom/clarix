import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'pdf_text_types.dart';

enum PdfPageObjectType { text, image, path, form }

enum PdfPageObjectCapability { inspect, editText, move, resize, rotate }

enum PdfPageObjectReadOnlyReason {
  sharedFormObject,
  unsupportedType,
  singularTransform,
}

final class PdfPageObjectLocator {
  PdfPageObjectLocator({
    required this.pageNumber,
    required List<int> objectPath,
    required this.type,
    required this.contentDigest,
    required this.geometryDigest,
    required this.sourceRevision,
  }) : objectPath = List<int>.unmodifiable(objectPath);

  final int pageNumber;
  final List<int> objectPath;
  final PdfPageObjectType type;
  final String contentDigest;
  final String geometryDigest;
  final String sourceRevision;

  @override
  bool operator ==(Object other) =>
      other is PdfPageObjectLocator &&
      other.pageNumber == pageNumber &&
      _listEquals(other.objectPath, objectPath) &&
      other.type == type &&
      other.contentDigest == contentDigest &&
      other.geometryDigest == geometryDigest &&
      other.sourceRevision == sourceRevision;

  @override
  int get hashCode => Object.hash(
    pageNumber,
    Object.hashAll(objectPath),
    type,
    contentDigest,
    geometryDigest,
    sourceRevision,
  );
}

final class PdfPageObject {
  PdfPageObject({
    required this.locator,
    required this.bounds,
    required this.transform,
    required Set<PdfPageObjectCapability> capabilities,
    this.readOnlyReason,
  }) : capabilities = UnmodifiableSetView(
         Set<PdfPageObjectCapability>.of(capabilities),
       );

  final PdfPageObjectLocator locator;
  final PdfBox bounds;
  final PdfTransform transform;
  final Set<PdfPageObjectCapability> capabilities;
  final PdfPageObjectReadOnlyReason? readOnlyReason;

  void requireCapability(PdfPageObjectCapability capability) {
    final reason = readOnlyReason;
    if (reason != null) {
      throw PdfReadOnlyPageObjectFailure(locator: locator, reason: reason);
    }
    if (!capabilities.contains(capability)) {
      throw PdfUnsupportedPageObjectOperationFailure(
        locator: locator,
        capability: capability,
      );
    }
  }

  PdfPageObject copyWith({PdfBox? bounds, PdfTransform? transform}) =>
      PdfPageObject(
        locator: locator,
        bounds: bounds ?? this.bounds,
        transform: transform ?? this.transform,
        capabilities: capabilities,
        readOnlyReason: readOnlyReason,
      );
}

final class PdfReadOnlyPageObjectFailure extends PdfEditFailure {
  PdfReadOnlyPageObjectFailure({required this.locator, required this.reason})
    : super(
        'read_only_page_object',
        'This PDF object is read-only: ${reason.name}.',
      );

  final PdfPageObjectLocator locator;
  final PdfPageObjectReadOnlyReason reason;
}

final class PdfUnsupportedPageObjectOperationFailure extends PdfEditFailure {
  PdfUnsupportedPageObjectOperationFailure({
    required this.locator,
    required this.capability,
  }) : super(
         'unsupported_page_object_operation',
         'This PDF object does not support ${capability.name}.',
       );

  final PdfPageObjectLocator locator;
  final PdfPageObjectCapability capability;
}

final class PdfInvalidTransformFailure extends PdfEditFailure {
  const PdfInvalidTransformFailure()
    : super('invalid_transform', 'The PDF object transform is singular.');
}

final class PdfStalePageObjectLocatorFailure extends PdfEditFailure {
  const PdfStalePageObjectLocatorFailure(this.locator)
    : super(
        'stale_page_object_locator',
        'The PDF object no longer matches the source document.',
      );

  final PdfPageObjectLocator locator;
}

extension PdfTransformOperations on PdfTransform {
  double get determinant => a * d - b * c;

  bool get isFinite =>
      a.isFinite &&
      b.isFinite &&
      c.isFinite &&
      d.isFinite &&
      translateX.isFinite &&
      translateY.isFinite;

  Offset transformPoint(Offset point) => Offset(
    a * point.dx + c * point.dy + translateX,
    b * point.dx + d * point.dy + translateY,
  );

  Offset inverseTransformPoint(Offset point) {
    final divisor = determinant;
    if (!divisor.isFinite || divisor.abs() < 1e-12) {
      throw const PdfInvalidTransformFailure();
    }
    final x = point.dx - translateX;
    final y = point.dy - translateY;
    return Offset((d * x - c * y) / divisor, (-b * x + a * y) / divisor);
  }

  PdfTransform translated({required double dx, required double dy}) =>
      PdfTransform(a, b, c, d, translateX + dx, translateY + dy);

  PdfTransform rotatedAround({
    required double radians,
    required Offset center,
  }) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final shiftedX = translateX - center.dx;
    final shiftedY = translateY - center.dy;
    return PdfTransform(
      cosine * a - sine * b,
      sine * a + cosine * b,
      cosine * c - sine * d,
      sine * c + cosine * d,
      cosine * shiftedX - sine * shiftedY + center.dx,
      sine * shiftedX + cosine * shiftedY + center.dy,
    );
  }

  PdfTransform scaledAround({
    required double scaleX,
    required double scaleY,
    required Offset center,
  }) => PdfTransform(
    scaleX * a,
    scaleY * b,
    scaleX * c,
    scaleY * d,
    scaleX * (translateX - center.dx) + center.dx,
    scaleY * (translateY - center.dy) + center.dy,
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
