import 'dart:io';
import 'dart:ui';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/annotations/infrastructure/annotation_sidecar_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps annotation drafts beside the PDF until they are cleared',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'clarix-annotation-sidecar-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final String pdfPath =
          '${directory.path}${Platform.pathSeparator}paper.pdf';
      final AnnotationSidecarStore store = AnnotationSidecarStore();
      final DocumentAnnotation annotation = DocumentAnnotation(
        id: 'highlight_1',
        kind: AnnotationKind.highlight,
        pageNumber: 2,
        pageRects: const <Rect>[Rect.fromLTWH(8, 12, 80, 14)],
        selectedText: 'A saved draft',
        note: null,
        colorValue: 0x66FFD54F,
        createdAt: DateTime.utc(2026),
      );

      await store.write(
        pdfPath,
        annotations: <DocumentAnnotation>[annotation],
        bookmarks: <DocumentBookmark>[
          DocumentBookmark(
            id: 'bookmark_1',
            pageNumber: 2,
            label: 'Key page',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      final AnnotationSidecarDraft? restored = await store.read(pdfPath);
      expect(restored!.annotations, hasLength(1));
      expect(restored.annotations.single.id, annotation.id);
      expect(restored.annotations.single.selectedText, annotation.selectedText);
      expect(restored.bookmarks.single.label, 'Key page');

      await store.clear(pdfPath);

      expect(await store.read(pdfPath), isNull);
    },
  );
}
