import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application source contains no Flutter Gemma reference', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source.toLowerCase(), isNot(contains('flutter_gemma')));
  });
}
