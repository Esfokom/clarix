import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows bundles the approved workspace-target Rust DLL', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(
      cmake,
      contains('rust/target/x86_64-pc-windows-msvc/release'),
    );
    expect(cmake, contains('rust/target/release'));
  });
}
