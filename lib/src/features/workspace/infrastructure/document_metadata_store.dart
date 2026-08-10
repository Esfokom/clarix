import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/models.dart';

class DocumentIdentityService {
  Future<DocumentIdentity> identify(
    String path, {
    int? pageCount,
    bool isEncrypted = false,
  }) async {
    final File file = File(path);
    final FileStat stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('PDF file is not available.', path);
    }
    final Digest digest = await sha256.bind(file.openRead()).first;
    return DocumentIdentity(
      fingerprint: digest.toString(),
      path: file.absolute.path,
      title: p.basename(path),
      byteLength: stat.size,
      modifiedAt: stat.modified.toUtc(),
      pageCount: pageCount,
      isEncrypted: isEncrypted,
    );
  }

  Future<bool> matches(String path, String fingerprint) async {
    try {
      return (await identify(path)).fingerprint == fingerprint;
    } on FileSystemException {
      return false;
    }
  }
}

class DocumentMetadataStore {
  DocumentMetadataStore({required Directory root})
    : _root = Directory(p.join(root.path, 'documents'));

  final Directory _root;

  Future<DocumentMetadata?> read(String fingerprint) async {
    _validateFingerprint(fingerprint);
    await _root.create(recursive: true);
    final File target = _fileFor(fingerprint);
    final File backup = _backupFor(fingerprint);
    if (!await target.exists() && await backup.exists()) {
      await backup.rename(target.path);
    }
    if (!await target.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return DocumentMetadata.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(DocumentMetadata metadata) async {
    _validateFingerprint(metadata.identity.fingerprint);
    await _root.create(recursive: true);
    final File target = _fileFor(metadata.identity.fingerprint);
    final File backup = _backupFor(metadata.identity.fingerprint);
    final File temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
    if (await backup.exists()) {
      await backup.delete();
    }
    if (await target.exists()) {
      await target.rename(backup.path);
    }
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> clearCache() async {
    if (await _root.exists()) await _root.delete(recursive: true);
  }

  File _fileFor(String fingerprint) =>
      File(p.join(_root.path, '$fingerprint.json'));

  File _backupFor(String fingerprint) =>
      File(p.join(_root.path, '$fingerprint.json.bak'));

  void _validateFingerprint(String fingerprint) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw ArgumentError.value(
        fingerprint,
        'fingerprint',
        'Expected a lowercase SHA-256 fingerprint.',
      );
    }
  }
}
