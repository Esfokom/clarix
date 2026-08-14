import 'dart:async';
import 'dart:typed_data';

import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_text_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('publishes and reloads only the latest serialized projection', () async {
    final fixture = await PdfTextFixture.singleBlock('Before');
    addTearDown(() => fixture.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(fixture.path);
    addTearDown(document.dispose);
    final mutator = _ControlledLiveMutator();
    final reloads = <List<int>>[];
    final coordinator = PdfNativeEditCoordinator(
      mutator: mutator,
      reloadPages: (_, pages) async => reloads.add(List<int>.of(pages)),
    );

    final first = coordinator.projectBlock(document, _request(1, 'First'));
    final second = coordinator.projectBlock(document, _request(2, 'Second'));

    await _waitFor(() => mutator.requests.length == 1);
    mutator.complete(0, _result(1, 'First'));
    await _waitFor(() => mutator.requests.length == 2);
    mutator.complete(1, _result(2, 'Second'));
    await Future.wait(<Future<void>>[first, second]);

    expect(mutator.requests.map((request) => request.editRevision), <int>[
      1,
      2,
    ]);
    expect(
      mutator.requests[1].nativeTarget?.text,
      'First',
      reason:
          'Each queued mutation must target the native object produced by the previous mutation.',
    );
    expect(coordinator.latestResult(document)?.block.text, 'Second');
    expect(reloads, <List<int>>[
      <int>[1],
    ]);
  });

  test('encodes through the live mutator and forgets document state', () async {
    final fixture = await PdfTextFixture.singleBlock('Before');
    addTearDown(() => fixture.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(fixture.path);
    addTearDown(document.dispose);
    final mutator = _ImmediateLiveMutator();
    final coordinator = PdfNativeEditCoordinator(
      mutator: mutator,
      reloadPages: (_, _) async {},
    );

    await coordinator.projectBlock(document, _request(3, 'Latest'));
    expect(coordinator.latestResult(document)?.appliedRevision, 3);
    expect(
      await coordinator.encode(document),
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    coordinator.forgetDocument(document);

    expect(coordinator.latestResult(document), isNull);
  });

  test('reloads the page prefix required by pdfrx for a later page', () async {
    final fixture = await PdfTextFixture.singleBlock('Before');
    addTearDown(() => fixture.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(fixture.path);
    addTearDown(document.dispose);
    final reloads = <List<int>>[];
    final coordinator = PdfNativeEditCoordinator(
      mutator: _ImmediateLiveMutator(affectedPages: const <int>[1, 3]),
      reloadPages: (_, pages) async => reloads.add(List<int>.of(pages)),
    );

    await coordinator.projectBlock(document, _request(4, 'Changed'));

    expect(reloads, <List<int>>[
      <int>[1, 2, 3],
    ]);
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Timed out waiting for asynchronous work.',
  );
}

PdfNativeProjectionRequest _request(int revision, String text) =>
    PdfNativeProjectionRequest(
      documentRevision: 'document-revision',
      editRevision: revision,
      block: _block(text),
    );

PdfNativeProjectionResult _result(int revision, String text) =>
    PdfNativeProjectionResult(
      requestedRevision: revision,
      appliedRevision: revision,
      block: _block(text),
      lines: <PdfNativeLine>[
        PdfNativeLine(
          range: PdfTextRange(0, text.length),
          bounds: const PdfBox(10, 20, 100, 32),
        ),
      ],
      characters: const <PdfNativeCharacterBox>[],
      affectedPages: const <int>[1],
    );

PdfTextBlock _block(String text) => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'document-revision',
  ),
  text: text,
  originalText: 'Before',
  runs: <PdfTextRun>[
    PdfTextRun(
      range: PdfTextRange(0, text.length),
      style: const PdfTextStyle(
        fontFamily: 'Helvetica',
        fontSize: 12,
        fillColorValue: 0xff000000,
        fontWeight: 400,
        italic: false,
        underline: false,
        baselineShift: 0,
        alignment: PdfTextAlignment.left,
        characterSpacing: 0,
        lineSpacing: 12,
        horizontalScaling: 1,
      ),
    ),
  ],
  bounds: const PdfBox(10, 20, 100, 32),
  transform: const PdfTransform(1, 0, 0, 1, 10, 20),
  baseline: 20,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: PdfTextCapability.values,
  readOnlyReason: null,
);

final class _ControlledLiveMutator implements PdfLiveDocumentMutator {
  final List<PdfNativeProjectionRequest> requests =
      <PdfNativeProjectionRequest>[];
  final List<Completer<PdfNativeProjectionResult>> _completers =
      <Completer<PdfNativeProjectionResult>>[];

  @override
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  }) {
    requests.add(request);
    final completer = Completer<PdfNativeProjectionResult>();
    _completers.add(completer);
    return completer.future;
  }

  void complete(int index, PdfNativeProjectionResult result) {
    _completers[index].complete(result);
  }

  @override
  Future<Uint8List> encodeLiveDocument({required PdfDocument document}) async =>
      Uint8List(0);
}

final class _ImmediateLiveMutator implements PdfLiveDocumentMutator {
  _ImmediateLiveMutator({this.affectedPages = const <int>[1]});

  final List<int> affectedPages;

  @override
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  }) async => PdfNativeProjectionResult(
    requestedRevision: request.editRevision,
    appliedRevision: request.editRevision,
    block: request.block,
    lines: const <PdfNativeLine>[],
    characters: const <PdfNativeCharacterBox>[],
    affectedPages: affectedPages,
  );

  @override
  Future<Uint8List> encodeLiveDocument({required PdfDocument document}) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}
