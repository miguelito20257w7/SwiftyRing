import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';

/// La cuadrícula "Distribución Semanal" del frame 1:392: filas por día,
/// columnas por bloque, celda amarilla con la sigla de la materia y el salón,
/// como las "LC · 11B" del prototipo.
///
/// Vive aquí, y no dentro del detalle de docente, porque la misma tabla la ven
/// dos roles sobre el mismo `MiHorario`: el administrador en el detalle de un
/// docente y el profesor en su horario completo (RF-40).
class CuadriculaSemanal extends StatelessWidget {
  final MiHorario horario;

  /// Qué decir cuando no hay clases; cambia según quién mira la tabla.
  final String mensajeVacio;

  const CuadriculaSemanal({
    super.key,
    required this.horario,
    required this.mensajeVacio,
  });

  /// Sigla de la materia: iniciales de sus palabras, máximo dos letras
  /// ("Lengua Castellana" → LC, "Ortografía" → O).
  static String sigla(String materia) => materia
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();

  /// ¿Es la clase que está ocurriendo ahora mismo? (RF-41).
  ///
  /// Se compara contra la hora del servidor, no la del teléfono: un reloj
  /// desajustado señalaría la celda equivocada. Las horas son `"HH:mm"`, así
  /// que comparar los textos alfabéticamente ordena igual que comparar horas.
  bool _enCurso(MiDia dia, MiBloque bloque) =>
      dia.dia == horario.diaActual &&
      bloque.horaInicio.compareTo(horario.horaServidor) <= 0 &&
      horario.horaServidor.compareTo(bloque.horaFin) < 0;

  @override
  Widget build(BuildContext context) {
    if (horario.dias.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(mensajeVacio, style: AppTextStyles.cuerpo),
      );
    }

    // Tantas columnas como bloques tenga el día más cargado; el encabezado de
    // cada columna toma su franja horaria del primer día que la tenga.
    final columnas = horario.dias
        .map((d) => d.bloques.length)
        .reduce((a, b) => a > b ? a : b);
    String franja(int indice) {
      for (final dia in horario.dias) {
        if (indice < dia.bloques.length) {
          final b = dia.bloques[indice];
          return '${b.horaInicio} – ${b.horaFin}';
        }
      }
      return '';
    }

    const anchoDia = 76.0;
    const anchoCelda = 96.0;

    Widget encabezado(String arriba, String abajo) => SizedBox(
      width: anchoCelda,
      child: Column(
        children: [
          Text(
            arriba,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: TimbreColors.tinta,
            ),
          ),
          Text(
            abajo,
            style: GoogleFonts.workSans(
              fontSize: 10,
              color: AppColors.textoApoyo,
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: anchoDia,
                child: Text(
                  'Día /\nBloque',
                  style: GoogleFonts.workSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dorado,
                  ),
                ),
              ),
              for (var i = 0; i < columnas; i++)
                encabezado('${i + 1}', franja(i)),
            ],
          ),
          const SizedBox(height: 8),
          for (final dia in horario.dias) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: anchoDia,
                    child: Text(
                      dia.dia.etiqueta,
                      style: GoogleFonts.workSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dorado,
                      ),
                    ),
                  ),
                  for (var i = 0; i < columnas; i++)
                    SizedBox(
                      width: anchoCelda,
                      child: i < dia.bloques.length
                          ? _CeldaBloque(
                              bloque: dia.bloques[i],
                              enCurso: _enCurso(dia, dia.bloques[i]),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CeldaBloque extends StatelessWidget {
  final MiBloque bloque;

  /// La clase que está ocurriendo ahora. Solo una celda de toda la tabla lo
  /// está, y es la única que lleva el amarillo fuerte.
  final bool enCurso;

  const _CeldaBloque({required this.bloque, required this.enCurso});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // El amarillo fuerte del prototipo se reserva para la clase en curso.
        // Marcaba el día entero, y con seis celdas encendidas a la vez no
        // señalaba nada: el día de hoy ya lo dice el rótulo de la tarjeta.
        color: TimbreColors.amarillo.withValues(alpha: enCurso ? 0.9 : 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: AppColors.dorado,
            width: enCurso ? 5 : 3,
          ),
        ),
      ),
      child: Tooltip(
        message: '${bloque.materia} · ${bloque.salon}\n'
            '${bloque.horaInicio} – ${bloque.horaFin}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CuadriculaSemanal.sigla(bloque.materia),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.dorado,
              ),
            ),
            Text(
              bloque.salon,
              style: GoogleFonts.workSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textoApoyo,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
