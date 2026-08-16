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

  test('Phase 1 checks clean their isolated Cargo target', () {
    final script = File(
      'tool/editing_phase1/run_phase1_checks.ps1',
    ).readAsStringSync();

    expect(script, contains('build/editing_phase1/cargo-gate-target'));
    expect(script, contains(r'$env:CARGO_INCREMENTAL = "0"'));
    expect(script, contains('cargo clean --manifest-path rust/Cargo.toml'));
    expect(script, contains(r'--target-dir $gateCargoTarget'));
  });

  test('Phase 1 benchmarks record evidence before cleaning their target', () {
    final script = File(
      'tool/editing_phase1/run_phase1_benchmarks.ps1',
    ).readAsStringSync();

    expect(script, contains('build/editing_phase1/cargo-benchmark-target'));
    final recordIndex = script.indexOf('record_phase1_evidence.ps1');
    final cleanIndex = script.indexOf('cargo clean --manifest-path');
    expect(recordIndex, greaterThanOrEqualTo(0));
    expect(cleanIndex, greaterThan(recordIndex));
  });
}
