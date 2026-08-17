import 'dart:io';

final class WindowsFontRegistration {
  const WindowsFontRegistration({
    required this.family,
    required this.registeredPath,
  });

  final String family;
  final String registeredPath;
}

Set<String> windowsFontDirectories(Map<String, String> environment) {
  final systemRoot = environment['WINDIR'] ?? environment['SystemRoot'];
  final localAppData = environment['LOCALAPPDATA'];
  return <String>{
    if (systemRoot != null && systemRoot.isNotEmpty) '$systemRoot\\Fonts',
    if (localAppData != null && localAppData.isNotEmpty)
      '$localAppData\\Microsoft\\Windows\\Fonts',
  };
}

bool isSupportedFontPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.ttf') ||
      lower.endsWith('.otf') ||
      lower.endsWith('.ttc');
}

String? resolveRegisteredFontPath(
  String registeredPath,
  Iterable<String> directories, {
  required bool Function(String path) exists,
}) {
  final normalized = registeredPath.replaceAll('/', r'\');
  final absolute =
      RegExp(r'^[A-Za-z]:\\').hasMatch(normalized) ||
      normalized.startsWith(r'\\');
  if (absolute) return exists(normalized) ? normalized : null;
  for (final directory in directories) {
    final candidate =
        '${directory.replaceAll(RegExp(r'\\+$'), '')}\\$normalized';
    if (exists(candidate)) return candidate;
  }
  return null;
}

List<WindowsFontRegistration> parseWindowsFontRegistry(String output) {
  final registrations = <WindowsFontRegistration>[];
  final valueLine = RegExp(r'^\s*(.*?)\s+REG_(?:EXPAND_)?SZ\s+(.+?)\s*$');
  final suffix = RegExp(
    r'\s*\((?:TrueType|OpenType)\)\s*$',
    caseSensitive: false,
  );
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = valueLine.firstMatch(line);
    if (match == null) continue;
    final registeredPath = match.group(2)!.trim();
    if (!isSupportedFontPath(registeredPath)) continue;
    final family = match.group(1)!.replaceFirst(suffix, '').trim();
    if (family.isEmpty) continue;
    registrations.add(
      WindowsFontRegistration(family: family, registeredPath: registeredPath),
    );
  }
  return registrations;
}

final class WindowsFontSource {
  const WindowsFontSource();

  static const _keys = <String>[
    r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
    r'HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
  ];

  Future<List<WindowsFontRegistration>> registrations() async {
    if (!Platform.isWindows) return const <WindowsFontRegistration>[];
    final result = <WindowsFontRegistration>[];
    for (final key in _keys) {
      final process = await Process.run('reg.exe', <String>['query', key]);
      if (process.exitCode == 0) {
        result.addAll(parseWindowsFontRegistry(process.stdout.toString()));
      }
    }
    return result;
  }
}
