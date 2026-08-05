import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/cuadricula_semanal.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// El horario semanal completo del profesor (RF-40..RF-43).
///
/// En el prototipo (frame 1:527) la vista del profesor es un resumen y este
/// listado vive detrás del botón "Ver horario completo"; por eso es una
/// pantalla aparte y no una sección más de `MiHorarioPage`.
///
/// Tiene dos vistas del mismo horario: la **lista** por día, que es la que
/// sirve en el celular durante la jornada porque marca la clase en curso y la
/// próxima, y la **cuadrícula** "Distribución Semanal" —la misma tabla que el
/// administrador ve en el detalle del docente—, que sirve para ver la semana
/// entera de un vistazo.
class HorarioCompletoPage extends ConsumerStatefulWidget {
  const HorarioCompletoPage({super.key});

  @override
  ConsumerState<HorarioCompletoPage> createState() =>
      _HorarioCompletoPageState();
}

class _HorarioCompletoPageState extends ConsumerState<HorarioCompletoPage> {
  /// Arranca en lista: es la vista del prototipo y la útil en el día a día.
  bool _cuadricula = false;

  @override
  Widget build(BuildContext context) {
    final horario = ref.watch(miHorarioProvider);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text(
          'Horario completo',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: TimbreColors.tinta,
          ),
        ),
      ),
      body: RefreshIndicator(
        // RF-43: refrescar trae los cambios del administrador.
        onRefresh: () => ref.refresh(miHorarioProvider.future),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: context.margenLateral,
            vertical: 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: switch (horario) {
                AsyncData(:final value) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sin horario no hay nada que alternar: el aviso vacío es
                    // el mismo en las dos vistas.
                    if (value.dias.isNotEmpty) ...[
                      Center(
                        child: SelectorPildora(
                          izquierda: 'LISTA',
                          derecha: 'CUADRÍCULA',
                          derechaActiva: _cuadricula,
                          holgura: 20,
                          alCambiar: (valor) =>
                              setState(() => _cuadricula = valor),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_cuadricula)
                      _TarjetaDistribucion(horario: value)
                    else
                      _Semanal(horario: value),
                  ],
                ),
                AsyncError(:final error) => AvisoErrorCarga(
                  error: error,
                  alReintentar: () => ref.invalidate(miHorarioProvider),
                ),
                _ => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Semanal extends StatelessWidget {
  final MiHorario horario;

  const _Semanal({required this.horario});

  @override
  Widget build(BuildContext context) {
    if (horario.dias.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.blanco,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.chipFondo),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.event_busy_outlined,
              size: 40,
              color: AppColors.chipTexto,
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes horario asignado. El administrador lo carga desde '
              'Asignación horaria.',
              textAlign: TextAlign.center,
              style: AppTextStyles.cuerpo,
            ),
          ],
        ),
      );
    }

    final hoy = horario.dias
        .where((d) => d.dia == horario.diaActual)
        .firstOrNull;
    // RF-41 / RF-42: en curso y próxima contra la hora del servidor.
    final enCurso = hoy?.bloques
        .where(
          (b) =>
              b.horaInicio.compareTo(horario.horaServidor) <= 0 &&
              horario.horaServidor.compareTo(b.horaFin) < 0,
        )
        .firstOrNull;
    final proxima = hoy?.bloques
        .where((b) => b.horaInicio.compareTo(horario.horaServidor) > 0)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dia in horario.dias) ...[
          _SeccionDia(
            dia: dia,
            esHoy: dia.dia == horario.diaActual,
            enCurso: dia.dia == horario.diaActual ? enCurso : null,
            proxima: dia.dia == horario.diaActual ? proxima : null,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// La "Distribución Semanal" tal como la ve el administrador en el detalle de
/// un docente, pero con el horario propio del profesor. La tarjeta se repite
/// aquí (y no se comparte con `DocenteDetallePage`) porque allá lleva el chip
/// de jornada y el botón de asignación, que el profesor no tiene.
class _TarjetaDistribucion extends StatelessWidget {
  final MiHorario horario;

  const _TarjetaDistribucion({required this.horario});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Distribución Semanal',
                  style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 18),
                ),
              ),
              if (horario.diaActual != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFE5F7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'HOY ${horario.diaActual!.etiqueta.toUpperCase()}',
                    style: GoogleFonts.workSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: const Color(0xFF2980B9),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          CuadriculaSemanal(
            horario: horario,
            mensajeVacio:
                'Aún no tienes horario asignado. El administrador lo carga '
                'desde Asignación horaria.',
          ),
          const SizedBox(height: 12),
          Text(
            'Desliza la tabla a los lados para ver todos los bloques. La '
            'celda es la sigla de la materia y el salón.',
            style: GoogleFonts.workSans(
              fontSize: 12,
              color: AppColors.textoApoyo,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeccionDia extends StatelessWidget {
  final MiDia dia;
  final bool esHoy;
  final MiBloque? enCurso;
  final MiBloque? proxima;

  const _SeccionDia({
    required this.dia,
    required this.esHoy,
    required this.enCurso,
    required this.proxima,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esHoy ? TimbreColors.amarillo : AppColors.chipFondo,
          width: esHoy ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dia.dia.etiqueta,
                style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 16),
              ),
              if (esHoy) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: TimbreColors.amarillo.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'HOY',
                    style: GoogleFonts.workSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.dorado,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (final bloque in dia.bloques)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilaBloque(
                bloque: bloque,
                // RF-41 / RF-42: los indicadores visuales.
                estado: identical(bloque, enCurso) || bloque == enCurso
                    ? _EstadoBloque.enCurso
                    : identical(bloque, proxima) || bloque == proxima
                    ? _EstadoBloque.proxima
                    : _EstadoBloque.normal,
              ),
            ),
        ],
      ),
    );
  }
}

enum _EstadoBloque { normal, enCurso, proxima }

class _FilaBloque extends StatelessWidget {
  final MiBloque bloque;
  final _EstadoBloque estado;

  const _FilaBloque({required this.bloque, required this.estado});

  @override
  Widget build(BuildContext context) {
    final (fondo, etiqueta, colorEtiqueta) = switch (estado) {
      _EstadoBloque.enCurso => (
        TimbreColors.amarillo.withValues(alpha: 0.35),
        'EN CURSO',
        const Color(0xFF00796B),
      ),
      _EstadoBloque.proxima => (
        TimbreColors.selectorFondo,
        'PRÓXIMA',
        const Color(0xFF2980B9),
      ),
      _EstadoBloque.normal => (Colors.transparent, null, Colors.transparent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '${bloque.horaInicio}–${bloque.horaFin}',
              style: GoogleFonts.workSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.dorado,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${bloque.materia} · ${bloque.salon}',
              style: GoogleFonts.workSans(
                fontSize: 14,
                color: TimbreColors.tinta,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (etiqueta != null)
            Text(
              etiqueta,
              style: GoogleFonts.workSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: colorEtiqueta,
              ),
            ),
        ],
      ),
    );
  }
}
