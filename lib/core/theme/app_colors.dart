import 'package:flutter/material.dart';

/// Brand palette. Change these to re-skin the whole app.
class AppColors {
  const AppColors._();

  static const rose = Color(0xFFE8456B);
  static const apricot = Color(0xFFFF8A5B);
  static const violet = Color(0xFF7B5CFA);

  static const like = Color(0xFF1FB57A);
  static const pass = Color(0xFFE5484D);
  static const undo = Color(0xFFF2A93B);

  static const ink = Color(0xFF1B1622);
  static const night = Color(0xFF121016);

  static const brandGradient = LinearGradient(
    colors: [rose, apricot],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Darkens the bottom of profile photos so white text stays readable.
  static const photoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
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
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const pill = 999.0;
}
