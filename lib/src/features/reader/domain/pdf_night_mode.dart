import 'package:flutter/material.dart';

/// Night Mode settings for PDF viewer canvas color transformation
enum PdfNightMode {
  off,
  inverted,
  smartDark,
}

extension PdfNightModeX on PdfNightMode {
  String get label => switch (this) {
        PdfNightMode.off => 'Normal Light',
        PdfNightMode.inverted => 'True Dark (Inverted)',
        PdfNightMode.smartDark => 'Smart Dark (Warm)',
      };

  IconData get icon => switch (this) {
        PdfNightMode.off => Icons.light_mode_outlined,
        PdfNightMode.inverted => Icons.dark_mode_outlined,
        PdfNightMode.smartDark => Icons.nightlight_round,
      };

  /// GPU ColorFilter matrix for instantaneous canvas transformation
  ColorFilter? get colorFilter {
    switch (this) {
      case PdfNightMode.off:
        return null;

      case PdfNightMode.inverted:
        // Hardware RGB inversion matrix for crisp night reading
        return const ColorFilter.matrix(<double>[
          -0.9,    0,    0, 0, 240,
             0, -0.9,    0, 0, 240,
             0,    0, -0.9, 0, 240,
             0,    0,    0, 1,   0,
        ]);

      case PdfNightMode.smartDark:
        // Eye-care warm amber dark mode matrix
        return const ColorFilter.matrix(<double>[
          -0.80,     0,     0, 0, 220,
              0, -0.80,     0, 0, 212,
              0,     0, -0.70, 0, 195,
              0,     0,     0, 1,   0,
        ]);
    }
  }
}
