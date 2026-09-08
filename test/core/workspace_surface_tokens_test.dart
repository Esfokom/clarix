import 'package:clarix/src/core/theme_profile.dart';
import 'package:clarix/src/core/workspace_surface_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Brightness brightness, Widget Function(BuildContext) builder) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(builder: builder),
    );

void main() {
  testWidgets('dark brightness resolves the dark base palette', (tester) async {
    late WorkspaceSurfaceTokens tokens;
    await tester.pumpWidget(
      _wrap(Brightness.dark, (context) {
        tokens = WorkspaceSurfaceTokens.fromProfile(
          const ClarixThemeProfile(),
          context,
        );
        return const SizedBox();
      }),
    );
    // panel/canvas/border are accent-tinted even at defaults, so only the
    // untinted fields (textStrong, viewerBackground, ...) are exact-matched.
    expect(tokens.textStrong.toARGB32(), 0xFFFAFAFA);
    expect(tokens.viewerBackground.toARGB32(), 0xFF292929);
  });

  testWidgets('light brightness resolves the light base palette', (tester) async {
    late WorkspaceSurfaceTokens tokens;
    await tester.pumpWidget(
      _wrap(Brightness.light, (context) {
        tokens = WorkspaceSurfaceTokens.fromProfile(
          const ClarixThemeProfile(),
          context,
        );
        return const SizedBox();
      }),
    );
    expect(tokens.textStrong.toARGB32(), 0xFF18181B);
    expect(tokens.viewerBackground.toARGB32(), 0xFFD4D4D8);
  });

  testWidgets('backdrop and warning stay constant across brightness', (tester) async {
    late WorkspaceSurfaceTokens dark;
    late WorkspaceSurfaceTokens light;
    await tester.pumpWidget(
      _wrap(Brightness.dark, (context) {
        dark = WorkspaceSurfaceTokens.fromProfile(
          const ClarixThemeProfile(),
          context,
        );
        return const SizedBox();
      }),
    );
    await tester.pumpWidget(
      _wrap(Brightness.light, (context) {
        light = WorkspaceSurfaceTokens.fromProfile(
          const ClarixThemeProfile(),
          context,
        );
        return const SizedBox();
      }),
    );
    expect(dark.backdrop, light.backdrop);
    expect(dark.warning, light.warning);
  });
}
