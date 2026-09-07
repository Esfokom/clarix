import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture_allowlist.dart';

const Set<String> _requiredEntryPoints = <String>{
  'lib/src/features/ai/ai.dart',
  'lib/src/features/reader/reader.dart',
  'lib/src/features/settings/settings.dart',
  'lib/src/features/utilities/utilities.dart',
  'lib/src/features/workspace/workspace.dart',
};

void main() {
  test('root features expose their public entry points', () {
    expect(
      temporarilyMissingFeatureEntryPoints.difference(_requiredEntryPoints),
      isEmpty,
      reason: 'Missing-entry exceptions must name required entry points.',
    );

    final List<String> missing =
        _requiredEntryPoints
            .where(
              (path) =>
                  !File(path).existsSync() &&
                  !temporarilyMissingFeatureEntryPoints.contains(path),
            )
            .toList()
          ..sort();
    final List<String> stale =
        temporarilyMissingFeatureEntryPoints
            .where((path) => File(path).existsSync())
            .toList()
          ..sort();

    expect(
      stale,
      isEmpty,
      reason: 'Remove created entry points from allowlist.',
    );
    expect(missing, isEmpty, reason: 'Create each public feature entry point.');
  });
}
