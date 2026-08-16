import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/editing/editor_command_id.dart';
import '../../../../core/editing/editor_bridge_types.dart';
import 'editor_session_gateway.dart';

enum Phase1RecoveryProbeMode { acceptThenWait, verify }

enum Phase1RecoveryKillWindow { acceptedCommand, walCheckpoint }

class Phase1RecoveryProbeInvocation {
  const Phase1RecoveryProbeInvocation({
    required this.mode,
    required this.fixturePath,
    required this.projectRootPath,
    required this.seed,
    required this.markerPath,
    this.killWindow = Phase1RecoveryKillWindow.acceptedCommand,
  });

  final Phase1RecoveryProbeMode mode;
  final String fixturePath;
  final String projectRootPath;
  final int seed;
  final String markerPath;
  final Phase1RecoveryKillWindow killWindow;

  static Phase1RecoveryProbeInvocation? tryParse(List<String> arguments) {
    final accept = arguments.contains('--phase1-recovery-probe');
    final verify = arguments.contains('--phase1-recovery-verify');
    if (!accept && !verify) return null;
    if (accept == verify) {
      throw const FormatException(
        'exactly one recovery probe mode is required',
      );
    }
    final fixture = _value(arguments, '--fixture');
    final seed = int.tryParse(_value(arguments, '--seed'));
    if (seed == null || seed < 0) {
      throw const FormatException('recovery probe seed must be non-negative');
    }
    return Phase1RecoveryProbeInvocation(
      mode: accept
          ? Phase1RecoveryProbeMode.acceptThenWait
          : Phase1RecoveryProbeMode.verify,
      fixturePath: fixture,
      projectRootPath: _value(arguments, '--project-root'),
      seed: seed,
      markerPath: _value(
        arguments,
        accept ? '--accepted-marker' : '--recovered-marker',
      ),
      killWindow: _killWindow(arguments),
    );
  }

  static Phase1RecoveryKillWindow _killWindow(List<String> arguments) {
    if (!arguments.contains('--kill-window')) {
      return Phase1RecoveryKillWindow.acceptedCommand;
    }
    return switch (_value(arguments, '--kill-window')) {
      'accepted-command' => Phase1RecoveryKillWindow.acceptedCommand,
      'wal-checkpoint' => Phase1RecoveryKillWindow.walCheckpoint,
      final value => throw FormatException(
        'unsupported recovery probe kill window: $value',
      ),
    };
  }

  static String _value(List<String> arguments, String name) {
    final index = arguments.indexOf(name);
    if (index < 0 || index + 1 >= arguments.length) {
      throw FormatException('missing recovery probe argument: $name');
    }
    return arguments[index + 1];
  }
}

class Phase1RecoveryProbe {
  const Phase1RecoveryProbe(this.gateway);

  final EditorSessionGateway gateway;

  Future<void> run(
    Phase1RecoveryProbeInvocation invocation, {
    bool waitForTermination = true,
  }) async {
    final metadata = await gateway.open(invocation.fixturePath);
    var object = await _firstEditableObject(metadata);
    var revision = metadata.revision;

    if (invocation.mode == Phase1RecoveryProbeMode.acceptThenWait) {
      for (var index = 0; index <= invocation.seed; index += 1) {
        final replacement = 'clarix-phase1-${invocation.seed}-$index';
        final result = await gateway.submit(
          EditorCommandRequest(
            commandId: newEditorCommandId(),
            baseRevision: revision,
            payload: EditorCommand(
              kind: EditorCommandKind.replaceTextRange,
              objectId: object.objectId,
              start: 0,
              end: object.text!.codeUnits.length,
              replacement: replacement,
            ),
          ),
        );
        if (!result.durable) {
          throw StateError('probe command was acknowledged without durability');
        }
        revision = result.committedRevision;
        String? canonicalText;
        for (final patch in result.objectPatches) {
          if (patch.objectId == object.objectId && patch.text != null) {
            canonicalText = patch.text;
            break;
          }
        }
        object = EditorSceneObject(
          kind: object.kind,
          objectId: object.objectId,
          pageId: object.pageId,
          text: canonicalText ?? replacement,
          bounds: object.bounds,
          transform: object.transform,
          capability: object.capability,
          capabilityReason: object.capabilityReason,
          modifiedRevision: revision,
          runs: object.runs,
          characterBoxes: object.characterBoxes,
          layout: object.layout,
          fontFingerprint: object.fontFingerprint,
          fontAssetHandle: object.fontAssetHandle,
        );
      }
    }

    await _writeMarker(invocation.markerPath, revision, object);
    if (invocation.mode == Phase1RecoveryProbeMode.acceptThenWait &&
        invocation.killWindow == Phase1RecoveryKillWindow.walCheckpoint) {
      await gateway.close();
      return;
    }
    if (invocation.mode == Phase1RecoveryProbeMode.acceptThenWait &&
        waitForTermination) {
      await Completer<void>().future;
    }
    await gateway.close();
  }

  Future<EditorSceneObject> _firstEditableObject(
    EditorSessionMetadata metadata,
  ) async {
    for (var page = 1; page <= metadata.pageCount; page += 1) {
      final scene = await gateway.requestPage(page, metadata.revision);
      for (final object in scene.objects) {
        if (object.kind == EditorSceneObjectKind.text &&
            object.capability == 'editable' &&
            object.text != null) {
          return object;
        }
      }
    }
    throw StateError('fixture has no editable text object');
  }

  Future<void> _writeMarker(
    String markerPath,
    int revision,
    EditorSceneObject object,
  ) async {
    final textHash = sha256.convert(utf8.encode(object.text!)).toString();
    await File(markerPath).writeAsString(
      jsonEncode(<String, Object>{
        'revision': revision,
        'textSha256': textHash,
        'objectId': object.objectId,
      }),
      flush: true,
    );
  }
}
