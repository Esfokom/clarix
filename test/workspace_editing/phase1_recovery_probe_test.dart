import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/phase1_recovery_probe.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses accepted and verification probe invocations', () {
    final accepted = Phase1RecoveryProbeInvocation.tryParse(const <String>[
      '--phase1-recovery-probe',
      '--fixture',
      'source.pdf',
      '--seed',
      '2',
      '--accepted-marker',
      'accepted.json',
    ])!;
    expect(accepted.mode, Phase1RecoveryProbeMode.acceptThenWait);
    expect(accepted.seed, 2);

    final verified = Phase1RecoveryProbeInvocation.tryParse(const <String>[
      '--phase1-recovery-verify',
      '--fixture',
      'source.pdf',
      '--seed',
      '2',
      '--recovered-marker',
      'recovered.json',
    ])!;
    expect(verified.mode, Phase1RecoveryProbeMode.verify);
    expect(verified.markerPath, 'recovered.json');
  });

  test('writes the last durable revision and text hash', () async {
    final directory = await Directory.systemTemp.createTemp('clarix-probe-');
    addTearDown(() => directory.delete(recursive: true));
    final marker = '${directory.path}${Platform.pathSeparator}accepted.json';
    final gateway = _FakeGateway();

    await Phase1RecoveryProbe(gateway).run(
      Phase1RecoveryProbeInvocation(
        mode: Phase1RecoveryProbeMode.acceptThenWait,
        fixturePath: 'source.pdf',
        seed: 2,
        markerPath: marker,
      ),
      waitForTermination: false,
    );

    final record = jsonDecode(await File(marker).readAsString());
    expect(record['revision'], 3);
    expect(
      record['textSha256'],
      sha256.convert(utf8.encode('clarix-phase1-2-2')).toString(),
    );
    expect(
      gateway.commandIds,
      everyElement(
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      ),
    );
    expect(gateway.closed, isTrue);
  });
}

class _FakeGateway implements EditorSessionGateway {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  var revision = 0;
  var text = 'A';
  var closed = false;
  final List<String> commandIds = <String>[];

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      const EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'session',
        documentId: 'document',
        sourceFingerprint: 'fingerprint',
        revision: 0,
        pageCount: 1,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async => EditorPageScene(
    schemaVersion: 1,
    pageId: 'page',
    pageNumber: 1,
    width: 100,
    height: 100,
    revision: revision,
    objects: <EditorSceneObject>[_object()],
  );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    commandIds.add(request.commandId);
    text = request.payload.replacement!;
    revision += 1;
    return EditorCommandResult(
      commandId: request.commandId,
      previousRevision: revision - 1,
      committedRevision: revision,
      durable: true,
      warnings: const <String>[],
      objectPatches: const <EditorObjectPatch>[],
    );
  }

  EditorSceneObject _object() => EditorSceneObject(
    kind: EditorSceneObjectKind.text,
    objectId: 'object',
    pageId: 'page',
    text: text,
    bounds: const EditorPdfBox(left: 0, bottom: 0, right: 10, top: 10),
    transform: const EditorAffineTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0),
    capability: 'editable',
    modifiedRevision: revision,
    runs: const <EditorTextRun>[],
  );

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async => _object();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();
}
