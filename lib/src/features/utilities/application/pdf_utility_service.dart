import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;

import '../../../core/ffi/api.dart';
import '../domain/utility_job.dart';

/// The native boundary used to compose PDF documents.
abstract interface class PdfComposeNative {
  Future<NativePdfComposeResponse> compose(NativePdfComposeRequest request);
}

/// Production implementation of [PdfComposeNative].
final class FrbPdfComposeNative implements PdfComposeNative {
  const FrbPdfComposeNative();

  @override
  Future<NativePdfComposeResponse> compose(NativePdfComposeRequest request) =>
      composePdfs(request: request);
}

typedef OpenPdfFiles = Future<void> Function(List<String> paths);
typedef FileExists = Future<bool> Function(String path);

/// Validates PDF composition requests and routes them to the native composer.
final class PdfUtilityService {
  PdfUtilityService({
    PdfComposeNative? native,
    FileExists? fileExists,
    OpenPdfFiles? openPdfFiles,
  }) : this._(
         native: native ?? const FrbPdfComposeNative(),
         fileExists: fileExists ?? _fileExistsOnDisk,
         openPdfFiles: openPdfFiles,
       );

  PdfUtilityService._({
    required this._native,
    required this._fileExists,
    this._openPdfFiles,
  });

  final PdfComposeNative _native;
  final FileExists _fileExists;
  final OpenPdfFiles? _openPdfFiles;

  /// Combines complete PDF source documents in their supplied order.
  Future<UtilityResult> combine({
    required List<String> sources,
    required String outputPath,
  }) async {
    if (sources.isEmpty) {
      throw const UtilityFailure('Select at least one PDF source.');
    }
    _validatePaths(sources: sources, outputPath: outputPath);
    return _compose(
      NativePdfComposeRequest(
        sources: sources
            .map(
              (String source) =>
                  NativePdfSource(path: source, pages: Uint64List(0)),
            )
            .toList(growable: false),
        outputPath: outputPath,
      ),
    );
  }

  /// Extracts the requested 1-based pages from a single PDF source.
  Future<UtilityResult> extract({
    required String sourcePath,
    required List<int> pages,
    required String outputPath,
  }) async {
    _validatePaths(sources: <String>[sourcePath], outputPath: outputPath);
    if (pages.isEmpty) {
      throw const UtilityFailure('Select at least one page.');
    }
    if (pages.any((int page) => page < 1)) {
      throw const UtilityFailure('Selected page numbers must be positive.');
    }
    return _compose(
      NativePdfComposeRequest(
        sources: <NativePdfSource>[
          NativePdfSource(path: sourcePath, pages: Uint64List.fromList(pages)),
        ],
        outputPath: outputPath,
      ),
    );
  }

  /// Opens a verified generated PDF in the workspace, if a callback is wired.
  Future<void> openGeneratedPdf(String outputPath) async {
    _validatePdfPath(outputPath, label: 'Output');
    if (!await _fileExists(outputPath)) {
      throw UtilityFailure('Generated PDF was not found: $outputPath');
    }
    final OpenPdfFiles? openPdfFiles = _openPdfFiles;
    if (openPdfFiles == null) {
      throw const UtilityFailure('PDF workspace opening is unavailable.');
    }
    await openPdfFiles(<String>[outputPath]);
  }

  Future<UtilityResult> _compose(NativePdfComposeRequest request) async {
    try {
      final NativePdfComposeResponse response = await _native.compose(request);
      final String? message = response.message;
      if (message != null && message.isNotEmpty) {
        throw UtilityFailure(message);
      }
      return UtilityResult(
        outputPath: response.outputPath,
        pageCount: response.pageCount.toInt(),
      );
    } on UtilityFailure {
      rethrow;
    } catch (error) {
      throw UtilityFailure('Could not compose PDF: $error');
    }
  }

  void _validatePaths({
    required List<String> sources,
    required String outputPath,
  }) {
    _validatePdfPath(outputPath, label: 'Output');
    for (final String source in sources) {
      _validatePdfPath(source, label: 'Source');
      if (_samePath(source, outputPath)) {
        throw const UtilityFailure(
          'The output PDF must be different from every source PDF.',
        );
      }
    }
  }

  void _validatePdfPath(String value, {required String label}) {
    if (value.trim().isEmpty) {
      throw UtilityFailure('$label PDF path is required.');
    }
    if (path.extension(value).toLowerCase() != '.pdf') {
      throw UtilityFailure('$label files must use the .pdf extension.');
    }
  }

  bool _samePath(String first, String second) {
    String normalize(String value) => path.normalize(path.absolute(value));
    final String normalizedFirst = normalize(first);
    final String normalizedSecond = normalize(second);
    return Platform.isWindows
        ? normalizedFirst.toLowerCase() == normalizedSecond.toLowerCase()
        : normalizedFirst == normalizedSecond;
  }

  static Future<bool> _fileExistsOnDisk(String outputPath) =>
      File(outputPath).exists();
}
