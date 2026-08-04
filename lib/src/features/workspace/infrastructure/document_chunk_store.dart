import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models.dart';

class DocumentChunkStore {
  DocumentChunkStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _defaultChunksDirectory;

  final Future<Directory> Function() _directoryProvider;

  static Future<Directory> _defaultChunksDirectory() async {
    Directory root;
    try {
      root = await getApplicationSupportDirectory();
    } catch (_) {
      root = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}clarix',
      );
    }
    final Directory dir = Directory(p.join(root.path, 'clarix', 'chunks'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _chunksDirectory() => _directoryProvider();

  Future<bool> hasChunks(String documentId) async {
    final Directory dir = await _chunksDirectory();
    return (await File(p.join(dir.path, '$documentId.jsonl')).exists()) ||
        await File(p.join(dir.path, '$documentId.json')).exists();
  }

  Future<int> replaceWithBatches(
    String documentId,
    Stream<List<PdfChunkRecord>> batches,
  ) async {
    final Directory dir = await _chunksDirectory();
    final File target = File(p.join(dir.path, '$documentId.jsonl'));
    final File temporary = File('${target.path}.tmp');
    final File backup = File('${target.path}.bak');
    final IOSink sink = temporary.openWrite();
    int count = 0;
    try {
      await for (final List<PdfChunkRecord> batch in batches) {
        for (final PdfChunkRecord chunk in batch) {
          sink.writeln(jsonEncode(_encode(chunk)));
          count++;
        }
      }
      await sink.flush();
      await sink.close();
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await target.exists()) {
        await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      if (await backup.exists()) {
        await backup.delete();
      }
      final File legacy = File(p.join(dir.path, '$documentId.json'));
      if (await legacy.exists()) {
        await legacy.delete();
      }
      return count;
    } catch (_) {
      await sink.close();
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  Future<void> saveChunks(
    String documentId,
    List<PdfChunkRecord> chunks,
  ) async {
    await replaceWithBatches(
      documentId,
      Stream<List<PdfChunkRecord>>.value(chunks),
    );
  }

  Future<List<PdfChunkRecord>> readChunks(String documentId) async {
    final Directory dir = await _chunksDirectory();
    final File jsonLines = File(p.join(dir.path, '$documentId.jsonl'));
    if (await jsonLines.exists()) {
      final List<PdfChunkRecord> output = <PdfChunkRecord>[];
      await for (final String line
          in jsonLines
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          continue;
        }
        output.add(_decode(jsonDecode(line) as Map<String, dynamic>));
      }
      return output;
    }

    final File legacy = File(p.join(dir.path, '$documentId.json'));
    if (!await legacy.exists()) {
      return const <PdfChunkRecord>[];
    }
    final List<dynamic> decoded =
        jsonDecode(await legacy.readAsString()) as List<dynamic>;
    return decoded
        .map((dynamic item) => _decode(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Map<String, dynamic> _encode(PdfChunkRecord chunk) => <String, dynamic>{
    'id': chunk.id,
    'documentId': chunk.documentId,
    'title': chunk.title,
    'pageNumber': chunk.pageNumber,
    'chunkOrder': chunk.chunkOrder,
    'text': chunk.text,
    'sectionTitle': chunk.sectionTitle,
  };

  PdfChunkRecord _decode(Map<String, dynamic> json) => PdfChunkRecord(
    id: json['id'] as String,
    documentId: json['documentId'] as String,
    title: json['title'] as String,
    pageNumber: json['pageNumber'] as int,
    chunkOrder: json['chunkOrder'] as int,
    text: json['text'] as String,
    sectionTitle: json['sectionTitle'] as String?,
  );
}
