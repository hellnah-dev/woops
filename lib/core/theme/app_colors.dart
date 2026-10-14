import 'package:flutter/material.dart';

/// "Lovey-dovey" palette: blush pinks, warm coral and a touch of lavender.
/// Change these to re-skin the whole app.
class AppColors {
  const AppColors._();

  static const rose = Color(0xFFFF4F81); // primary: sweetheart pink
  static const berry = Color(0xFFD81B60); // deeper pink for contrast/text
  static const apricot = Color(0xFFFF8A7A); // warm coral
  static const blush = Color(0xFFFFD1DF); // soft pink surfaces
  static const lavender = Color(0xFFB39DFF); // dreamy accent
  static const violet = lavender;
  static const cream = Color(0xFFFFF6F9); // light background
  static const plum = Color(0xFF1C1119); // dark background

  static const like = Color(0xFFFF3D7F);
  static const pass = Color(0xFF8E8A99);
  static const undo = Color(0xFFFFB547);

  static const ink = Color(0xFF2B1A24);
  static const night = plum;

  static const brandGradient = LinearGradient(
    colors: [Color(0xFFFF7EB3), rose, apricot],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Soft, dreamy background wash used on welcome/empty screens.
  static const dreamyGradient = LinearGradient(
    colors: [Color(0xFFFFE3EE), Color(0xFFFFF6F9), Color(0xFFF3ECFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const dreamyGradientDark = LinearGradient(
    colors: [Color(0xFF2A1422), plum, Color(0xFF1F1530)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Darkens the bottom of profile photos so white text stays readable.
  static const photoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0x00000000), Color(0xCC2B0A1A)],
    stops: [0, 0.45, 1],
  );
}

class AppSpacing {
  const AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  const AppRadius._();
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 28.0;
  static const pill = 999.0;
}

class AppFonts {
  const AppFonts._();
  static const body = 'Nunito';

  /// Handwritten script for the wordmark and big romantic moments.
  static const script = 'Pacifico';
}
