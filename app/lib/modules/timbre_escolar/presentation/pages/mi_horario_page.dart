import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
/// Es la pantalla de entrada del rol profesor y, como en el prototipo, es un
/// **resumen**: próximo timbre con su cuenta regresiva, clase actual, próxima
/// clase y los chips del día. El semanal completo vive detrás del botón
/// "Ver horario completo" ([HorarioCompletoPage] en su propia ruta).
/// "En curso" y "Próxima" se marcan contra la hora del servidor, no la del
/// teléfono (RF-41, RF-42).
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
            if (hoy case AsyncData(:final value)) ...[
              TarjetaProximoTimbre(
                hoy: value,
                alAgotarse: () {
                  // Sonó el timbre: el próximo toque y la clase en curso ya
                  // son otros.
                  ref.invalidate(timbresHoyProvider);
                  ref.invalidate(miHorarioProvider);
                },
              ),
              const SizedBox(height: 16),
            ],
            switch (horario) {
              AsyncData(:final value) => _ResumenDeHoy(
                horario: value,
                timbresHoy: hoy.value,
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
          ],
        ),
      ),
    );
  }
}

/// La tarjeta amarilla "PRÓXIMO TIMBRE" (frame 1:527), con el "TIEMPO
/// RESTANTE" corriendo segundo a segundo.
///
/// La cuenta parte de la hora del servidor y avanza con el reloj local desde
/// el momento en que llegó la respuesta: el teléfono solo aporta el paso del
/// tiempo, no su hora (RF-41).
class TarjetaProximoTimbre extends StatefulWidget {
  final TimbresHoy hoy;

  /// Se llama una sola vez cuando la cuenta llega a cero.
  final VoidCallback? alAgotarse;

  const TarjetaProximoTimbre({super.key, required this.hoy, this.alAgotarse});

  @override
  State<TarjetaProximoTimbre> createState() => _TarjetaProximoTimbreState();
}

class _TarjetaProximoTimbreState extends State<TarjetaProximoTimbre> {
  Timer? _tic;
  late DateTime _referencia;
  int _tics = 0;
  bool _avisado = false;

  @override
  void initState() {
    super.initState();
    _referencia = DateTime.now();
    _tic = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _tics++),
    );
  }

  @override
  void didUpdateWidget(TarjetaProximoTimbre anterior) {
    super.didUpdateWidget(anterior);
    // Llegaron datos frescos del servidor: la cuenta arranca de nuevo.
    if (!identical(anterior.hoy, widget.hoy)) {
      _referencia = DateTime.now();
      _tics = 0;
      _avisado = false;
    }
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  static int _minutos(String hora) {
    final partes = hora.split(':');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }

  /// Segundos entre la hora del servidor (avanzada con el reloj local) y el
  /// próximo toque, o `null` si hoy ya no suena nada.
  ///
  /// El paso del tiempo se mide dos veces —los tics del temporizador y el
  /// reloj de pared— y manda el mayor: si el sistema suspende la app, el
  /// temporizador se congela pero el reloj no, y al volver la cuenta aparece
  /// donde debe en vez de donde se quedó.
  int? get _segundosRestantes {
    final proximo = widget.hoy.proximo;
    if (proximo == null) return null;

    final alLlegar =
        (_minutos(proximo.hora) - _minutos(widget.hoy.horaServidor)) * 60;
    final pared = DateTime.now().difference(_referencia).inSeconds;
    return alLlegar - (_tics > pared ? _tics : pared);
  }

  static String _cuenta(int segundos) {
    final s = segundos < 0 ? 0 : segundos;
    String dos(int n) => n.toString().padLeft(2, '0');
    final horas = s ~/ 3600;
    final resto = '${dos((s % 3600) ~/ 60)}:${dos(s % 60)}';
    return horas > 0 ? '$horas:$resto' : resto;
  }

  @override
  Widget build(BuildContext context) {
    final proximo = widget.hoy.proximo;
    final restante = _segundosRestantes;

    if (restante != null && restante <= 0 && !_avisado) {
      _avisado = true;
      // Fuera del build: invalidar providers mientras se construye lanza.
      final avisar = widget.alAgotarse;
      if (avisar != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => avisar());
      }
    }

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
                if (proximo == null)
                  Text(
                    'No hay más timbres por hoy',
                    style: GoogleFonts.workSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: AppColors.dorado.withValues(alpha: 0.8),
                    ),
                  )
                else ...[
                  Text(
                    'TIEMPO RESTANTE',
                    style: TimbreTextos.rotulo.copyWith(
                      fontSize: 10,
                      color: AppColors.dorado.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    _cuenta(restante ?? 0),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: AppColors.dorado,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.timer_outlined, size: 40, color: AppColors.dorado),
        ],
      ),
    );
  }
}

/// Clase actual, próxima clase, el botón al semanal y los chips del día.
class _ResumenDeHoy extends StatelessWidget {
  final MiHorario horario;
  final TimbresHoy? timbresHoy;

  const _ResumenDeHoy({required this.horario, required this.timbresHoy});

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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${proxima.materia} · ${proxima.salon} · ${proxima.horaInicio}',
                          style: GoogleFonts.workSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: TimbreColors.tinta,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.chipTexto,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        // "Ver horario completo" (frame 1:527): el semanal vive en su propia
        // pantalla, como en el prototipo.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push(RutasTimbre.miHorarioCompleto),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Ver horario completo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dorado,
              side: const BorderSide(color: AppColors.dorado),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.workSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Los chips resumen del prototipo, con datos reales del día.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipResumen(
              icono: Icons.event_note_outlined,
              texto:
                  '${hoy?.bloques.length ?? 0} Clases hoy',
            ),
            if (timbresHoy != null)
              _ChipResumen(
                icono: Icons.notifications_none_outlined,
                texto: '${timbresHoy!.timbres.length} Timbres hoy',
              ),
          ],
        ),
      ],
    );
  }
}

class _ChipResumen extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _ChipResumen({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: TimbreColors.grisChip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: TimbreColors.tinta),
          const SizedBox(width: 8),
          Text(
            texto,
            style: GoogleFonts.workSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TimbreColors.tinta,
            ),
          ),
        ],
      ),
    );
  }
}
