import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture_allowlist.dart';

void main() {
  test('hand-written production Dart files contain at most 800 lines', () {
    final Map<String, int> oversized = <String, int>{};
    final Set<String> discovered = <String>{};

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll('\\', '/');
      if (path.startsWith('lib/src/core/ffi/')) continue;
      discovered.add(path);
      final int lines = const LineSplitter()
          .convert(entity.readAsStringSync())
          .length;
      if (lines > 800 && !oversizedProductionDartAllowlist.contains(path)) {
        oversized[path] = lines;
      }
    }

    final List<String> stale = oversizedProductionDartAllowlist.where((path) {
      if (!discovered.contains(path)) return true;
      final int lines = const LineSplitter()
          .convert(File(path).readAsStringSync())
          .length;
      return lines <= 800;
    }).toList()..sort();

    expect(stale, isEmpty, reason: 'Remove stale/missing size exceptions.');
    expect(
      oversized,
      isEmpty,
      reason: 'Split each listed hand-written production file.',
    );
  });
}
