import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/models.dart';

abstract class AnnotationSidecarPort {
  Future<List<DocumentAnnotation>> read(String documentPath);

  Future<void> write(String documentPath, List<DocumentAnnotation> annotations);
}

@immutable
class AnnotationDocumentState {
  const AnnotationDocumentState({
    this.annotations = const <DocumentAnnotation>[],
    this.isDirty = false,
  });

  const AnnotationDocumentState.empty() : this();

  final List<DocumentAnnotation> annotations;
  final bool isDirty;

  AnnotationDocumentState copyWith({
    List<DocumentAnnotation>? annotations,
    bool? isDirty,
  }) => AnnotationDocumentState(
    annotations: annotations ?? this.annotations,
    isDirty: isDirty ?? this.isDirty,
  );
}

class AnnotationController extends ChangeNotifier {
  AnnotationController({required this.documentPath, required this.sidecar});

  final String documentPath;
  final AnnotationSidecarPort sidecar;
  AnnotationDocumentState _state = const AnnotationDocumentState.empty();

  AnnotationDocumentState get state => _state;

  void addHighlight({
    required int pageNumber,
    required List<Rect> pageRects,
    required String selectedText,
  }) {
    _add(
      DocumentAnnotation(
        id: 'highlight_${DateTime.now().microsecondsSinceEpoch}',
        kind: AnnotationKind.highlight,
        pageNumber: pageNumber,
        pageRects: pageRects,
        selectedText: selectedText,
        note: null,
        colorValue: 0x66FFD54F,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  void addNote({required int pageNumber, required String note}) {
    _add(
      DocumentAnnotation(
        id: 'note_${DateTime.now().microsecondsSinceEpoch}',
        kind: AnnotationKind.note,
        pageNumber: pageNumber,
        pageRects: const <Rect>[],
        selectedText: '',
        note: note,
        colorValue: 0x66FFD54F,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> load() async {
    _state = AnnotationDocumentState(
      annotations: await sidecar.read(documentPath),
    );
    notifyListeners();
  }

  Future<void> save() async {
    await sidecar.write(documentPath, _state.annotations);
    _state = _state.copyWith(isDirty: false);
    notifyListeners();
  }

  void _add(DocumentAnnotation annotation) {
    _state = _state.copyWith(
      annotations: <DocumentAnnotation>[..._state.annotations, annotation],
      isDirty: true,
    );
    notifyListeners();
  }
}
