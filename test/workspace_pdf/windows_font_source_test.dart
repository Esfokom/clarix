import 'package:clarix/src/features/workspace/infrastructure/windows_font_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses SystemRoot when WINDIR is absent', () {
    final directories = windowsFontDirectories(<String, String>{
      'SystemRoot': r'C:\WINDOWS',
      'LOCALAPPDATA': r'C:\Users\Sam\AppData\Local',
    });

    expect(directories, <String>{
      r'C:\WINDOWS\Fonts',
      r'C:\Users\Sam\AppData\Local\Microsoft\Windows\Fonts',
    });
  });

  test('parses registered TrueType, OpenType, and collection entries', () {
    const output = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
    Arial (TrueType)    REG_SZ    arial.ttf
    Cambria & Cambria Math (TrueType)    REG_SZ    cambria.ttc
    Adobe Song Std (OpenType)    REG_SZ    C:\Fonts\AdobeSongStd.otf
''';

    final registrations = parseWindowsFontRegistry(output);

    expect(registrations.map((entry) => entry.family), <String>[
      'Arial',
      'Cambria & Cambria Math',
      'Adobe Song Std',
    ]);
    expect(registrations.map((entry) => entry.registeredPath), <String>[
      'arial.ttf',
      'cambria.ttc',
      r'C:\Fonts\AdobeSongStd.otf',
    ]);
  });

  test('recognizes TrueType collections as supported font containers', () {
    expect(isSupportedFontPath('cambria.ttc'), isTrue);
    expect(isSupportedFontPath('arial.ttf'), isTrue);
    expect(isSupportedFontPath('source.otf'), isTrue);
    expect(isSupportedFontPath('legacy.fon'), isFalse);
  });

  test('resolves relative registrations against known font directories', () {
    expect(
      resolveRegisteredFontPath('cambria.ttc', <String>[
        r'C:\WINDOWS\Fonts',
        r'C:\Users\Sam\Fonts',
      ], exists: (path) => path == r'C:\WINDOWS\Fonts\cambria.ttc'),
      r'C:\WINDOWS\Fonts\cambria.ttc',
    );
    expect(
      resolveRegisteredFontPath(r'D:\Fonts\custom.otf', <String>[
        r'C:\WINDOWS\Fonts',
      ], exists: (path) => path == r'D:\Fonts\custom.otf'),
      r'D:\Fonts\custom.otf',
    );
  });
}
