import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models.dart';

class DocumentChunkStore {
  Future<Directory> _chunksDirectory() async {
    final Directory root = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(root.path, 'clarix', 'chunks'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> saveChunks(
    String documentId,
    List<PdfChunkRecord> chunks,
  ) async {
    final Directory dir = await _chunksDirectory();
    final File file = File(p.join(dir.path, '$documentId.json'));
    final List<Map<String, dynamic>> encoded = chunks
        .map(
          (PdfChunkRecord chunk) => <String, dynamic>{
            'id': chunk.id,
            'documentId': chunk.documentId,
            'title': chunk.title,
            'pageNumber': chunk.pageNumber,
            'chunkOrder': chunk.chunkOrder,
            'text': chunk.text,
            'sectionTitle': chunk.sectionTitle,
          },
        )
        .toList(growable: false);
    await file.writeAsString(jsonEncode(encoded));
  }

  Future<List<PdfChunkRecord>> readChunks(String documentId) async {
    final Directory dir = await _chunksDirectory();
    final File file = File(p.join(dir.path, '$documentId.json'));
    if (!await file.exists()) {
      return const <PdfChunkRecord>[];
    }
    final List<dynamic> decoded =
        jsonDecode(await file.readAsString()) as List<dynamic>;
    return decoded.map((dynamic item) {
      final Map<String, dynamic> json = item as Map<String, dynamic>;
      return PdfChunkRecord(
        id: json['id'] as String,
        documentId: json['documentId'] as String,
        title: json['title'] as String,
        pageNumber: json['pageNumber'] as int,
        chunkOrder: json['chunkOrder'] as int,
        text: json['text'] as String,
        sectionTitle: json['sectionTitle'] as String?,
      );
    }).toList(growable: false);
  }
}
