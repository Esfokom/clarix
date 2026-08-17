import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'page_surface.dart';

class PdfrxPageSurface extends ChangeNotifier implements PageSurface {
  PdfrxPageSurface(this._controller) {
    _controller.addListener(refresh);
  }

  final PdfViewerController _controller;
  final Object _identity = Object();
  PageSurfaceViewport _viewport = PageSurfaceViewport.empty();

  @override
  Object get identity => _identity;

  @override
  PageSurfaceViewport get viewport => _viewport;

  void refresh() {
    if (!_controller.isReady) return;
    final visibleRect = _controller.visibleRect;
    final visiblePages = <int>{};
    final layouts = _controller.layout.pageLayouts;
    for (var index = 0; index < layouts.length; index++) {
      if (layouts[index].overlaps(visibleRect)) visiblePages.add(index + 1);
    }
    final next = PageSurfaceViewport(
      visiblePages: visiblePages,
      visibleDocumentRect: visibleRect,
      zoom: _controller.currentZoom,
      anchorPage: _controller.pageNumber,
    );
    if (next == _viewport) return;
    _viewport = next;
    notifyListeners();
  }

  @override
  Rect pageRect(int pageNumber) =>
      _controller.layout.pageLayouts[_pageIndex(pageNumber)];

  @override
  Size pageSize(int pageNumber) {
    final page = _controller.pages[_pageIndex(pageNumber)];
    return Size(page.width, page.height);
  }

  @override
  Offset pageToDocument(int pageNumber, Offset pageOffset) =>
      PageSurfaceGeometry.pageToDocument(
        pageRect: pageRect(pageNumber),
        pageSize: pageSize(pageNumber),
        pageOffset: pageOffset,
      );

  @override
  Offset documentToPage(int pageNumber, Offset documentOffset) =>
      PageSurfaceGeometry.documentToPage(
        pageRect: pageRect(pageNumber),
        pageSize: pageSize(pageNumber),
        documentOffset: documentOffset,
      );

  @override
  Future<void> showPage(int pageNumber) =>
      _controller.goToPage(pageNumber: pageNumber);

  int _pageIndex(int pageNumber) {
    if (!_controller.isReady) {
      throw StateError('page surface is not ready');
    }
    if (pageNumber < 1 || pageNumber > _controller.pageCount) {
      throw RangeError.range(
        pageNumber,
        1,
        _controller.pageCount,
        'pageNumber',
      );
    }
    return pageNumber - 1;
  }

  @override
  void dispose() {
    _controller.removeListener(refresh);
    super.dispose();
  }
}
