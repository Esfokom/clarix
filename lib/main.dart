import 'dart:io';

import 'package:clarix/src/app.dart';
import 'package:clarix/src/core/boot.dart';
import 'package:clarix/src/core/clarix_rust_runtime.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/phase1_recovery_probe.dart';
import 'package:flutter/material.dart';

Future<void> main(List<String> arguments) async {
  final recoveryProbe = Phase1RecoveryProbeInvocation.tryParse(arguments);
  if (recoveryProbe != null) {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await ClarixRustRuntime.requireInitialized();
      await Phase1RecoveryProbe(
        BridgeEditorSessionGateway(),
      ).run(recoveryProbe);
    } catch (error, stackTrace) {
      stderr.writeln('Phase 1 recovery probe failed: $error');
      stderr.writeln(stackTrace);
      exitCode = 1;
    }
    return;
  }
  await bootstrapClarix();
  runApp(const ClarixApp());
}
