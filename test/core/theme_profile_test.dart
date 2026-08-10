import 'package:clarix/src/core/theme_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClarixThemeProfile persistence', () {
    test('round-trips all persisted reader and highlight preferences', () {
      const profile = ClarixThemeProfile(
        mode: ThemeMode.light,
        accent: ClarixAccent.custom,
        customAccentColor: 0xFF123456,
        readerBackgroundPath: '/backgrounds/paper.png',
        readerBackgroundInverted: true,
        readerBookBackgroundOverride: true,
        highlightColor: 0xFFABCDEF,
        highlightOpacity: 0.72,
        customHighlightColors: <int>[0xFF001122, 0xFF334455],
      );

      final restored = ClarixThemeProfile.fromJson(profile.toJson());

      expect(restored.mode, ThemeMode.light);
      expect(restored.accent, ClarixAccent.custom);
      expect(restored.customAccentColor, 0xFF123456);
      expect(restored.readerBackgroundPath, '/backgrounds/paper.png');
      expect(restored.readerBackgroundInverted, isTrue);
      expect(restored.readerBookBackgroundOverride, isTrue);
      expect(restored.highlightColor, 0xFFABCDEF);
      expect(restored.highlightOpacity, 0.72);
      expect(restored.customHighlightColors, <int>[0xFF001122, 0xFF334455]);
    });

    test('normalizes invalid persisted values and caps custom palette', () {
      final profile = ClarixThemeProfile.fromJson(<String, dynamic>{
        'mode': 'unsupported',
        'accent': 'unsupported',
        'customAccentColor': -1,
        'highlightColor': 0x1FFFFFFFF,
        'highlightOpacity': 4,
        'customHighlightColors': List<int>.generate(13, (index) => index),
      });

      expect(profile.mode, ThemeMode.system);
      expect(profile.accent, ClarixAccent.defaultAccent);
      expect(profile.customAccentColor, isNull);
      expect(profile.highlightColor, ClarixThemeProfile.defaultHighlightColor);
      expect(profile.highlightOpacity, 1);
      expect(profile.customHighlightColors, hasLength(10));
    });
  });

  test('token resolution uses a custom accent and derives highlight color', () {
    const profile = ClarixThemeProfile(
      accent: ClarixAccent.custom,
      customAccentColor: 0xFF102030,
      highlightColor: 0xFFABCDEF,
      highlightOpacity: 0.25,
    );

    final tokens = resolveThemeTokens(profile);

    expect(tokens.accent, const Color(0xFF102030));
    expect(tokens.highlight, const Color(0xFFABCDEF).withValues(alpha: 0.25));
  });
}
