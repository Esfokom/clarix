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
        // Full hardware RGB inversion matrix
        return const ColorFilter.matrix(<double>[
          -1,  0,  0, 0, 255,
           0, -1,  0, 0, 255,
           0,  0, -1, 0, 255,
           0,  0,  0, 1,   0,
        ]);

      case PdfNightMode.smartDark:
        // Warm dark slate reading matrix (reduces harsh blue light)
        return const ColorFilter.matrix(<double>[
          -0.85,     0,     0, 0, 230,
              0, -0.85,     0, 0, 225,
              0,     0, -0.75, 0, 210,
              0,     0,     0, 1,   0,
        ]);
    }
  }
}
