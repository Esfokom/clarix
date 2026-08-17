import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_page_object.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_object_transform_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rotation handle emits one rotate intent', (tester) async {
    final intents = <PdfEditIntent>[];
    await tester.pumpWidget(_harness(_object(), intents));
    await tester.tap(find.byKey(const Key('pdf-page-object-outline')));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('pdf-rotate-handle')),
      const Offset(30, 20),
    );

    expect(intents.whereType<RotatePdfPageObjectIntent>(), hasLength(1));
  });

  testWidgets('locked nested form shows no transform handles', (tester) async {
    await tester.pumpWidget(_harness(_object(locked: true), <PdfEditIntent>[]));
    await tester.tap(find.byKey(const Key('pdf-page-object-outline')));
    await tester.pump();

    expect(find.byKey(const Key('pdf-object-locked')), findsOneWidget);
    expect(find.byKey(const Key('pdf-rotate-handle')), findsNothing);
  });
}

Widget _harness(PdfPageObject object, List<PdfEditIntent> intents) =>
    MaterialApp(
      home: SizedBox(
        width: 400,
        height: 400,
        child: PdfObjectTransformOverlay(
          objects: <PdfPageObject>[object],
          rectForObject: (_) => const Rect.fromLTWH(100, 100, 120, 50),
          documentId: 'doc',
          documentRevision: 'rev',
          onIntent: intents.add,
          onPreview: (_, _) async {},
        ),
      ),
    );

PdfPageObject _object({bool locked = false}) => PdfPageObject(
  locator: PdfPageObjectLocator(
    pageNumber: 1,
    objectPath: locked ? const <int>[2, 0] : const <int>[2],
    type: locked ? PdfPageObjectType.form : PdfPageObjectType.image,
    contentDigest: 'content',
    geometryDigest: 'geometry',
    sourceRevision: 'rev',
  ),
  bounds: const PdfBox(0, 0, 120, 50),
  transform: const PdfTransform(1, 0, 0, 1, 100, 100),
  capabilities: locked
      ? const <PdfPageObjectCapability>{PdfPageObjectCapability.inspect}
      : const <PdfPageObjectCapability>{
          PdfPageObjectCapability.inspect,
          PdfPageObjectCapability.move,
          PdfPageObjectCapability.resize,
          PdfPageObjectCapability.rotate,
        },
  readOnlyReason: locked ? PdfPageObjectReadOnlyReason.sharedFormObject : null,
);
