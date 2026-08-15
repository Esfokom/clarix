import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

@immutable
class PageSurfaceViewport {
  PageSurfaceViewport({
    required Set<int> visiblePages,
    required this.visibleDocumentRect,
    required this.zoom,
    required this.anchorPage,
  }) : visiblePages = Set<int>.unmodifiable(visiblePages);

  factory PageSurfaceViewport.empty() => PageSurfaceViewport(
    visiblePages: const <int>{},
    visibleDocumentRect: Rect.zero,
    zoom: 1,
    anchorPage: null,
  );

  final Set<int> visiblePages;
  final Rect visibleDocumentRect;
  final double zoom;
  final int? anchorPage;

  @override
  bool operator ==(Object other) =>
      other is PageSurfaceViewport &&
      setEquals(visiblePages, other.visiblePages) &&
      visibleDocumentRect == other.visibleDocumentRect &&
      zoom == other.zoom &&
      anchorPage == other.anchorPage;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(visiblePages),
    visibleDocumentRect,
    zoom,
    anchorPage,
  );
}

abstract interface class PageSurface implements Listenable {
  Object get identity;

  PageSurfaceViewport get viewport;

  Rect pageRect(int pageNumber);

  Size pageSize(int pageNumber);

  Offset pageToDocument(int pageNumber, Offset pageOffset);

  Offset documentToPage(int pageNumber, Offset documentOffset);

  Future<void> showPage(int pageNumber);
}

abstract final class PageSurfaceGeometry {
  static Offset pageToDocument({
    required Rect pageRect,
    required Size pageSize,
    required Offset pageOffset,
  }) => Offset(
    pageRect.left + pageOffset.dx * pageRect.width / pageSize.width,
    pageRect.top + pageOffset.dy * pageRect.height / pageSize.height,
  );

  static Offset documentToPage({
    required Rect pageRect,
    required Size pageSize,
    required Offset documentOffset,
  }) => Offset(
    (documentOffset.dx - pageRect.left) * pageSize.width / pageRect.width,
    (documentOffset.dy - pageRect.top) * pageSize.height / pageRect.height,
  );
}
