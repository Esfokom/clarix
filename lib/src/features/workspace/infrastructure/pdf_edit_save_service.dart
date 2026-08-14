// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/pdf_edit_session.dart';
import '../domain/pdf_text_types.dart';

typedef PdfDraftWriter =
    Future<void> Function(File working, PdfEditingSession draft);
typedef PdfWorkingValidator = Future<void> Function(File working);
typedef PdfWorkingReplacer = Future<void> Function(File working, File source);

final class PdfSaveRequest {
  const PdfSaveRequest({
    required this.path,
    required this.sourceRevision,
    required this.draft,
  });

  final String path;
  final String sourceRevision;
  final PdfEditingSession draft;
}

final class PdfSaveOutcome {
  const PdfSaveOutcome({required this.newRevision});

  final String newRevision;
}

final class PdfEditSaveService {
  PdfEditSaveService({
    required PdfDraftWriter writeDraft,
    PdfWorkingValidator? validate,
    PdfWorkingReplacer? replace,
  }) : _writeDraft = writeDraft,
       _validate = validate ?? _validateExists,
       _replace = replace ?? _replaceWithBackup;

  final PdfDraftWriter _writeDraft;
  final PdfWorkingValidator _validate;
  final PdfWorkingReplacer _replace;

  Future<PdfSaveOutcome> save(PdfSaveRequest request) async {
    final source = File(request.path);
    final actualRevision = await _revision(source);
    if (actualRevision != request.sourceRevision) {
      throw PdfExternalRevisionFailure(
        expected: request.sourceRevision,
        actual: actualRevision,
      );
    }
    final working = File(_workingPath(source));
    try {
      await source.copy(working.path);
      await _writeDraft(working, request.draft);
      await _validate(working);
      final newRevision = await _revision(working);
      await _replace(working, source);
      return PdfSaveOutcome(newRevision: newRevision);
    } finally {
      if (await working.exists()) await working.delete();
    }
  }
}

Future<String> _revision(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

String _workingPath(File source) {
  final separator = Platform.pathSeparator;
  final name = source.uri.pathSegments.last;
  return '${source.parent.path}$separator.$name.clarix-edit-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf';
}

Future<void> _validateExists(File working) async {
  if (!await working.exists() || await working.length() == 0) {
    throw const PdfValidationFailure('The edited PDF is empty.');
  }
}

Future<void> _replaceWithBackup(File working, File source) async {
  final backup = File(
    '${source.parent.path}${Platform.pathSeparator}.${source.uri.pathSegments.last}'
    '.clarix-backup-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await source.rename(backup.path);
  } on FileSystemException catch (error) {
    throw PdfAtomicReplacementFailure(
      'Could not release the original PDF: ${error.message}',
    );
  }
  try {
    await working.rename(source.path);
  } catch (error) {
    if (await source.exists()) await source.delete();
    await backup.rename(source.path);
    throw PdfAtomicReplacementFailure(
      'Could not replace the original PDF: $error',
    );
  }
  try {
    await backup.delete();
  } on FileSystemException {
    // A stale backup is safer than risking the successfully installed PDF.
  }
}
