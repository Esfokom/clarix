import 'dart:convert';
import 'dart:io';

import '../../../core/models.dart';

class AnnotationSidecarDraft {
  const AnnotationSidecarDraft({
    required this.annotations,
    required this.bookmarks,
  });

  final List<DocumentAnnotation> annotations;
  final List<DocumentBookmark> bookmarks;
}

class AnnotationSidecarStore {
  Future<AnnotationSidecarDraft?> read(String documentPath) async {
    final File sidecar = _sidecarFor(documentPath);
    if (!await sidecar.exists()) {
      return null;
    }
    final Object? decoded = jsonDecode(await sidecar.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid annotation sidecar.');
    }
    final Object? annotationsValue = decoded['annotations'];
    final Object? bookmarksValue = decoded['bookmarks'];
    if (annotationsValue is! List<dynamic> ||
        bookmarksValue is! List<dynamic>) {
      throw const FormatException('Invalid annotation sidecar annotations.');
    }
    return AnnotationSidecarDraft(
      annotations: annotationsValue
          .map(
            (Object? item) =>
                DocumentAnnotation.fromJson(item! as Map<String, dynamic>),
          )
          .toList(growable: false),
      bookmarks: bookmarksValue
          .map(
            (Object? item) =>
                DocumentBookmark.fromJson(item! as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  Future<void> write(
    String documentPath, {
    required List<DocumentAnnotation> annotations,
    required List<DocumentBookmark> bookmarks,
  }) async {
    final File target = _sidecarFor(documentPath);
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object>{
        'annotations': annotations
            .map((DocumentAnnotation annotation) => annotation.toJson())
            .toList(growable: false),
        'bookmarks': bookmarks
            .map((DocumentBookmark bookmark) => bookmark.toJson())
            .toList(growable: false),
      }),
      flush: true,
    );
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }

  Future<void> clear(String documentPath) async {
    final File target = _sidecarFor(documentPath);
    if (await target.exists()) {
      await target.delete();
    }
  }

  File _sidecarFor(String documentPath) => File('$documentPath.clarix.json');
}
