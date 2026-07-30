import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:swiftyring/core/theme/app_theme.dart';

/// Los dos círculos difuminados del fondo (capa "Background Decoration" del
/// prototipo, nodo 1:802). Van al 40 % de opacidad y recortados al borde de la
/// pantalla, igual que el `overflow-clip` del diseño.
///
/// En el prototipo las posiciones son absolutas, medidas sobre un lienzo de
/// 375 × 884. Aquí se expresan como **proporciones**: si se dejaran fijas, al
/// rotar el teléfono el segundo círculo se quedaría en mitad de la pantalla y
/// su borde dibujaría una costura visible en vez de un resplandor de esquina.
///
/// El tamaño se calcula sobre el **lado corto** de la pantalla, no sobre el
/// ancho: en horizontal, escalar por ancho produciría dos manchas enormes que
/// taparían el contenido.
class FondoDecorado extends StatelessWidget {
  const FondoDecorado({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final alto = constraints.maxHeight;
            final ladoCorto = math.min(ancho, alto);

            // Proporciones tomadas del prototipo: 384/375 y 256/375.
            final lado1 = (ladoCorto * 1.024).clamp(240.0, 620.0);
            final lado2 = (ladoCorto * 0.683).clamp(160.0, 420.0);

            return Opacity(
              opacity: 0.4,
              child: Stack(
                children: [
                  // nodo 1:803 — resplandor de la esquina superior izquierda.
                  _CirculoDifuminado(
                    left: -lado1 * 0.25,
                    top: -lado1 * 0.25,
                    lado: lado1,
                    color: AppColors.brilloSuperior,
                    desenfoque: lado1 * 0.104,
                  ),
                  // nodo 1:804 — resplandor de la esquina inferior derecha.
                  _CirculoDifuminado(
                    left: ancho - lado2 * 0.87,
                    top: alto - lado2 - alto * 0.21,
                    lado: lado2,
                    color: AppColors.brilloInferior,
                    desenfoque: lado2 * 0.195,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CirculoDifuminado extends StatelessWidget {
  final double left;
  final double top;
  final double lado;
  final Color color;
  final double desenfoque;

  const _CirculoDifuminado({
    required this.left,
    required this.top,
    required this.lado,
    required this.color,
    required this.desenfoque,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: desenfoque,
          sigmaY: desenfoque,
        ),
        child: Container(
          width: lado,
          height: lado,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
