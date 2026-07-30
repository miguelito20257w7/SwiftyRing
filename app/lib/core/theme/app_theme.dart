import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens de diseno tomados del prototipo de Figma
/// "Bienvenida y Login (Yellow)" — archivo mGuugvHdapmZgoIf0dL2MG, nodo 1:800.
/// Si el prototipo cambia, este archivo es el unico que hay que tocar.
abstract class AppColors {
  /// Fondo de pantalla.
  static const fondo = Color(0xFFF8F9FA);

  /// Dorado oscuro de marca: logo, titulo, boton principal y enlaces.
  static const dorado = Color(0xFF735C00);

  /// Texto secundario (subtitulos, textos de apoyo).
  static const textoApoyo = Color(0xFF4D4634);

  /// Circulos difuminados de fondo.
  static const brilloSuperior = Color(0xFFEBC23E);
  static const brilloInferior = Color(0xFFFFD54F);

  /// Chip discreto ("Ajustes de red").
  static const chipFondo = Color(0xFFEDEEEF);
  static const chipTexto = Color(0xFF7F7662);

  static const blanco = Color(0xFFFFFFFF);
  static const error = Color(0xFFB3261E);
}

/// Medidas del prototipo. Los nombres siguen las capas de Figma.
abstract class AppSizes {
  static const paddingHorizontal = 24.0;
  static const paddingVertical = 48.0;

  /// Ancho maximo del bloque de acciones (max-w-[448px] en el diseno).
  static const anchoMaximoContenido = 448.0;

  static const logoLado = 128.0;
  static const logoRadio = 35.84;
  static const iconoLado = 80.0;

  static const botonAlto = 64.0;
  static const botonRadio = 16.0;
}

abstract class AppTextStyles {
  /// "BIENVENIDO" — Plus Jakarta Sans Bold 32/40, tracking -0.8.
  static TextStyle get titulo => GoogleFonts.plusJakartaSans(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.8,
    color: AppColors.dorado,
  );

  /// "Timbre Escolar" — Work Sans Regular 18/28.
  static TextStyle get subtitulo => GoogleFonts.workSans(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 28 / 18,
    color: AppColors.textoApoyo,
  );

  /// Texto del boton principal — Plus Jakarta Sans SemiBold 24/32.
  static TextStyle get boton => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    color: AppColors.blanco,
  );

  /// Texto de apoyo — Work Sans Regular 16/24.
  static TextStyle get cuerpo => GoogleFonts.workSans(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.textoApoyo,
  );

  /// Enlace — Work Sans SemiBold 16/24.
  static TextStyle get enlace => GoogleFonts.workSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
    color: AppColors.dorado,
  );

  /// Chip — Work Sans Medium 14/20, tracking 0.14.
  static TextStyle get chip => GoogleFonts.workSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    letterSpacing: 0.14,
    color: AppColors.chipTexto,
  );
}

abstract class AppShadows {
  /// shadow-[0px_20px_25px_-5px_rgba(0,0,0,0.1),0px_8px_10px_-6px_rgba(0,0,0,0.1)]
  static List<BoxShadow> get logo => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      offset: const Offset(0, 20),
      blurRadius: 25,
      spreadRadius: -5,
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      offset: const Offset(0, 8),
      blurRadius: 10,
      spreadRadius: -6,
    ),
  ];

  /// shadow-[0px_10px_15px_-3px_rgba(0,0,0,0.1),0px_4px_6px_-4px_rgba(0,0,0,0.1)]
  static List<BoxShadow> get boton => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      offset: const Offset(0, 10),
      blurRadius: 15,
      spreadRadius: -3,
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      offset: const Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -4,
    ),
  ];
}

/// RNF-02: la interfaz sigue Material Design 3.
abstract class AppTheme {
  static ThemeData get light {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.dorado,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base.copyWith(
        primary: AppColors.dorado,
        onPrimary: AppColors.blanco,
        surface: AppColors.fondo,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.fondo,
      textTheme: GoogleFonts.workSansTextTheme(),
    );
  }
}
