import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Clases de ancho de ventana, siguiendo los *window size classes* de
/// Material 3. Se usan para decidir **estructura** (una columna o dos, cuántas
/// tarjetas por fila), no para escalar tipografía.
enum ClaseAncho {
  /// Teléfono en vertical.
  compacta,

  /// Tableta en vertical, teléfono grande en horizontal, ventana estrecha.
  media,

  /// Tableta en horizontal, escritorio.
  expandida,
}

/// Ayudas de diseño adaptativo.
///
/// El prototipo de Figma se dibujó sobre un lienzo de 375 × 884: un teléfono
/// en vertical. Sus medidas siguen siendo la referencia, pero aquí dejan de
/// ser absolutas y pasan a depender del espacio real disponible.
///
/// La distinción que más importa no es el ancho sino [altoCompacto]: un
/// teléfono en horizontal tiene mucho ancho y muy poca altura, y ahí una
/// columna con logo grande y espaciados generosos no cabe de ninguna manera.
extension Responsive on BuildContext {
  Size get _tamano => MediaQuery.sizeOf(this);

  ClaseAncho get claseAncho {
    final ancho = _tamano.width;
    if (ancho < 600) return ClaseAncho.compacta;
    if (ancho < 840) return ClaseAncho.media;
    return ClaseAncho.expandida;
  }

  bool get esCompacta => claseAncho == ClaseAncho.compacta;
  bool get esExpandida => claseAncho == ClaseAncho.expandida;

  /// Hay poca altura: teléfono en horizontal o ventana aplastada. Es la
  /// condición que obliga a cambiar de estructura, no el ancho.
  bool get altoCompacto => _tamano.height < 600;

  /// Ancho máximo del bloque de contenido. Evita líneas de texto de medio
  /// metro en una pantalla de escritorio.
  double get anchoContenido => switch (claseAncho) {
    ClaseAncho.compacta => 448,
    ClaseAncho.media => 520,
    ClaseAncho.expandida => 560,
  };

  /// Margen lateral de la página.
  double get margenLateral => switch (claseAncho) {
    ClaseAncho.compacta => 24,
    ClaseAncho.media => 32,
    ClaseAncho.expandida => 48,
  };

  /// Margen superior e inferior. Se reduce mucho cuando falta altura.
  double get margenVertical => altoCompacto ? 16 : 48;

  /// Lado del cuadro del logo. En horizontal se encoge para dejar sitio al
  /// texto; en pantallas grandes crece un poco para no verse perdido.
  double get ladoLogo {
    if (altoCompacto) return 88;
    return esExpandida ? 152 : 128;
  }

  /// Escala un espaciado vertical del prototipo según la altura disponible.
  /// Nunca lo agranda: el diseño original es el techo.
  double espacioVertical(double base) =>
      altoCompacto ? math.max(8, base * 0.4) : base;
}
