import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the cached tile for an identical revision key', () async {
    final producer = _FakeTileProducer();
    final renderer = LivePdfiumTileRenderer(producer: producer.call);
    const request = LivePdfiumTileRequest(
      pageNumber: 1,
      revision: 3,
      bounds: EditorPdfBox(left: 0, bottom: 0, right: 72, top: 72),
      width: 72,
      height: 72,
    );

    final first = await renderer.render(request);
    final second = await renderer.render(request);

    expect(second.rgbaBytes, orderedEquals(first.rgbaBytes));
    expect(producer.calls, 1);
  });

  test(
    'invalidates only intersecting stale tiles on the changed page',
    () async {
      final producer = _FakeTileProducer();
      final renderer = LivePdfiumTileRenderer(producer: producer.call);
      const changed = EditorPdfBox(left: 0, bottom: 0, right: 72, top: 72);
      const overlapping = LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 1,
        bounds: changed,
        width: 72,
        height: 72,
      );
      const otherPage = LivePdfiumTileRequest(
        pageNumber: 2,
        revision: 1,
        bounds: changed,
        width: 72,
        height: 72,
      );
      await renderer.render(overlapping);
      await renderer.render(otherPage);

      renderer.invalidate(pageNumber: 1, bounds: changed, revision: 2);

      expect(renderer.contains(overlapping), isFalse);
      expect(renderer.contains(otherPage), isTrue);
    },
  );
}

final class _FakeTileProducer {
  int calls = 0;

  Future<EditorDirtyTile> call(LivePdfiumTileRequest request) async {
    calls += 1;
    return EditorDirtyTile(
      pageNumber: request.pageNumber,
      revision: request.revision,
      bounds: request.bounds,
      width: request.width,
      height: request.height,
      rgbaBytes: <int>[calls, 0, 0, 255],
    );
  }
}
