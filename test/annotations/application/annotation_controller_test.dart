import 'dart:ui';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/annotations/application/annotation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changes remain in memory until save succeeds', () async {
    final _RecordingSidecar sidecar = _RecordingSidecar();
    final AnnotationController controller = AnnotationController(
      documentPath: r'C:\documents\paper.pdf',
      sidecar: sidecar,
    );

    controller.addHighlight(
      pageNumber: 1,
      pageRects: const <Rect>[Rect.fromLTWH(10, 12, 80, 14)],
      selectedText: 'Clarix',
    );

    expect(controller.state.isDirty, isTrue);
    expect(sidecar.writes, isEmpty);

    await controller.save();

    expect(controller.state.isDirty, isFalse);
    expect(sidecar.writes, hasLength(1));
    expect(sidecar.writes.single.path, r'C:\documents\paper.pdf');
    expect(sidecar.writes.single.annotations.single.selectedText, 'Clarix');
  });

  test('a save failure preserves dirty annotations for retry', () async {
    final AnnotationController controller = AnnotationController(
      documentPath: r'C:\documents\paper.pdf',
      sidecar: _RecordingSidecar(shouldFail: true),
    );
    controller.addNote(pageNumber: 2, note: 'Review this diagram.');

    await expectLater(controller.save(), throwsStateError);

    expect(controller.state.isDirty, isTrue);
    expect(controller.state.annotations.single.note, 'Review this diagram.');
  });
}

class _RecordingSidecar implements AnnotationSidecarPort {
  _RecordingSidecar({this.shouldFail = false});

  final bool shouldFail;
  final List<_Write> writes = <_Write>[];

  @override
  Future<List<DocumentAnnotation>> read(String documentPath) async =>
      const <DocumentAnnotation>[];

  @override
  Future<void> write(
    String documentPath,
    List<DocumentAnnotation> annotations,
  ) async {
    if (shouldFail) throw StateError('sidecar unavailable');
    writes.add(_Write(documentPath, annotations));
  }
}

class _Write {
  const _Write(this.path, this.annotations);

  final String path;
  final List<DocumentAnnotation> annotations;
}
