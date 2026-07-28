import 'dart:io';

import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:clarix/src/features/utilities/infrastructure/libreoffice_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-office-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('reports LibreOffice as absent when no candidate exists', () async {
    final LibreOfficeConverter converter = LibreOfficeConverter(
      fileExists: (_) async => false,
    );

    expect(await converter.discover(), isNull);
  });

  test('prefers a configured executable before standard locations', () async {
    const String configured = 'D:/Portable/LibreOffice/program/soffice.com';
    final List<String> checked = <String>[];
    final LibreOfficeConverter converter = LibreOfficeConverter(
      configuredExecutable: configured,
      fileExists: (String candidate) async {
        checked.add(candidate);
        return candidate == configured;
      },
    );

    expect(await converter.discover(), configured);
    expect(checked, <String>[configured]);
  });

  test(
    'runs an isolated headless conversion and moves the expected PDF',
    () async {
      final Directory work = Directory(_path(root, 'work'));
      final File input = File(_path(root, 'Quarterly Report.docx'));
      final String outputPath = _path(root, 'finished.pdf');
      await input.writeAsString('fake docx');
      String executable = '';
      List<String> arguments = <String>[];

      final LibreOfficeConverter converter = LibreOfficeConverter(
        configuredExecutable: 'C:/LibreOffice/program/soffice.com',
        fileExists: (_) async => true,
        createTempDirectory: (_) async {
          await work.create();
          return work;
        },
        runProcess: (String command, List<String> args) async {
          executable = command;
          arguments = List<String>.of(args);
          final int outputIndex = args.indexOf('--outdir') + 1;
          await File(
            '${args[outputIndex]}${Platform.pathSeparator}Quarterly Report.pdf',
          ).writeAsBytes(<int>[37, 80, 68, 70]);
          return ProcessResult(42, 0, 'converted', '');
        },
      );

      await converter.convert(input.path, outputPath);

      expect(executable, 'C:/LibreOffice/program/soffice.com');
      expect(arguments.take(3), <String>[
        '--headless',
        '--nologo',
        '--nolockcheck',
      ]);
      expect(arguments[3], startsWith('-env:UserInstallation=file:///'));
      expect(arguments[4], '--convert-to');
      expect(arguments[5], 'pdf');
      expect(arguments[6], '--outdir');
      expect(arguments.last, input.path);
      expect(await File(outputPath).readAsBytes(), <int>[37, 80, 68, 70]);
      expect(await work.exists(), isFalse);
    },
  );

  test('gives actionable guidance when LibreOffice is unavailable', () async {
    final LibreOfficeConverter converter = LibreOfficeConverter(
      fileExists: (_) async => false,
    );

    await expectLater(
      converter.convert('report.docx', _path(root, 'report.pdf')),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          allOf(contains('LibreOffice'), contains('DOCX, PPTX, and XLSX')),
        ),
      ),
    );
  });

  test('process failure removes temporary output and reports stderr', () async {
    final Directory work = Directory(_path(root, 'failed-work'));
    final LibreOfficeConverter converter = LibreOfficeConverter(
      configuredExecutable: 'C:/LibreOffice/program/soffice.com',
      fileExists: (_) async => true,
      createTempDirectory: (_) async {
        await work.create();
        return work;
      },
      runProcess: (_, _) async =>
          ProcessResult(42, 7, '', 'source document is corrupt'),
    );
    final String output = _path(root, 'failed.pdf');

    await expectLater(
      converter.convert('corrupt.docx', output),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          contains('source document is corrupt'),
        ),
      ),
    );
    expect(await File(output).exists(), isFalse);
    expect(await work.exists(), isFalse);
  });

  test('successful exit without the expected PDF is a failure', () async {
    final Directory work = Directory(_path(root, 'missing-work'));
    final LibreOfficeConverter converter = LibreOfficeConverter(
      configuredExecutable: 'C:/LibreOffice/program/soffice.com',
      fileExists: (_) async => true,
      createTempDirectory: (_) async {
        await work.create();
        return work;
      },
      runProcess: (_, _) async => ProcessResult(42, 0, 'done', ''),
    );

    await expectLater(
      converter.convert('missing.xlsx', _path(root, 'missing.pdf')),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          contains('did not create the expected PDF'),
        ),
      ),
    );
    expect(await work.exists(), isFalse);
  });
}

String _path(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';
