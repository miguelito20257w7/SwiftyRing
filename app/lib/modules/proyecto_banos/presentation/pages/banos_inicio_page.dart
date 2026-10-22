import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_horario.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/presentation/widgets/banos_bottom_nav.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

const _navy = Color(0xFF1E2545);
const _verde = Color(0xFF2D8C3E);
const _ambar = Color(0xFFE0A100);
const _rojo = Color(0xFFD32F2F);
const _gris = Color(0xFF6B7189);

/// Verde = tranquilo, amarillo = se acerca al límite, rojo = pasó el límite.
Color _colorTiempo(int minutos, int limite) {
  if (minutos >= limite) return _rojo;
  if (minutos >= (limite * 0.7).round()) return _ambar;
  return _verde;
}

/// Panel principal del módulo Control Baños SS.
///
/// Muestra solo el grupo que le toca al docente en este momento (según su
/// horario del timbre). Si no tiene clase, es su hora libre y no se muestra
/// nada para gestionar. Administración y el "modo manual" eligen el grupo a
/// mano.
class BanosInicioPage extends ConsumerStatefulWidget {
  const BanosInicioPage({super.key});

  @override
  ConsumerState<BanosInicioPage> createState() => _BanosInicioPageState();
}

class _BanosInicioPageState extends ConsumerState<BanosInicioPage> {
  /// Salidas que ya hicieron sonar la alerta (para que suene una sola vez).
  final _alertados = <String>{};
  String? _turnoAvisado;

  void _revisarAlertas() {
    final config = ref.read(banosConfigProvider);
    final grupo = ref.read(grupoActivoProvider);
    if (grupo.estado != EstadoGrupo.enClase) return;
    final fuera = ref
        .read(banosProvider)
        .where((s) => s.enCurso && s.grado == grupo.grado);
    for (final s in fuera) {
      if (s.duracionMinutos >= config.minutosLimite && _alertados.add(s.id)) {
        if (config.alertaSonora) {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    // RF02: el rol `operador` no tiene acceso a este módulo.
    if (sesion.rol == RolUsuario.operador) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(Rutas.lanzador),
          ),
          title: const Text('Control Baños'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu rol de operador no tiene acceso al control de salidas al '
              'baño. Habla con coordinación si crees que es un error.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // El reloj refresca la pantalla y revisa si alguien superó el límite.
    ref.watch(relojProvider);
    ref.listen<AsyncValue<DateTime>>(relojProvider, (anterior, siguiente) => _revisarAlertas());

    final grupo = ref.watch(grupoActivoProvider);
    final config = ref.watch(banosConfigProvider);
    final todas = ref.watch(banosProvider);
    final fila = ref.watch(esperaProvider);

    final enClase = grupo.estado == EstadoGrupo.enClase && grupo.grado != null;
    final grado = grupo.grado;

    final fuera = enClase
        ? todas.where((s) => s.enCurso && s.grado == grado).toList()
        : const <SalidaBano>[];
    final recientes = enClase
        ? todas.where((s) => !s.enCurso && s.grado == grado).take(5).toList()
        : const <SalidaBano>[];
    final filaDelGrupo = enClase
        ? fila.where((e) => e.estudiante.grado == grado).toList()
        : const <EsperaSalida>[];

    // ¿Le toca ya al primero de la fila? Se le avisa al profesor una sola vez.
    final grupoLleno = enClase && ref.read(banosProvider.notifier).grupoLleno(grado!);
    final turno = (filaDelGrupo.isNotEmpty && !grupoLleno) ? filaDelGrupo.first : null;
    if (turno != null && turno.id != _turnoAvisado) {
      _turnoAvisado = turno.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ya puede salir ${turno.estudiante.nombre}.')),
        );
      });
    } else if (turno == null) {
      _turnoAvisado = null;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Rutas.lanzador),
        ),
        title: const Text('Control Baños SS'),
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(RutasBanos.configuracion),
          ),
        ],
      ),
      bottomNavigationBar: const BanosBottomNav(indiceActual: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Buen día, ${sesion.primerNombre}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
          ),
          const Text(
            'MONITOR DE AULA ACTIVO',
            style: TextStyle(color: _gris, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          _TarjetaGrupo(
            grupo: grupo,
            onCambiar: () async {
              final elegido = await _elegirGrupo(
                context,
                ref.read(gradosProvider),
                grupo.grado,
              );
              if (elegido != null) {
                ref.read(grupoManualProvider.notifier).elegir(elegido);
              }
            },
            onReintentar: () => ref.invalidate(horarioDocenteProvider),
          ),
          const SizedBox(height: 16),
          if (enClase) ...[
            _TarjetaEnCurso(salidas: fuera, limite: config.minutosLimite),
            const SizedBox(height: 16),
            if (filaDelGrupo.isNotEmpty) ...[
              _TarjetaFila(fila: filaDelGrupo, hayCupo: !grupoLleno),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => context.push(RutasBanos.autorizar),
                child: const Text(
                  'Autorizar nueva salida',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _BotonSecundario(
                  texto: 'Ver historial',
                  onTap: () => context.push(RutasBanos.historial),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BotonSecundario(
                  texto: 'Ir a reportes',
                  onTap: () => context.push(RutasBanos.reportes),
                ),
              ),
            ],
          ),
          if (enClase) ...[
            const SizedBox(height: 24),
            const Text(
              'Actividad reciente',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
            ),
            const SizedBox(height: 8),
            if (recientes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Todavía no hay salidas completadas de este grupo.',
                  style: TextStyle(color: _gris),
                ),
              )
            else
              ...recientes.map((s) => _FilaActividad(salida: s)),
          ],
        ],
      ),
    );
  }
}

/// Hoja inferior para escoger el grupo a mano.
Future<String?> _elegirGrupo(BuildContext context, List<String> grados, String? actual) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Elegir grupo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final g in grados)
            ListTile(
              title: Text(g),
              trailing: g == actual ? const Icon(Icons.check, color: _verde) : null,
              onTap: () => Navigator.of(ctx).pop(g),
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tarjeta del grupo / hora libre
// ---------------------------------------------------------------------------

class _TarjetaGrupo extends StatelessWidget {
  final GrupoActivo grupo;
  final VoidCallback onCambiar;
  final VoidCallback onReintentar;

  const _TarjetaGrupo({
    required this.grupo,
    required this.onCambiar,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icono;
    late final String titulo;
    String? detalle;
    Widget? accion;

    switch (grupo.estado) {
      case EstadoGrupo.cargando:
        icono = Icons.hourglass_empty;
        titulo = 'Cargando tu horario…';
      case EstadoGrupo.error:
        icono = Icons.cloud_off_outlined;
        titulo = 'Sin conexión con el horario';
        detalle = grupo.mensaje;
        accion = TextButton(onPressed: onReintentar, child: const Text('Reintentar'));
      case EstadoGrupo.sinHorario:
        icono = Icons.event_busy_outlined;
        titulo = 'Sin horario asignado';
        detalle = grupo.mensaje;
      case EstadoGrupo.horaLibre:
        icono = Icons.free_breakfast_outlined;
        titulo = 'Hora libre';
        detalle = grupo.mensaje;
      case EstadoGrupo.enClase:
        icono = Icons.groups_outlined;
        titulo = 'Grupo ${grupo.grado}';
        detalle = grupo.manual
            ? 'Elegido manualmente'
            : [grupo.materia, grupo.horario].where((t) => t != null && t.isNotEmpty).join(' · ');
        if (grupo.manual) {
          accion = TextButton(onPressed: onCambiar, child: const Text('Cambiar'));
        }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: _navy, child: Icon(icono, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
                if (detalle != null && detalle.isNotEmpty)
                  Text(detalle, style: const TextStyle(color: _gris, fontSize: 12)),
              ],
            ),
          ),
          if (accion != null) accion,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estudiantes fuera del aula (con colores por tiempo)
// ---------------------------------------------------------------------------

class _TarjetaEnCurso extends StatelessWidget {
  final List<SalidaBano> salidas;
  final int limite;

  const _TarjetaEnCurso({required this.salidas, required this.limite});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estudiantes fuera del aula',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${salidas.length} ahora', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (salidas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nadie está fuera del aula ahora.', style: TextStyle(color: _gris)),
            )
          else
            ...salidas.map((s) => _FilaEnCurso(salida: s, limite: limite)),
        ],
      ),
    );
  }
}

class _FilaEnCurso extends ConsumerWidget {
  final SalidaBano salida;
  final int limite;

  const _FilaEnCurso({required this.salida, required this.limite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutos = salida.duracionMinutos;
    final color = _colorTiempo(minutos, limite);
    final pasoElLimite = minutos >= limite;
    final iniciales = salida.estudianteNombre
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join()
        .toUpperCase();

    final fila = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _navy,
            child: Text(iniciales, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(salida.estudianteNombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  minutos <= 0
                      ? 'Ahora mismo · ${salida.motivo.etiqueta}'
                      : 'Hace $minutos min · ${salida.motivo.etiqueta}',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                if (pasoElLimite)
                  Text('Superó el límite de $limite min',
                      style: const TextStyle(color: _rojo, fontSize: 11)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
            onPressed: () => ref.read(banosProvider.notifier).registrarRegreso(salida.id),
            child: const Text('Registrar\nRegreso', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );

    return _Parpadeo(activo: pasoElLimite, child: fila);
  }
}

/// Hace parpadear a su hijo mientras `activo` sea true.
class _Parpadeo extends StatefulWidget {
  final bool activo;
  final Widget child;
  const _Parpadeo({required this.activo, required this.child});

  @override
  State<_Parpadeo> createState() => _ParpadeoState();
}

class _ParpadeoState extends State<_Parpadeo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (widget.activo) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Parpadeo anterior) {
    super.didUpdateWidget(anterior);
    if (widget.activo && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.activo && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_c),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de espera
// ---------------------------------------------------------------------------

class _TarjetaFila extends ConsumerWidget {
  final List<EsperaSalida> fila;
  final bool hayCupo;

  const _TarjetaFila({required this.fila, required this.hayCupo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ambar.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fila de espera', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
          const Text(
            'El grupo ya tiene a alguien fuera. Salen de a uno.',
            style: TextStyle(color: _gris, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < fila.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _ambar,
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${fila[i].estudiante.nombre} · ${fila[i].motivo.etiqueta}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (i == 0 && hayCupo)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _verde,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final r = ref.read(banosProvider.notifier).autorizarDesdeFila(fila[i]);
                        final mensaje = switch (r) {
                          Autorizada(:final salida) => 'Salió ${salida.estudianteNombre}.',
                          EnEspera() => 'Sigue en espera.',
                          Rechazada(:final razon) => razon,
                        };
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
                      },
                      child: const Text('Autorizar ahora', style: TextStyle(fontSize: 12)),
                    ),
                  IconButton(
                    tooltip: 'Quitar de la fila',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => ref.read(esperaProvider.notifier).quitar(fila[i].id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actividad reciente y botones
// ---------------------------------------------------------------------------

class _FilaActividad extends StatelessWidget {
  final SalidaBano salida;
  const _FilaActividad({required this.salida});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: _verde, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: salida.estudianteNombre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' regresó'),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Duración: ${salida.duracionMinutos} minutos',
            style: const TextStyle(color: _gris, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BotonSecundario extends StatelessWidget {
  final String texto;
  final VoidCallback onTap;
  const _BotonSecundario({required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: _navy,
        side: BorderSide(color: _navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
