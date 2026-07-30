import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-08 — Historial de notificaciones y activaciones (RF-17, RF-23).
/// Frame de Figma `1:844` "Historial de Notificaciones (Yellow)".
///
/// Tres listas con el mismo filtro de fechas: la bitácora de activaciones, los
/// eventos sísmicos y las notificaciones de próxima clase registradas.
class HistorialPage extends ConsumerStatefulWidget {
  const HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  int _pestana = 0;

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: ahora.subtract(const Duration(days: 365)),
      lastDate: ahora,
      helpText: 'Filtrar historial por fechas',
    );
    if (rango == null) return;
    String iso(DateTime f) =>
        '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';
    ref
        .read(filtroHistorialProvider.notifier)
        .fijar(desde: iso(rango.start), hasta: iso(rango.end));
  }

  @override
  Widget build(BuildContext context) {
    final filtro = ref.watch(filtroHistorialProvider);
    final hayFiltro = filtro.desde != null;

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.historial,
      child: CuerpoTimbre(
        children: [
          Text('Historial', style: TimbreTextos.titulo),
          Text(
            'Activaciones, sismos y notificaciones',
            style: AppTextStyles.cuerpo,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Timbres')),
                    ButtonSegment(value: 1, label: Text('Sismos')),
                    ButtonSegment(value: 2, label: Text('Avisos')),
                  ],
                  selected: {_pestana},
                  onSelectionChanged: (seleccion) =>
                      setState(() => _pestana = seleccion.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.dorado,
                    selectedForegroundColor: AppColors.blanco,
                    foregroundColor: AppColors.textoApoyo,
                  ),
                ),
              ),
              IconButton(
                onPressed: _elegirRango,
                icon: Icon(
                  hayFiltro ? Icons.filter_alt : Icons.filter_alt_outlined,
                ),
                color: AppColors.dorado,
                tooltip: 'Filtrar por fechas',
              ),
            ],
          ),
          if (hayFiltro)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InputChip(
                label: Text('${filtro.desde} → ${filtro.hasta}'),
                onDeleted: () =>
                    ref.read(filtroHistorialProvider.notifier).limpiar(),
              ),
            ),
          const SizedBox(height: 16),
          switch (_pestana) {
            0 => const _ListaActivaciones(),
            1 => const _ListaSismos(),
            _ => const _ListaNotificaciones(),
          },
        ],
      ),
    );
  }
}

String _fecha(DateTime momento) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(momento.day)}/${dos(momento.month)}/${momento.year} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}

/// Fila de historial con el icono circular de color del prototipo (1:844).
class _FilaHistorial extends StatelessWidget {
  final IconData icono;
  final Color color;
  final Color fondo;
  final String titulo;
  final String detalle;

  const _FilaHistorial({
    required this.icono,
    required this.color,
    required this.fondo,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
            child: Icon(icono, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  detalle,
                  style: GoogleFonts.workSans(
                    fontSize: 13,
                    color: AppColors.textoApoyo,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeLista extends StatelessWidget {
  final String texto;

  const _MensajeLista({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(texto, style: AppTextStyles.cuerpo),
    );
  }
}

class _ListaActivaciones extends ConsumerWidget {
  const _ListaActivaciones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activaciones = ref.watch(activacionesProvider);

    return switch (activaciones) {
      AsyncData(:final value) when value.isEmpty => const _MensajeLista(
        texto: 'No hay activaciones registradas en este rango.',
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final activacion in value)
            _FilaHistorial(
              icono: switch (activacion.tipo) {
                TipoActivacion.automatico => Icons.schedule,
                TipoActivacion.manualApp => Icons.smartphone,
                TipoActivacion.manualFisico => Icons.touch_app_outlined,
                TipoActivacion.sismico => Icons.warning_amber_rounded,
              },
              color: switch (activacion.tipo) {
                TipoActivacion.automatico => const Color(0xFF2980B9),
                TipoActivacion.manualApp => AppColors.dorado,
                TipoActivacion.manualFisico => AppColors.dorado,
                TipoActivacion.sismico => const Color(0xFFC0392B),
              },
              fondo: switch (activacion.tipo) {
                TipoActivacion.automatico => const Color(0xFFCFE5F7),
                TipoActivacion.sismico => const Color(0xFFFFD3D6),
                _ => TimbreColors.amarillo.withValues(alpha: 0.45),
              },
              titulo: activacion.tipo.etiqueta,
              detalle: [
                _fecha(activacion.ocurridoAt),
                if (activacion.usuarioNombre != null) activacion.usuarioNombre!,
              ].join(' · '),
            ),
        ],
      ),
      AsyncError(:final error) => AvisoErrorCarga(
        error: error,
        alReintentar: () => ref.invalidate(activacionesProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _ListaSismos extends ConsumerWidget {
  const _ListaSismos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sismos = ref.watch(sismosProvider);

    return switch (sismos) {
      AsyncData(:final value) when value.isEmpty => const _MensajeLista(
        texto: 'Sin eventos sísmicos registrados. Ojalá siga así.',
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final sismo in value)
            _FilaHistorial(
              icono: Icons.warning_amber_rounded,
              color: const Color(0xFFC0392B),
              fondo: const Color(0xFFFFD3D6),
              titulo:
                  '${sismo.intensidadG.toStringAsFixed(2)} g · ${sismo.duracionMs} ms',
              detalle:
                  '${_fecha(sismo.ocurridoAt)}'
                  '${sismo.timbreActivado ? ' · Activó el timbre' : ''}',
            ),
        ],
      ),
      AsyncError(:final error) => AvisoErrorCarga(
        error: error,
        alReintentar: () => ref.invalidate(sismosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _ListaNotificaciones extends ConsumerWidget {
  const _ListaNotificaciones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificaciones = ref.watch(notificacionesProvider);

    return switch (notificaciones) {
      AsyncData(:final value) when value.isEmpty => const _MensajeLista(
        texto:
            'Sin notificaciones de próxima clase todavía: se generan al sonar '
            'el timbre para los docentes con clase a continuación.',
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final notificacion in value)
            _FilaHistorial(
              icono: Icons.notifications_none,
              color: const Color(0xFF00796B),
              fondo: const Color(0xFFCDEFE8),
              titulo: notificacion.profesorNombre,
              detalle:
                  '${notificacion.mensaje} · ${_fecha(notificacion.ocurridoAt)}',
            ),
        ],
      ),
      AsyncError(:final error) => AvisoErrorCarga(
        error: error,
        alReintentar: () => ref.invalidate(notificacionesProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
