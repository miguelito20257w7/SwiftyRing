import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/grafica_sismograma.dart';
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
  final VoidCallback? onTap;

  const _FilaHistorial({
    required this.icono,
    required this.color,
    required this.fondo,
    required this.titulo,
    required this.detalle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: fondo,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, size: 22, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TimbreTextos.etiquetaTarjeta.copyWith(
                          fontSize: 16,
                        ),
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
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.chipTexto,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DetalleEventoPage.activacion(activacion: activacion),
                ),
              ),
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
    final configAsync = ref.watch(configuracionProvider);
    final umbralG = configAsync.value?.umbralSismicoG ?? 0.15;

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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetalleEventoPage.sismo(
                    sismo: sismo,
                    umbralG: umbralG,
                  ),
                ),
              ),
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetalleEventoPage.notificacion(
                    notificacion: notificacion,
                  ),
                ),
              ),
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

/// Pantalla de detalle exhaustiva para cualquier evento del historial.
class DetalleEventoPage extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color colorIcono;
  final Color fondoIcono;
  final List<({IconData icono, String etiqueta, String valor})> datos;
  final Widget? contenidoExtra;

  const DetalleEventoPage({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colorIcono,
    required this.fondoIcono,
    required this.datos,
    this.contenidoExtra,
  });

  factory DetalleEventoPage.activacion({required Activacion activacion}) {
    final icono = switch (activacion.tipo) {
      TipoActivacion.automatico => Icons.schedule,
      TipoActivacion.manualApp => Icons.smartphone,
      TipoActivacion.manualFisico => Icons.touch_app_outlined,
      TipoActivacion.sismico => Icons.warning_amber_rounded,
    };
    final color = switch (activacion.tipo) {
      TipoActivacion.automatico => const Color(0xFF2980B9),
      TipoActivacion.sismico => const Color(0xFFC0392B),
      _ => AppColors.dorado,
    };
    final fondo = switch (activacion.tipo) {
      TipoActivacion.automatico => const Color(0xFFCFE5F7),
      TipoActivacion.sismico => const Color(0xFFFFD3D6),
      _ => TimbreColors.amarillo.withValues(alpha: 0.45),
    };

    final origen = switch (activacion.tipo) {
      TipoActivacion.automatico => 'Horario escolar programado',
      TipoActivacion.manualApp =>
        activacion.usuarioNombre != null
            ? 'Usuario: ${activacion.usuarioNombre}'
            : 'Activación manual desde App',
      TipoActivacion.manualFisico => 'Pulsador físico en módulo ESP32',
      TipoActivacion.sismico => 'Alarma automática por sensor MPU-6050',
    };

    return DetalleEventoPage(
      titulo: activacion.tipo.etiqueta,
      subtitulo: 'Registro de activación del timbre',
      icono: icono,
      colorIcono: color,
      fondoIcono: fondo,
      datos: [
        (
          icono: Icons.calendar_today_outlined,
          etiqueta: 'Fecha y hora',
          valor: _fecha(activacion.ocurridoAt),
        ),
        (
          icono: Icons.timer_outlined,
          etiqueta: 'Duración del toque',
          valor: activacion.duracionSeg != null
              ? '${activacion.duracionSeg} segundos'
              : 'Predeterminada (5 s)',
        ),
        (
          icono: Icons.person_outline,
          etiqueta: 'Origen / Responsable',
          valor: origen,
        ),
        (
          icono: Icons.fingerprint,
          etiqueta: 'ID de registro',
          valor: activacion.id,
        ),
      ],
    );
  }

  factory DetalleEventoPage.sismo({
    required Sismo sismo,
    double umbralG = 0.15,
  }) {
    return DetalleEventoPage(
      titulo: '${sismo.intensidadG.toStringAsFixed(2)} g',
      subtitulo: 'Evento sísmico detectado',
      icono: Icons.warning_amber_rounded,
      colorIcono: const Color(0xFFC0392B),
      fondoIcono: const Color(0xFFFFD3D6),
      contenidoExtra: GraficaSismograma(
        sismo: sismo,
        umbralG: umbralG,
      ),
      datos: [
        (
          icono: Icons.speed,
          etiqueta: 'Aceleración pico (PGA)',
          valor: '${sismo.intensidadG.toStringAsFixed(3)} g',
        ),
        (
          icono: Icons.timer_outlined,
          etiqueta: 'Duración de la sacudida',
          valor: '${sismo.duracionMs} ms (${(sismo.duracionMs / 1000).toStringAsFixed(2)} s)',
        ),
        (
          icono: Icons.notifications_active_outlined,
          etiqueta: 'Alarma de evacuación',
          valor: sismo.timbreActivado
              ? 'Sonó automáticamente (30 s)'
              : 'No activó el timbre (bajo umbral)',
        ),
        (
          icono: Icons.calendar_today_outlined,
          etiqueta: 'Fecha y hora',
          valor: _fecha(sismo.ocurridoAt),
        ),
        (
          icono: Icons.fingerprint,
          etiqueta: 'ID del evento',
          valor: sismo.id,
        ),
      ],
    );
  }

  factory DetalleEventoPage.notificacion({
    required Notificacion notificacion,
  }) {
    return DetalleEventoPage(
      titulo: notificacion.profesorNombre,
      subtitulo: 'Notificación de próxima clase',
      icono: Icons.notifications_none,
      colorIcono: const Color(0xFF00796B),
      fondoIcono: const Color(0xFFCDEFE8),
      datos: [
        (
          icono: Icons.person_outline,
          etiqueta: 'Docente',
          valor: notificacion.profesorNombre,
        ),
        (
          icono: Icons.message_outlined,
          etiqueta: 'Mensaje transmitido',
          valor: notificacion.mensaje,
        ),
        (
          icono: Icons.send_outlined,
          etiqueta: 'Estado de entrega',
          valor: notificacion.enviada
              ? 'Entregada por FCM'
              : 'Registrada en bitácora',
        ),
        (
          icono: Icons.calendar_today_outlined,
          etiqueta: 'Fecha y hora',
          valor: _fecha(notificacion.ocurridoAt),
        ),
        (
          icono: Icons.fingerprint,
          etiqueta: 'ID de notificación',
          valor: notificacion.id,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        title: const Text('Detalle del evento'),
        backgroundColor: AppColors.fondo,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.blanco,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.chipFondo),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: fondoIcono,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icono, size: 32, color: colorIcono),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      titulo,
                      style: GoogleFonts.workSans(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: TimbreColors.tinta,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: GoogleFonts.workSans(
                        fontSize: 14,
                        color: AppColors.textoApoyo,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (contenidoExtra != null) ...[
                const SizedBox(height: 20),
                contenidoExtra!,
              ],
              const SizedBox(height: 20),
              Text(
                'INFORMACIÓN REGISTRADA',
                style: TimbreTextos.rotulo,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.blanco,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.chipFondo),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < datos.length; i++) ...[
                      if (i > 0) const Divider(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            datos[i].icono,
                            size: 20,
                            color: AppColors.textoApoyo,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  datos[i].etiqueta,
                                  style: GoogleFonts.workSans(
                                    fontSize: 12,
                                    color: AppColors.textoApoyo,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  datos[i].valor,
                                  style: GoogleFonts.workSans(
                                    fontSize: 15,
                                    color: TimbreColors.tinta,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al historial'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: TimbreColors.tinta,
                  side: const BorderSide(color: AppColors.chipFondo),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

