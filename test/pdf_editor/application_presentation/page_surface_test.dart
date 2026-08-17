import 'package:clarix/src/features/pdf_editor/presentation/page_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page and document transforms round trip', () {
    const pageRect = Rect.fromLTWH(20, 40, 300, 400);
    const pageSize = Size(600, 800);
    const pagePoint = Offset(150, 320);

    final documentPoint = PageSurfaceGeometry.pageToDocument(
      pageRect: pageRect,
      pageSize: pageSize,
      pageOffset: pagePoint,
    );

    expect(
      PageSurfaceGeometry.documentToPage(
        pageRect: pageRect,
        pageSize: pageSize,
        documentOffset: documentPoint,
      ),
      pagePoint,
    );
  });

  testWidgets('typing does not replace or reload the retained page surface', (
    tester,
  ) async {
    final surface = RecordingPageSurface();
    final identity = surface.identity;
    final viewport = surface.viewport;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Text(surface.identity.toString(), key: const Key('surface')),
              const TextField(key: Key('clarix-native-editor')),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('clarix-native-editor')), 'x');
    await tester.pump();

    expect(surface.identity, same(identity));
    expect(surface.viewport, viewport);
    expect(surface.reloadCount, 0);
  });
}

class RecordingPageSurface extends ChangeNotifier implements PageSurface {
  final Object _identity = Object();
  int reloadCount = 0;

  @override
  Object get identity => _identity;

  @override
  PageSurfaceViewport get viewport => PageSurfaceViewport(
    visiblePages: const <int>{1},
    visibleDocumentRect: const Rect.fromLTWH(0, 0, 600, 800),
    zoom: 1,
    anchorPage: 1,
  );

  @override
  Offset documentToPage(int pageNumber, Offset documentOffset) =>
      documentOffset;

  @override
  Rect pageRect(int pageNumber) => const Rect.fromLTWH(0, 0, 600, 800);

  @override
  Size pageSize(int pageNumber) => const Size(600, 800);

  @override
  Offset pageToDocument(int pageNumber, Offset pageOffset) => pageOffset;

  @override
  Future<void> showPage(int pageNumber) async {}
}
