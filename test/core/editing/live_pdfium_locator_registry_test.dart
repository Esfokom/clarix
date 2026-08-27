import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/editing/live_pdfium_editor_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const locator = EditorPhysicalLocator(
    pageNumber: 1,
    objectPath: <int>[3],
    objectType: 'text',
    sourceFingerprint: 'source',
    objectRevision: 0,
  );

  test('resolves only the source revision it registered', () {
    final registry = LivePdfiumLocatorRegistry()
      ..register(
        sourceKey: 'page/1/text/3',
        sourceRevision: 'revision-a',
        locator: locator,
      );

    expect(
      registry.resolve(
        sourceKey: 'page/1/text/3',
        sourceRevision: 'revision-a',
      ),
      same(locator),
    );
    expect(
      () => registry.resolve(
        sourceKey: 'page/1/text/3',
        sourceRevision: 'revision-b',
      ),
      throwsA(isA<StateError>()),
    );
    registry.clear();
    expect(
      () => registry.resolve(
        sourceKey: 'page/1/text/3',
        sourceRevision: 'revision-a',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
