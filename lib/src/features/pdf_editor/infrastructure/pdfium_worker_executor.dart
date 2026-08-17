import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

typedef PdfiumWorkerInput<M> = ({int documentAddress, M message});
typedef PdfiumWorkerCallback<M, R> =
    FutureOr<R> Function(PdfiumWorkerInput<M> input);

/// Runs PDFium calls on the isolate that owns pdfrx's native document.
///
/// A PDFium document handle may be borrowed on the UI isolate, but invoking
/// PDFium there is unsafe: pdfrx installs synchronous font callbacks that are
/// isolate-local to its worker. Only the integer handle crosses isolates here;
/// the native callback itself always executes on the pdfrx worker.
final class PdfiumWorkerExecutor {
  const PdfiumWorkerExecutor();

  Future<R> run<M, R>({
    required PdfDocument document,
    required PdfiumWorkerCallback<M, R> callback,
    required M message,
  }) async {
    final documentAddress = await document.useNativeDocumentHandle(
      (address) => address,
    );
    return PdfrxEntryFunctions.instance.compute(callback, (
      documentAddress: documentAddress,
      message: message,
    ));
  }
}
