import 'dart:io';
import 'dart:typed_data';

import 'windows_font_source.dart';

enum FontEmbeddingRights { installable, editable, previewPrint, restricted }

final class InstalledFontFace {
  const InstalledFontFace({
    required this.path,
    required this.family,
    required this.face,
    required this.weight,
    required this.scripts,
    this.italic = false,
    this.width = 5,
    this.embeddingRights = FontEmbeddingRights.installable,
    this.bitmapOnly = false,
  });

  final String path;
  final String family;
  final String face;
  final int weight;
  final bool italic;
  final int width;
  final Set<String> scripts;
  final FontEmbeddingRights embeddingRights;
  final bool bitmapOnly;

  bool get mayEmbed =>
      !bitmapOnly && embeddingRights != FontEmbeddingRights.restricted;
}

final class FontMatchRequest {
  const FontMatchRequest({
    required this.family,
    required this.weight,
    required this.italic,
    required this.text,
    this.width = 5,
  });

  final String family;
  final int weight;
  final bool italic;
  final String text;
  final int width;
}

final class FontMatch {
  const FontMatch({
    required this.font,
    required this.score,
    required this.requiresSubstitution,
  });

  final InstalledFontFace font;
  final double score;
  final bool requiresSubstitution;
}

final class FontMatchUnavailable implements Exception {
  const FontMatchUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

final class InstalledFontCatalog {
  InstalledFontCatalog.fromFaces(Iterable<InstalledFontFace> faces)
    : faces = List<InstalledFontFace>.unmodifiable(faces);

  final List<InstalledFontFace> faces;

  List<String> get families =>
      (faces.map((face) => face.family).toSet().toList()..sort()).toList();

  static Future<InstalledFontCatalog> scan({
    WindowsFontSource source = const WindowsFontSource(),
  }) async {
    final directoryPaths = windowsFontDirectories(Platform.environment);
    final directories = directoryPaths.map(Directory.new).toSet();
    final result = <InstalledFontFace>[];
    final seen = <String>{};
    final registeredPaths = <String>{};
    final registrations = await source.registrations();
    for (final registration in registrations) {
      final path = resolveRegisteredFontPath(
        registration.registeredPath,
        directoryPaths,
        exists: (candidate) => File(candidate).existsSync(),
      );
      if (path == null) continue;
      final identity =
          '${registration.family.toLowerCase()}|${path.toLowerCase()}';
      if (!seen.add(identity)) continue;
      registeredPaths.add(path.toLowerCase());
      try {
        result.add(
          await _faceFromFile(
            File(path),
            registeredFamily: registration.family,
          ),
        );
      } on FileSystemException {
        // A registered font can disappear or become inaccessible during scan.
      }
    }
    for (final directory in directories) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !isSupportedFontPath(entity.path)) continue;
        if (registeredPaths.contains(entity.path.toLowerCase())) continue;
        final identity = '|${entity.path.toLowerCase()}';
        if (!seen.add(identity)) continue;
        try {
          result.add(await _faceFromFile(entity));
        } on FileSystemException {
          // A system font can disappear or become inaccessible during a scan.
        }
      }
    }
    return InstalledFontCatalog.fromFaces(result);
  }

  FontMatch match(FontMatchRequest request) {
    final requiredScripts = _scriptsFor(request.text);
    final candidates =
        faces
            .where(
              (face) =>
                  face.mayEmbed && requiredScripts.every(face.scripts.contains),
            )
            .map((face) => (font: face, score: _score(face, request)))
            .toList()
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            return score != 0
                ? score
                : left.font.path.toLowerCase().compareTo(
                    right.font.path.toLowerCase(),
                  );
          });
    if (candidates.isEmpty) {
      throw FontMatchUnavailable(
        'No installed embeddable font supports ${requiredScripts.join(', ')}.',
      );
    }
    final best = candidates.first;
    return FontMatch(
      font: best.font,
      score: best.score,
      requiresSubstitution:
          _normalizeFamily(best.font.family) !=
          _normalizeFamily(request.family),
    );
  }

  static double _score(InstalledFontFace face, FontMatchRequest request) {
    final requested = _normalizeFamily(request.family);
    final candidate = _normalizeFamily(face.family);
    var score = candidate == requested
        ? 1000.0
        : _sameFamilyClass(candidate, requested)
        ? 500.0
        : 0.0;
    score += 200 - (face.weight - request.weight).abs() / 5;
    score += face.italic == request.italic ? 100 : 0;
    score += 50 - (face.width - request.width).abs() * 10;
    return score;
  }
}

Future<InstalledFontFace> _faceFromFile(
  File file, {
  String? registeredFamily,
}) async {
  final bytes = await file.readAsBytes();
  final stem = file.uri.pathSegments.last.replaceFirst(
    RegExp(r'\.(ttf|otf)$', caseSensitive: false),
    '',
  );
  final lower = stem.toLowerCase();
  final bold = lower.contains('bold') || lower.endsWith('bd');
  final italic = lower.contains('italic') || lower.contains('oblique');
  return InstalledFontFace(
    path: file.path,
    family:
        registeredFamily ??
        stem
            .replaceAll(
              RegExp(
                r'[-_](bold|italic|oblique|regular).*$',
                caseSensitive: false,
              ),
              '',
            )
            .trim(),
    face: bold && italic
        ? 'Bold Italic'
        : bold
        ? 'Bold'
        : italic
        ? 'Italic'
        : 'Regular',
    weight: bold ? 700 : 400,
    italic: italic,
    scripts: const <String>{
      'Latin',
      'Cyrillic',
      'Greek',
      'Arabic',
      'Hebrew',
      'CJK',
      'Other',
    },
    embeddingRights: _embeddingRights(bytes),
  );
}

FontEmbeddingRights _embeddingRights(Uint8List bytes) {
  if (bytes.length < 12) return FontEmbeddingRights.restricted;
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  for (var index = 0; index < tables; index++) {
    final offset = 12 + index * 16;
    if (offset + 16 > bytes.length) break;
    final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (tag != 'OS/2') continue;
    final tableOffset = data.getUint32(offset + 8);
    if (tableOffset + 10 > bytes.length) break;
    final fsType = data.getUint16(tableOffset + 8);
    if (fsType & 0x0002 != 0) return FontEmbeddingRights.restricted;
    if (fsType & 0x0008 != 0) return FontEmbeddingRights.editable;
    if (fsType & 0x0004 != 0) return FontEmbeddingRights.previewPrint;
    return FontEmbeddingRights.installable;
  }
  return FontEmbeddingRights.installable;
}

Set<String> _scriptsFor(String text) {
  final scripts = <String>{};
  for (final rune in text.runes) {
    if (rune <= 0x024f) {
      scripts.add('Latin');
    } else if (rune >= 0x0400 && rune <= 0x052f) {
      scripts.add('Cyrillic');
    } else if (rune >= 0x0600 && rune <= 0x06ff) {
      scripts.add('Arabic');
    } else if (rune >= 0x0590 && rune <= 0x05ff) {
      scripts.add('Hebrew');
    } else if (rune >= 0x2e80 && rune <= 0x9fff) {
      scripts.add('CJK');
    } else if (rune > 0x7f) {
      scripts.add('Other');
    }
  }
  return scripts.isEmpty ? <String>{'Latin'} : scripts;
}

String _normalizeFamily(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '')
    .replaceAll('mt', '');

bool _sameFamilyClass(String left, String right) {
  const sans = <String>{'arial', 'helvetica', 'calibri', 'segoeui'};
  const serif = <String>{'timesnewroman', 'times', 'georgia', 'cambria'};
  return (sans.contains(left) && sans.contains(right)) ||
      (serif.contains(left) && serif.contains(right));
}
