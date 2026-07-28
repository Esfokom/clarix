import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/utility_job.dart';

typedef LibreOfficeFileExists = Future<bool> Function(String path);
typedef LibreOfficeProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef LibreOfficeTempDirectoryFactory =
    Future<Directory> Function(String prefix);

/// Boundary used for Office document sources.
abstract interface class OfficePdfConverter {
  Future<void> convert(String inputPath, String outputPath);
}

/// Discovers and runs a local, isolated LibreOffice headless process.
final class LibreOfficeConverter implements OfficePdfConverter {
  LibreOfficeConverter({
    this.configuredExecutable,
    LibreOfficeFileExists? fileExists,
    LibreOfficeProcessRunner? runProcess,
    LibreOfficeTempDirectoryFactory? createTempDirectory,
  }) : _fileExists = fileExists ?? _fileExistsOnDisk,
       _runProcess = runProcess ?? _runLibreOffice,
       _createTempDirectory =
           createTempDirectory ?? Directory.systemTemp.createTemp;

  static const List<String> standardWindowsExecutables = <String>[
    r'C:\Program Files\LibreOffice\program\soffice.com',
    r'C:\Program Files (x86)\LibreOffice\program\soffice.com',
  ];

  final String? configuredExecutable;
  final LibreOfficeFileExists _fileExists;
  final LibreOfficeProcessRunner _runProcess;
  final LibreOfficeTempDirectoryFactory _createTempDirectory;

  /// Returns the first configured or standard executable that exists.
  Future<String?> discover() async {
    final String? configured = configuredExecutable?.trim();
    final Iterable<String> candidates = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      ...standardWindowsExecutables,
    ];
    for (final String candidate in candidates) {
      if (await _fileExists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<void> convert(String inputPath, String outputPath) async {
    final String? executable = await discover();
    if (executable == null) {
      throw const UtilityFailure(
        'LibreOffice is required to convert DOCX, PPTX, and XLSX files. '
        'Install LibreOffice or select its soffice.com executable in settings.',
      );
    }
    if (path.extension(outputPath).toLowerCase() != '.pdf') {
      throw const UtilityFailure('Office conversion output must be a PDF.');
    }
    if (await File(outputPath).exists()) {
      throw UtilityFailure('The output PDF already exists: $outputPath');
    }

    Directory? workingDirectory;
    try {
      workingDirectory = await _createTempDirectory('clarix-libreoffice-');
      final Directory profile = Directory(
        path.join(workingDirectory.path, 'profile'),
      );
      final Directory converted = Directory(
        path.join(workingDirectory.path, 'converted'),
      );
      await profile.create(recursive: true);
      await converted.create(recursive: true);

      final List<String> arguments = <String>[
        '--headless',
        '--nologo',
        '--nolockcheck',
        '-env:UserInstallation=${profile.absolute.uri}',
        '--convert-to',
        'pdf',
        '--outdir',
        converted.path,
        inputPath,
      ];
      final ProcessResult result = await _runProcess(executable, arguments);
      if (result.exitCode != 0) {
        final String detail = result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : result.stdout.toString().trim();
        throw UtilityFailure(
          detail.isEmpty
              ? 'LibreOffice conversion failed with exit code '
                    '${result.exitCode}.'
              : 'LibreOffice conversion failed: $detail',
        );
      }

      final File expected = File(
        path.join(
          converted.path,
          '${path.basenameWithoutExtension(inputPath)}.pdf',
        ),
      );
      if (!await expected.exists()) {
        throw UtilityFailure(
          'LibreOffice did not create the expected PDF for '
          '${path.basename(inputPath)}.',
        );
      }
      await _publishFile(expected, outputPath);
    } on UtilityFailure {
      rethrow;
    } catch (error) {
      throw UtilityFailure(
        'Could not convert ${path.basename(inputPath)} with LibreOffice: '
        '$error',
      );
    } finally {
      if (workingDirectory != null && await workingDirectory.exists()) {
        try {
          await workingDirectory.delete(recursive: true);
        } on FileSystemException {
          // Conversion has already finished; best-effort cleanup is sufficient.
        }
      }
    }
  }

  static Future<void> _publishFile(File source, String outputPath) async {
    final Directory parent = File(outputPath).parent;
    if (!await parent.exists()) {
      throw UtilityFailure(
        'The selected output directory does not exist: ${parent.path}',
      );
    }
    final File pending = File(
      '$outputPath.clarix-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await source.copy(pending.path);
      if (await File(outputPath).exists()) {
        throw UtilityFailure('The output PDF already exists: $outputPath');
      }
      await pending.rename(outputPath);
    } finally {
      if (await pending.exists()) {
        await pending.delete();
      }
    }
  }

  static Future<bool> _fileExistsOnDisk(String candidate) =>
      File(candidate).exists();

  static Future<ProcessResult> _runLibreOffice(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);
}
