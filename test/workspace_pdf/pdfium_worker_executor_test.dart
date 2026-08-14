import 'dart:isolate';

import 'package:clarix/src/features/workspace/infrastructure/pdfium_worker_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

({int documentAddress, String? isolateName}) _workerIdentity(
  ({int documentAddress, Object? message}) input,
) => (
  documentAddress: input.documentAddress,
  isolateName: Isolate.current.debugName,
);

void main() {
  test('native PDF work runs on the pdfrx owning isolate', () async {
    final file = await PdfTextFixture.singleBlock('Worker ownership');
    addTearDown(() async => file.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(file.path);
    addTearDown(document.dispose);

    final identity = await const PdfiumWorkerExecutor()
        .run<Object?, ({int documentAddress, String? isolateName})>(
          document: document,
          callback: _workerIdentity,
          message: null,
        );

    expect(identity.documentAddress, isNonZero);
    expect(identity.isolateName, 'PdfrxEngineWorker');
  });
}
