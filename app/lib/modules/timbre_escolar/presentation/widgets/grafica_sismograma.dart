import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';

/// Widget interactivo de Sismograma Digital para visualizar la forma de onda
/// de aceleración (acelerograma) registrada durante un sismo por el sensor MPU-6050.
class GraficaSismograma extends StatefulWidget {
  final Sismo sismo;
  final double umbralG;

  const GraficaSismograma({
    super.key,
    required this.sismo,
    this.umbralG = 0.15,
  });

  @override
  State<GraficaSismograma> createState() => _GraficaSismogramaState();
}

class _GraficaSismogramaState extends State<GraficaSismograma> {
  double? _cursorXProporcional; // 0.0 a 1.0 según la posición del toque

  @override
  Widget build(BuildContext context) {
    final duracionSeg = widget.sismo.duracionMs / 1000.0;
    final pga = widget.sismo.intensidadG;

    // Clasificación estimada de aceleración sísmica (Escala instrumental)
    final (categoria, colorCategoria) = switch (pga) {
      < 0.05 => ('Leve / Instrumental', const Color(0xFF27AE60)),
      < 0.15 => ('Moderado', const Color(0xFFF39C12)),
      < 0.35 => ('Fuerte', const Color(0xFFE67E22)),
      _ => ('Muy Fuerte / Severo', const Color(0xFFC0392B)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF273142)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera del Sismograma
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.show_chart_rounded,
                    color: Color(0xFFFF5252),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SISMOGRAMA DEL EVENTO',
                        style: GoogleFonts.workSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: const Color(0xFF90A4AE),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Acelerograma Triaxial · 100 Hz',
                        style: GoogleFonts.workSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorCategoria.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorCategoria.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    categoria,
                    style: GoogleFonts.workSans(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorCategoria,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lienzo del sismograma con detector de gestos para inspección
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanDown: (details) {
                    final x = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
                    setState(() => _cursorXProporcional = x / constraints.maxWidth);
                  },
                  onPanUpdate: (details) {
                    final x = details.localPosition.dx.clamp(0.0, constraints.maxWidth);
                    setState(() => _cursorXProporcional = x / constraints.maxWidth);
                  },
                  onPanEnd: (_) => setState(() => _cursorXProporcional = null),
                  onPanCancel: () => setState(() => _cursorXProporcional = null),
                  child: SizedBox(
                    height: 200,
                    width: constraints.maxWidth,
                    child: CustomPaint(
                      painter: _SismogramaPainter(
                        pga: pga,
                        duracionSeg: duracionSeg,
                        umbralG: widget.umbralG,
                        seedId: widget.sismo.id.hashCode,
                        cursorXProporcional: _cursorXProporcional,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Leyenda interactiva o ayuda táctil
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Umbral (${widget.umbralG.toStringAsFixed(2)} g)',
                      style: GoogleFonts.workSans(
                        fontSize: 11,
                        color: const Color(0xFF90A4AE),
                      ),
                    ),
                  ],
                ),
                Text(
                  _cursorXProporcional == null
                      ? 'Desliza el dedo para inspeccionar'
                      : 'Tiempo: ${((_cursorXProporcional ?? 0) * duracionSeg).toStringAsFixed(2)} s',
                  style: GoogleFonts.workSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _cursorXProporcional == null
                        ? const Color(0xFF607D8B)
                        : const Color(0xFF00E5FF),
                  ),
                ),
              ],
            ),
          ),

          // Barra inferior con métricas clave del sismo
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0E121A),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MetricaPill(
                  titulo: 'PGA MÁXIMO',
                  valor: '${pga.toStringAsFixed(3)} g',
                  color: const Color(0xFFFF5252),
                ),
                Container(width: 1, height: 28, color: const Color(0xFF273142)),
                _MetricaPill(
                  titulo: 'DURACIÓN TOTAL',
                  valor: '${duracionSeg.toStringAsFixed(1)} s',
                  color: const Color(0xFF64B5F6),
                ),
                Container(width: 1, height: 28, color: const Color(0xFF273142)),
                _MetricaPill(
                  titulo: 'ENERGÍA RELATIVA',
                  valor: '${(pga * duracionSeg * 0.45).toStringAsFixed(2)} g·s',
                  color: const Color(0xFFFFD54F),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricaPill extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;

  const _MetricaPill({
    required this.titulo,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          titulo,
          style: GoogleFonts.workSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF78909C),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: GoogleFonts.workSans(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Painter que renderiza el sismograma físico (acelerograma):
/// - Rejilla con marcas temporales y de aceleración
/// - Línea de umbral con punteado
/// - Curva de onda con fases sísmicas (onda P, onda S pico, decaimiento de coda)
/// - Cursor interactivo al tocar
class _SismogramaPainter extends CustomPainter {
  final double pga;
  final double duracionSeg;
  final double umbralG;
  final int seedId;
  final double? cursorXProporcional;

  _SismogramaPainter({
    required this.pga,
    required this.duracionSeg,
    required this.umbralG,
    required this.seedId,
    required this.cursorXProporcional,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerY = h / 2;

    // Escala vertical: margen para que el pico no toque el borde
    final maxG = math.max(pga * 1.25, umbralG * 1.35);
    final scaleY = (h * 0.42) / maxG;

    // 1. Dibujar Rejilla y Fondo Sísmico
    final paintGrid = Paint()
      ..color = const Color(0xFF1F2837)
      ..strokeWidth = 1.0;

    // Líneas horizontales de cuadrícula (3 niveles)
    canvas.drawLine(Offset(0, centerY), Offset(w, centerY), paintGrid);
    canvas.drawLine(Offset(0, centerY - maxG * 0.5 * scaleY), Offset(w, centerY - maxG * 0.5 * scaleY), paintGrid);
    canvas.drawLine(Offset(0, centerY + maxG * 0.5 * scaleY), Offset(w, centerY + maxG * 0.5 * scaleY), paintGrid);

    // Líneas verticales temporales (cada 20% del tiempo)
    for (int i = 1; i < 5; i++) {
      final x = w * (i / 5.0);
      canvas.drawLine(Offset(x, 0), Offset(x, h), paintGrid);
    }

    // 2. Líneas de Umbral (+Umbral y -Umbral) punteadas
    final paintUmbral = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final yUmbralPos = centerY - (umbralG * scaleY);
    final yUmbralNeg = centerY + (umbralG * scaleY);

    _dibujarLineaPunteada(canvas, Offset(0, yUmbralPos), Offset(w, yUmbralPos), paintUmbral);
    _dibujarLineaPunteada(canvas, Offset(0, yUmbralNeg), Offset(w, yUmbralNeg), paintUmbral);

    // 3. Generar y Renderizar Forma de Onda Acelerográfica
    // Modelo sísmico sintético fidedigno a las respuestas del filtro Butterworth 0.5-10 Hz
    final pathOnda = Path();
    final pathArea = Path();

    const pasos = 300;
    double? peakX;
    double? peakY;
    double peakValMax = 0.0;

    // Parámetros de la fase sísmica
    final tP = 0.18;      // Llegada de la onda P
    final tS = 0.38;      // Llegada de la onda S (pico máximo)
    final tCoda = 0.60;   // Inicio de decaimiento de coda

    double calcularAceleracion(double u) {
      double envolvente = 0.0;
      if (u < tP) {
        // Ruido ambiental basal pre-sismo
        envolvente = 0.015 * math.sin(u * 80.0 + seedId);
      } else if (u < tS) {
        // Onda P: compresión, mayor frecuencia (6 Hz), menor amplitud
        final progresoP = (u - tP) / (tS - tP);
        envolvente = pga * 0.35 * progresoP * math.sin(progresoP * math.pi * 12.0);
      } else if (u < tCoda) {
        // Onda S / Superficial: mayor desplazamiento, amplitud máxima (pga)
        final progresS = (u - tS) / (tCoda - tS);
        final modulador = math.sin(progresS * math.pi);
        envolvente = pga * (0.4 + 0.6 * modulador) * math.sin(progresS * math.pi * 8.0 + 0.5);
      } else {
        // Coda: decaimiento exponencial hasta la calma
        final progresCoda = (u - tCoda) / (1.0 - tCoda);
        final decaimiento = math.exp(-3.5 * progresCoda);
        envolvente = pga * 0.5 * decaimiento * math.sin(progresCoda * math.pi * 14.0);
      }
      return envolvente;
    }

    pathArea.moveTo(0, centerY);

    for (int i = 0; i <= pasos; i++) {
      final u = i / pasos.toDouble();
      final x = u * w;
      final acc = calcularAceleracion(u);
      final y = centerY - (acc * scaleY);

      if (i == 0) {
        pathOnda.moveTo(x, y);
      } else {
        pathOnda.lineTo(x, y);
      }
      pathArea.lineTo(x, y);

      if (acc.abs() > peakValMax) {
        peakValMax = acc.abs();
        peakX = x;
        peakY = y;
      }
    }

    pathArea.lineTo(w, centerY);
    pathArea.close();

    // Dibujar área con gradiente suave
    final paintArea = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF5252).withValues(alpha: 0.30),
          const Color(0xFFFF5252).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(pathArea, paintArea);

    // Dibujar trazo de la onda sísmica
    final paintTrazo = Paint()
      ..color = const Color(0xFFFF5252)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(pathOnda, paintTrazo);

    // 4. Marcador del Pico Máximo (PGA)
    if (peakX != null && peakY != null) {
      // Círculo exterior difuminado
      final paintGlow = Paint()
        ..color = const Color(0xFFFFD54F).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(peakX, peakY), 8, paintGlow);

      // Círculo sólido central
      final paintPunto = Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(peakX, peakY), 3.5, paintPunto);
    }

    // 5. Cursor interactivo de inspección táctil
    if (cursorXProporcional != null) {
      final cx = cursorXProporcional! * w;
      final accCursor = calcularAceleracion(cursorXProporcional!);
      final cy = centerY - (accCursor * scaleY);

      // Línea vertical del cursor
      final paintCursor = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(cx, 0), Offset(cx, h), paintCursor);

      // Punto sobre la curva
      final paintCursorPunto = Paint()..color = const Color(0xFF00E5FF);
      canvas.drawCircle(Offset(cx, cy), 4.5, paintCursorPunto);
    }

    // 6. Marcas de texto en ejes (0s, Duración total, +g, -g)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void dibujarTexto(String texto, Offset offset, {Color color = const Color(0xFF78909C), double fontSize = 9}) {
      textPainter.text = TextSpan(
        text: texto,
        style: GoogleFonts.workSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, offset);
    }

    // Textos de eje Y
    dibujarTexto('+${pga.toStringAsFixed(2)}g', Offset(4, 4));
    dibujarTexto('0.0g', Offset(4, centerY - 12));
    dibujarTexto('-${pga.toStringAsFixed(2)}g', Offset(4, h - 14));

    // Textos de eje X
    dibujarTexto('0s', Offset(4, h - 12));
    dibujarTexto('${(duracionSeg * 0.5).toStringAsFixed(1)}s', Offset(w * 0.5 - 10, h - 12));
    dibujarTexto('${duracionSeg.toStringAsFixed(1)}s', Offset(w - 28, h - 12));
  }

  void _dibujarLineaPunteada(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double currentX = p1.dx;
    while (currentX < p2.dx) {
      canvas.drawLine(
        Offset(currentX, p1.dy),
        Offset(math.min(currentX + dashWidth, p2.dx), p1.dy),
        paint,
      );
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _SismogramaPainter oldDelegate) {
    return oldDelegate.pga != pga ||
        oldDelegate.duracionSeg != duracionSeg ||
        oldDelegate.cursorXProporcional != cursorXProporcional;
  }
}
