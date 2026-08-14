import 'dart:io';

import 'package:clarix/src/features/workspace/infrastructure/installed_font_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows scan includes registered system font families', () async {
    if (!Platform.isWindows) return;

    final catalog = await InstalledFontCatalog.scan();

    expect(catalog.families.length, greaterThan(20));
    expect(
      catalog.families.any((family) => family.toLowerCase().contains('arial')),
      isTrue,
    );
    expect(
      catalog.faces.any((face) => face.path.toLowerCase().endsWith('.ttc')),
      isTrue,
    );
  });

  test('closest compatible font prefers weight and required script', () {
    final catalog = InstalledFontCatalog.fromFaces(<InstalledFontFace>[
      const InstalledFontFace(
        path: 'arial.ttf',
        family: 'Arial',
        face: 'Regular',
        weight: 400,
        scripts: <String>{'Latin'},
      ),
      const InstalledFontFace(
        path: 'arialbd.ttf',
        family: 'Arial',
        face: 'Bold',
        weight: 700,
        scripts: <String>{'Latin'},
      ),
      const InstalledFontFace(
        path: 'arabic.ttf',
        family: 'Noto Sans Arabic',
        face: 'Regular',
        weight: 400,
        scripts: <String>{'Arabic'},
      ),
    ]);

    final match = catalog.match(
      const FontMatchRequest(
        family: 'Helvetica',
        weight: 700,
        italic: false,
        text: 'Revenue',
      ),
    );

    expect(match.font.family, 'Arial');
    expect(match.font.weight, 700);
    expect(match.requiresSubstitution, isTrue);
  });

  test('restricted and incompatible faces cannot be selected', () {
    final catalog = InstalledFontCatalog.fromFaces(<InstalledFontFace>[
      const InstalledFontFace(
        path: 'restricted.ttf',
        family: 'Restricted Sans',
        face: 'Regular',
        weight: 400,
        scripts: <String>{'Latin'},
        embeddingRights: FontEmbeddingRights.restricted,
      ),
      const InstalledFontFace(
        path: 'arabic.ttf',
        family: 'Arabic Sans',
        face: 'Regular',
        weight: 400,
        scripts: <String>{'Arabic'},
      ),
    ]);

    expect(
      () => catalog.match(
        const FontMatchRequest(
          family: 'Restricted Sans',
          weight: 400,
          italic: false,
          text: 'Revenue',
        ),
      ),
      throwsA(isA<FontMatchUnavailable>()),
    );
  });
}
