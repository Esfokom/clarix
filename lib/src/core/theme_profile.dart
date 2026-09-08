import 'package:flutter/material.dart';

enum ClarixAccent {
  defaultAccent,
  gray,
  sepia,
  grass,
  cherry,
  sky,
  solarized,
  gruvbox,
  nord,
  custom,
}

/// The global interface typeface stored with other visual preferences.
enum ClarixFont { sans, serif, mono }

/// The persisted visual preferences shared by the application and reader.
///
/// Colours are stored as ARGB integers so the profile remains platform-neutral.
class ClarixThemeProfile {
  const ClarixThemeProfile({
    this.mode = ThemeMode.system,
    this.accent = ClarixAccent.defaultAccent,
    this.customAccentColor,
    this.highlightColor = defaultHighlightColor,
    this.highlightOpacity = defaultHighlightOpacity,
    this.customHighlightColors = const <int>[],
    this.readerBackgroundPath,
    this.readerBackgroundInverted = false,
    this.readerBookBackgroundOverride = false,
    this.font = ClarixFont.sans,
    this.fontScale = defaultFontScale,
  });

  static const int defaultHighlightColor = 0xFFFFD54F;
  static const double defaultHighlightOpacity = 0.4;
  static const int maxCustomHighlightColors = 10;
  static const double defaultFontScale = 1;
  static const double minimumFontScale = 0.9;
  static const double maximumFontScale = 1.3;

  /// The five colours that are always offered by the reader highlight picker.
  static const List<int> builtInHighlightColors = <int>[
    0xFFFFD54F,
    0xFF80CBC4,
    0xFF90CAF9,
    0xFFCE93D8,
    0xFFEF9A9A,
  ];

  final ThemeMode mode;
  final ClarixAccent accent;
  final int? customAccentColor;

  /// Active reader highlight colour, independent of the available palette.
  final int highlightColor;
  final double highlightOpacity;
  final List<int> customHighlightColors;

  final String? readerBackgroundPath;
  final bool readerBackgroundInverted;
  final bool readerBookBackgroundOverride;
  final ClarixFont font;
  final double fontScale;

  int get activeHighlightColor => highlightColor;
  List<int> get highlightPalette => <int>[
    ...builtInHighlightColors,
    ...customHighlightColors,
  ];
  bool get hasReaderBackground => readerBackgroundPath != null;

  factory ClarixThemeProfile.fromJson(Map<String, dynamic> json) {
    final customColors = _readColorList(json['customHighlightColors']);
    return ClarixThemeProfile(
      mode: _themeMode(json['mode']),
      accent: _accent(json['accent']),
      customAccentColor: _readOptionalColor(json['customAccentColor']),
      highlightColor:
          _readColor(json['activeHighlightColor']) ??
          _readColor(json['highlightColor']) ??
          defaultHighlightColor,
      highlightOpacity: _readOpacity(json['highlightOpacity']),
      customHighlightColors: customColors,
      readerBackgroundPath: _readNonEmptyString(json['readerBackgroundPath']),
      readerBackgroundInverted: json['readerBackgroundInverted'] == true,
      readerBookBackgroundOverride:
          json['readerBookBackgroundOverride'] == true,
      font:
          ClarixFont.values
              .where((ClarixFont candidate) => candidate.name == json['font'])
              .firstOrNull ??
          ClarixFont.sans,
      fontScale: _readFontScale(json['fontScale']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.name,
    'accent': accent.name,
    'customAccentColor': customAccentColor,
    // Keep the original name for backwards-compatible readers.
    'highlightColor': highlightColor,
    'activeHighlightColor': activeHighlightColor,
    'highlightOpacity': highlightOpacity,
    'customHighlightColors': customHighlightColors,
    'readerBackgroundPath': readerBackgroundPath,
    'readerBackgroundInverted': readerBackgroundInverted,
    'readerBookBackgroundOverride': readerBookBackgroundOverride,
    'font': font.name,
    'fontScale': fontScale,
  };

  ClarixThemeProfile copyWith({
    ThemeMode? mode,
    ClarixAccent? accent,
    int? customAccentColor,
    bool clearCustomAccentColor = false,
    int? highlightColor,
    double? highlightOpacity,
    List<int>? customHighlightColors,
    String? readerBackgroundPath,
    bool clearReaderBackgroundPath = false,
    bool? readerBackgroundInverted,
    bool? readerBookBackgroundOverride,
    ClarixFont? font,
    double? fontScale,
  }) => ClarixThemeProfile(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    customAccentColor: clearCustomAccentColor
        ? null
        : customAccentColor ?? this.customAccentColor,
    highlightColor: highlightColor ?? this.highlightColor,
    highlightOpacity: _readOpacity(highlightOpacity ?? this.highlightOpacity),
    customHighlightColors: customHighlightColors == null
        ? this.customHighlightColors
        : _normalizeColorList(customHighlightColors),
    readerBackgroundPath: clearReaderBackgroundPath
        ? null
        : readerBackgroundPath ?? this.readerBackgroundPath,
    readerBackgroundInverted:
        readerBackgroundInverted ?? this.readerBackgroundInverted,
    readerBookBackgroundOverride:
        readerBookBackgroundOverride ?? this.readerBookBackgroundOverride,
    font: font ?? this.font,
    fontScale: _readFontScale(fontScale ?? this.fontScale),
  );
}

ThemeMode _themeMode(Object? value) =>
    ThemeMode.values
        .where((ThemeMode candidate) => candidate.name == value)
        .firstOrNull ??
    ThemeMode.system;

ClarixAccent _accent(Object? value) =>
    ClarixAccent.values
        .where((ClarixAccent candidate) => candidate.name == value)
        .firstOrNull ??
    ClarixAccent.defaultAccent;

String? _readNonEmptyString(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

int? _readOptionalColor(Object? value) => _readColor(value);

int? _readColor(Object? value) {
  if (value is! int || value < 0 || value > 0xFFFFFFFF) return null;
  return value;
}

double _readOpacity(Object? value) {
  final opacity = value is num
      ? value.toDouble()
      : ClarixThemeProfile.defaultHighlightOpacity;
  if (!opacity.isFinite) return ClarixThemeProfile.defaultHighlightOpacity;
  return opacity.clamp(0.0, 1.0).toDouble();
}

double _readFontScale(Object? value) {
  final scale = value is num
      ? value.toDouble()
      : ClarixThemeProfile.defaultFontScale;
  if (!scale.isFinite) return ClarixThemeProfile.defaultFontScale;
  return scale
      .clamp(
        ClarixThemeProfile.minimumFontScale,
        ClarixThemeProfile.maximumFontScale,
      )
      .toDouble();
}

List<int> _readColorList(Object? value) {
  if (value is! List) return const <int>[];
  return _normalizeColorList(value.whereType<int>());
}

List<int> _normalizeColorList(Iterable<int> colors) => colors
    .where((int color) => _readColor(color) != null)
    .toSet()
    .take(ClarixThemeProfile.maxCustomHighlightColors)
    .toList(growable: false);

Color accentFor(ClarixAccent accent, {int? customAccentColor}) =>
    switch (accent) {
      ClarixAccent.defaultAccent => const Color(0xFFE4E4E7),
      ClarixAccent.gray => const Color(0xFF9CA3AF),
      ClarixAccent.sepia => const Color(0xFFD6A75E),
      ClarixAccent.grass => const Color(0xFF9CAF72),
      ClarixAccent.cherry => const Color(0xFFE4A0AB),
      ClarixAccent.sky => const Color(0xFF9BB9EA),
      ClarixAccent.solarized => const Color(0xFF2AA198),
      ClarixAccent.gruvbox => const Color(0xFFD8B870),
      ClarixAccent.nord => const Color(0xFF88C0D0),
      ClarixAccent.custom => Color(customAccentColor ?? 0xFFE4E4E7),
    };

class ClarixThemeTokens {
  const ClarixThemeTokens({
    required this.accent,
    required this.highlight,
    required this.readerBackgroundInverted,
    required this.readerBookBackgroundOverride,
  });

  final Color accent;
  final Color highlight;
  final bool readerBackgroundInverted;
  final bool readerBookBackgroundOverride;

  Color get accentSoft => accent.withValues(alpha: 0.14);
  Color get accentBorder => accent.withValues(alpha: 0.35);
}

ClarixThemeTokens resolveThemeTokens(ClarixThemeProfile profile) =>
    ClarixThemeTokens(
      accent: accentFor(
        profile.accent,
        customAccentColor: profile.customAccentColor,
      ),
      highlight: Color(
        profile.activeHighlightColor,
      ).withValues(alpha: profile.highlightOpacity),
      readerBackgroundInverted: profile.readerBackgroundInverted,
      readerBookBackgroundOverride: profile.readerBookBackgroundOverride,
    );
