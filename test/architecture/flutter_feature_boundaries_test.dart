import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture_allowlist.dart';

const Set<String> _publicFeatures = <String>{
  'ai',
  'reader',
  'settings',
  'utilities',
  'workspace',
};

void main() {
  test('feature dependencies cross only through public entry points', () {
    final List<String> violations = <String>[];
    final RegExp directive = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );

    for (final FileSystemEntity entity in Directory(
      'lib/src/features',
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.path.replaceAll('\\', '/');
      final String? sourceFeature = _featureFromSource(source);
      if (sourceFeature == null) continue;

      for (final RegExpMatch match in directive.allMatches(
        entity.readAsStringSync(),
      )) {
        final String uri = match.group(1)!;
        final String? targetFeature = _featureFromUri(source, uri);
        if (targetFeature == null || targetFeature == sourceFeature) continue;

        final bool allowed = _isAllowedCrossFeatureImport(
          sourceFeature: sourceFeature,
          targetFeature: targetFeature,
          uri: uri,
        );
        if (!allowed && !temporaryFeatureBoundaryAllowlist.contains(source)) {
          violations.add('$source imports $uri');
        }
      }
    }

    violations.sort();
    expect(violations, isEmpty, reason: 'Use the target feature barrel.');
  });
}

String? _featureFromSource(String path) {
  final RegExpMatch? match = RegExp(
    r'^lib/src/features/([^/]+)/',
  ).firstMatch(path);
  return match?.group(1);
}

String? _featureFromUri(String source, String uri) {
  final RegExpMatch? packageMatch = RegExp(
    r'^package:clarix/src/features/([^/]+)/',
  ).firstMatch(uri);
  if (packageMatch != null) return packageMatch.group(1);
  if (!uri.startsWith('.')) return null;

  final Uri resolved = Uri.file(source).resolve(uri);
  final String normalized = resolved.path.replaceAll('\\', '/');
  return _featureFromSource(normalized);
}

bool _isAllowedCrossFeatureImport({
  required String sourceFeature,
  required String targetFeature,
  required String uri,
}) {
  if (!_publicFeatures.contains(targetFeature)) return true;
  final bool targetsBarrel = uri.endsWith('/$targetFeature.dart');
  if (!targetsBarrel) return false;

  if (sourceFeature == 'ai' && targetFeature == 'workspace') {
    return false;
  }
  if ((sourceFeature == 'reader' || sourceFeature == 'utilities') &&
      targetFeature == 'workspace') {
    return false;
  }
  return true;
}
