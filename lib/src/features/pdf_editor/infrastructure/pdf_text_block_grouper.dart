import '../domain/pdf_text_types.dart';

final class PdfTextObjectGroup {
  PdfTextObjectGroup({required List<PdfTextObjectSnapshot> objects})
    : objects = List<PdfTextObjectSnapshot>.unmodifiable(objects),
      objectPaths = List<List<int>>.unmodifiable(
        objects.map((object) => object.objectPath).toList(growable: false),
      ),
      text = objects.map((object) => object.text).join('\n'),
      bounds = _union(objects.map((object) => object.bounds)),
      stableKey = _stableKey(objects);

  final List<PdfTextObjectSnapshot> objects;
  final List<List<int>> objectPaths;
  final String text;
  final PdfBox bounds;
  final String stableKey;

  @override
  bool operator ==(Object other) =>
      other is PdfTextObjectGroup && other.stableKey == stableKey;

  @override
  int get hashCode => stableKey.hashCode;
}

final class PdfTextBlockGrouper {
  const PdfTextBlockGrouper();

  List<PdfTextObjectGroup> group(List<PdfTextObjectSnapshot> snapshots) {
    if (snapshots.isEmpty) return const <PdfTextObjectGroup>[];
    final List<PdfTextObjectSnapshot> sorted = List.of(snapshots)
      ..sort(_compareObjects);
    final List<double> sizes =
        sorted.map((item) => item.style.fontSize).toList()..sort();
    final double medianSize = sizes[sizes.length ~/ 2];
    final double baselineTolerance = medianSize * 1.6;
    final double horizontalTolerance = medianSize * 2;
    final List<List<PdfTextObjectSnapshot>> groups =
        <List<PdfTextObjectSnapshot>>[];
    for (final PdfTextObjectSnapshot object in sorted) {
      if (groups.isEmpty ||
          !_belongs(
            groups.last.last,
            object,
            baselineTolerance,
            horizontalTolerance,
          )) {
        groups.add(<PdfTextObjectSnapshot>[object]);
      } else {
        groups.last.add(object);
      }
    }
    return List<PdfTextObjectGroup>.unmodifiable(
      groups.map((objects) => PdfTextObjectGroup(objects: objects)),
    );
  }

  bool _belongs(
    PdfTextObjectSnapshot previous,
    PdfTextObjectSnapshot next,
    double baselineTolerance,
    double horizontalTolerance,
  ) {
    if (previous.writingDirection != next.writingDirection) return false;
    if ((previous.baseline - next.baseline).abs() > baselineTolerance) {
      return false;
    }
    final bool horizontallyRelated =
        next.bounds.left <= previous.bounds.right + horizontalTolerance &&
        previous.bounds.left <= next.bounds.right + horizontalTolerance;
    return horizontallyRelated &&
        previous.style.fontFamily == next.style.fontFamily &&
        (previous.style.fontSize - next.style.fontSize).abs() <= 0.5;
  }
}

int _compareObjects(PdfTextObjectSnapshot left, PdfTextObjectSnapshot right) {
  final int direction = left.writingDirection.index.compareTo(
    right.writingDirection.index,
  );
  if (direction != 0) return direction;
  final int baseline = right.baseline.compareTo(left.baseline);
  if (baseline != 0) return baseline;
  final int horizontal = left.bounds.left.compareTo(right.bounds.left);
  if (horizontal != 0) return horizontal;
  return _comparePaths(left.objectPath, right.objectPath);
}

int _comparePaths(List<int> left, List<int> right) {
  final int length = left.length < right.length ? left.length : right.length;
  for (int index = 0; index < length; index++) {
    final int value = left[index].compareTo(right[index]);
    if (value != 0) return value;
  }
  return left.length.compareTo(right.length);
}

PdfBox _union(Iterable<PdfBox> boxes) {
  final Iterator<PdfBox> iterator = boxes.iterator;
  iterator.moveNext();
  double left = iterator.current.left;
  double bottom = iterator.current.bottom;
  double right = iterator.current.right;
  double top = iterator.current.top;
  while (iterator.moveNext()) {
    final PdfBox box = iterator.current;
    if (box.left < left) left = box.left;
    if (box.bottom < bottom) bottom = box.bottom;
    if (box.right > right) right = box.right;
    if (box.top > top) top = box.top;
  }
  return PdfBox(left, bottom, right, top);
}

String _stableKey(List<PdfTextObjectSnapshot> objects) => objects
    .map(
      (object) =>
          '${object.objectPath.join('.')}:${object.text}:${object.bounds.hashCode}:${object.style.hashCode}',
    )
    .join('|');
