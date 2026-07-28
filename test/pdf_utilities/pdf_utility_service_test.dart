import 'package:clarix/src/core/ffi/api.dart';
import 'package:clarix/src/features/utilities/application/pdf_utility_service.dart';
import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePdfComposeNative native;
  late List<String> opened;
  late PdfUtilityService service;

  setUp(() {
    native = _FakePdfComposeNative();
    opened = <String>[];
    service = PdfUtilityService(
      native: native,
      fileExists: (_) async => true,
      openPdfFiles: (List<String> paths) async => opened.addAll(paths),
    );
  });

  test(
    'extract delegates one selected source in requested page order',
    () async {
      final UtilityResult result = await service.extract(
        sourcePath: 'in.pdf',
        pages: const <int>[4, 2],
        outputPath: 'out.pdf',
      );

      expect(native.requests.single.sources.single.path, 'in.pdf');
      expect(
        native.requests.single.sources.single.pages.map(
          (BigInt page) => page.toInt(),
        ),
        <int>[4, 2],
      );
      expect(result.outputPath, 'out.pdf');
      expect(result.pageCount, 2);
    },
  );

  test('combine delegates every PDF source with all pages selected', () async {
    await service.combine(
      sources: const <String>['first.pdf', 'second.PDF'],
      outputPath: 'combined.pdf',
    );

    expect(
      native.requests.single.sources.map(
        (NativePdfSource source) => source.path,
      ),
      <String>['first.pdf', 'second.PDF'],
    );
    expect(
      native.requests.single.sources.map(
        (NativePdfSource source) => source.pages.isEmpty,
      ),
      <bool>[true, true],
    );
  });

  test('rejects unsafe inputs before invoking native composition', () async {
    await expectLater(
      service.combine(sources: const <String>[], outputPath: 'out.pdf'),
      throwsA(isA<UtilityFailure>()),
    );
    await expectLater(
      service.combine(
        sources: const <String>['same.pdf'],
        outputPath: 'same.pdf',
      ),
      throwsA(isA<UtilityFailure>()),
    );
    await expectLater(
      service.extract(
        sourcePath: 'in.txt',
        pages: const <int>[1],
        outputPath: 'out.pdf',
      ),
      throwsA(isA<UtilityFailure>()),
    );

    expect(native.requests, isEmpty);
  });

  test('converts native composition errors to utility failures', () async {
    native.error = StateError('native failed');

    await expectLater(
      service.combine(sources: const <String>['in.pdf'], outputPath: 'out.pdf'),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          contains('native failed'),
        ),
      ),
    );
  });

  test(
    'converts a native composition failure response to a utility failure',
    () async {
      native.message = 'Output could not be saved.';

      await expectLater(
        service.combine(
          sources: const <String>['in.pdf'],
          outputPath: 'out.pdf',
        ),
        throwsA(
          isA<UtilityFailure>().having(
            (UtilityFailure failure) => failure.message,
            'message',
            'Output could not be saved.',
          ),
        ),
      );
    },
  );

  test(
    'opens an existing generated PDF through the workspace callback',
    () async {
      await service.openGeneratedPdf('out.pdf');

      expect(opened, <String>['out.pdf']);
    },
  );

  test('does not open a generated PDF that is absent', () async {
    final PdfUtilityService missingOutputService = PdfUtilityService(
      native: native,
      fileExists: (_) async => false,
      openPdfFiles: (List<String> paths) async => opened.addAll(paths),
    );

    await expectLater(
      missingOutputService.openGeneratedPdf('out.pdf'),
      throwsA(isA<UtilityFailure>()),
    );
    expect(opened, isEmpty);
  });
}

final class _FakePdfComposeNative implements PdfComposeNative {
  final List<NativePdfComposeRequest> requests = <NativePdfComposeRequest>[];
  Object? error;
  String? message;

  @override
  Future<NativePdfComposeResponse> compose(
    NativePdfComposeRequest request,
  ) async {
    requests.add(request);
    if (error != null) {
      throw error!;
    }
    return NativePdfComposeResponse(
      outputPath: request.outputPath,
      pageCount: BigInt.from(
        request.sources.fold<int>(
          0,
          (int total, NativePdfSource source) =>
              total + (source.pages.isEmpty ? 1 : source.pages.length),
        ),
      ),
      message: message,
    );
  }
}
