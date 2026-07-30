import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-09 — Vista del profesor (RF-40..RF-43).
/// Frame de Figma `1:527` "Vista Profesor (Yellow)".
///
/// Es la pantalla de entrada del rol profesor: próximo timbre, clase actual,
/// próxima clase y el horario semanal completo. "En curso" y "Próxima" se
/// marcan contra la hora del servidor, no la del teléfono (RF-41, RF-42).
class MiHorarioPage extends ConsumerWidget {
  const MiHorarioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    final horario = ref.watch(miHorarioProvider);
    final hoy = ref.watch(timbresHoyProvider);

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.miHorario,
      child: RefreshIndicator(
        onRefresh: () {
          // RF-43: el gesto de refrescar trae los cambios del administrador.
          ref.invalidate(timbresHoyProvider);
          return ref.refresh(miHorarioProvider.future);
        },
        child: CuerpoTimbre(
          children: [
            Text(
              sesion?.nombre ?? 'Profesor',
              style: TimbreTextos.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: TimbreColors.amarillo.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Profesor', style: TimbreTextos.rotulo),
            ),
            const SizedBox(height: 24),
            if (hoy case AsyncData(:final value))
              _TarjetaProximoTimbre(hoy: value),
            const SizedBox(height: 16),
            switch (horario) {
              AsyncData(:final value) => _ContenidoHorario(horario: value),
              AsyncError(:final error) => AvisoErrorCarga(
                error: error,
                alReintentar: () => ref.invalidate(miHorarioProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// La tarjeta amarilla "PRÓXIMO TIMBRE" (frame 1:527).
class _TarjetaProximoTimbre extends StatelessWidget {
  final TimbresHoy hoy;

  const _TarjetaProximoTimbre({required this.hoy});

  /// Minutos entre la hora del servidor y el próximo toque.
  int? get _minutosRestantes {
    final proximo = hoy.proximo;
    if (proximo == null) return null;
    int minutos(String hora) {
      final partes = hora.split(':');
      return int.parse(partes[0]) * 60 + int.parse(partes[1]);
    }
    return minutos(proximo.hora) - minutos(hoy.horaServidor);
  }

  @override
  Widget build(BuildContext context) {
    final proximo = hoy.proximo;
    final restante = _minutosRestantes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: TimbreColors.amarillo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PRÓXIMO TIMBRE',
                  style: TimbreTextos.rotulo.copyWith(color: AppColors.dorado),
                ),
                Text(
                  proximo?.hora ?? '—',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: AppColors.dorado,
                  ),
                ),
                Text(
                  proximo == null
                      ? 'No hay más timbres por hoy'
                      : restante != null && restante > 0
                      ? 'Faltan $restante min · ${proximo.etiqueta}'
                      : proximo.etiqueta,
                  style: GoogleFonts.workSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.dorado.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.timer_outlined, size: 40, color: AppColors.dorado),
        ],
      ),
    );
  }
}

class _ContenidoHorario extends StatelessWidget {
  final MiHorario horario;

  const _ContenidoHorario({required this.horario});

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
        // Tarjeta "CLASE ACTUAL / PRÓXIMA CLASE" (frame 1:527).
        if (enCurso != null || proxima != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TimbreColors.selectorFondo,
              borderRadius: BorderRadius.circular(16),
              border: const Border(
                left: BorderSide(color: AppColors.dorado, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (enCurso != null) ...[
                  Text('CLASE ACTUAL', style: TimbreTextos.rotulo),
                  const SizedBox(height: 4),
                  Text(
                    enCurso.materia,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: TimbreColors.tinta,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.textoApoyo,
                      ),
                      const SizedBox(width: 4),
                      Text(enCurso.salon, style: AppTextStyles.cuerpo),
                    ],
                  ),
                ],
                if (enCurso != null && proxima != null) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                ],
                if (proxima != null) ...[
                  Text('PRÓXIMA CLASE', style: TimbreTextos.rotulo),
                  const SizedBox(height: 4),
                  Text(
                    '${proxima.materia} · ${proxima.salon} · ${proxima.horaInicio}',
                    style: GoogleFonts.workSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: TimbreColors.tinta,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text(
          'Horario semanal',
          style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 12),
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
