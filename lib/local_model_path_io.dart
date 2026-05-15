import 'dart:io';

import 'package:path/path.dart' as p;

String resolveLocalModelPath(String relativePath) {
  if (p.isAbsolute(relativePath)) {
    return relativePath;
  }

  final basePath = Directory.current.path;
  return basePath.endsWith(Platform.pathSeparator)
      ? '$basePath$relativePath'
      : '$basePath${Platform.pathSeparator}$relativePath';
}
