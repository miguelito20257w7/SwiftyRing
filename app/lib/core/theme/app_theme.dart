import 'package:flutter/material.dart';

/// Paleta institucional de SwiftyRing (ver Docs/Documento Final.md, sección 2.3.1).
class AppTheme {
  static const Color primary = Color(0xFFF5B301);
  static const Color primaryContainer = Color(0xFFFFE7A3);
  static const Color grafito = Color(0xFF3B3B30);
  static const Color naranja = Color(0xFFDB712F);
  static const Color marfil = Color(0xFFFAF8F2);
  static const Color marfilSombreado = Color(0xFFECE9E0);
  static const Color grisCalido = Color(0xFF6E6B60);
  static const Color error = Color(0xFFC62828);

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: grafito,
      primaryContainer: primaryContainer,
      onPrimaryContainer: grafito,
      secondary: grafito,
      onSecondary: marfil,
      tertiary: naranja,
      onTertiary: marfil,
      surface: marfil,
      onSurface: grafito,
      surfaceContainerHighest: marfilSombreado,
      onSurfaceVariant: grisCalido,
      error: error,
      onError: marfil,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: marfil,
      useMaterial3: true,
    );
  }
}
