import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_inspection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  test(
    'controller routes Phase 2 workflows through the native session',
    () async {
      final harness = NativeEditorTestHarness(text: 'Find this');
      await harness.open();

      final search = await harness.controller.searchDocument(query: 'Find');
      expect(search.matches.single.quotedText, 'Find this');
      expect((await harness.controller.compatibilityReport()).editableCount, 1);

      const annotation = EditorAnnotation(
        objectId: 'annotation-1',
        pageId: 'page-1',
        bounds: EditorPdfBox(left: 1, bottom: 2, right: 3, top: 4),
        kind: EditorAnnotationKind.comment,
        anchorKind: EditorAnnotationAnchorKind.pagePoint,
        anchorX: 1,
        anchorY: 2,
        body: 'Review this',
      );
      await harness.controller.createAnnotation(annotation);
      expect(
        (await harness.controller.annotationDetails(annotation.objectId)).body,
        'Review this',
      );
      final deleted = await harness.controller.deleteAnnotation(
        annotation.objectId,
      );
      expect(deleted.removedObjectIds, <String>[annotation.objectId]);
      expect(harness.controller.state.revision, 2);
      await harness.controller.close();
    },
  );
}
