import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';

/// Qué grupo le toca al docente AHORA, según su horario del timbre.
///
/// El horario ya existe en el servidor (módulo del timbre, endpoint
/// `/mi-horario`). Este módulo lo consume por su cuenta, con su propio modelo
/// mínimo: no importa nada de `timbre_escolar/`, así que sigue siendo
/// independiente (puede borrarse sin romper al otro).

// ---------------------------------------------------------------------------
// Reloj: hace que la pantalla se refresque sola cada 10 segundos
// ---------------------------------------------------------------------------

final relojProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 10), (_) => DateTime.now()),
);

// ---------------------------------------------------------------------------
// Horario del docente (lo que responde /mi-horario)
// ---------------------------------------------------------------------------

class BloqueClase {
  final String horaInicio;
  final String horaFin;
  final String materia;
  final String salon;

  const BloqueClase({
    required this.horaInicio,
    required this.horaFin,
    required this.materia,
    required this.salon,
  });

  factory BloqueClase.fromJson(Map<String, dynamic> json) => BloqueClase(
    horaInicio: json['horaInicio'] as String,
    horaFin: json['horaFin'] as String,
    materia: (json['materia'] as String?) ?? '',
    salon: (json['salon'] as String?) ?? '',
  );
}

class HorarioDocente {
  /// Clases por día de la semana (`lunes`, `martes`...).
  final Map<String, List<BloqueClase>> porDia;

  const HorarioDocente(this.porDia);

  factory HorarioDocente.fromJson(Map<String, dynamic> json) {
    final porDia = <String, List<BloqueClase>>{};
    for (final d in (json['dias'] as List<dynamic>? ?? const [])) {
      final dia = d as Map<String, dynamic>;
      porDia[dia['dia'] as String] = (dia['bloques'] as List<dynamic>? ?? const [])
          .map((b) => BloqueClase.fromJson(b as Map<String, dynamic>))
          .toList();
    }
    return HorarioDocente(porDia);
  }
}

/// `null` si el servidor no tiene horario para esta cuenta (por ejemplo, el
/// administrador no da clases).
final horarioDocenteProvider = FutureProvider.autoDispose<HorarioDocente?>((ref) async {
  final dio = ref.watch(apiProvider).dio;
  final respuesta = await dio.get<dynamic>('/mi-horario');
  if (respuesta.statusCode != 200 || respuesta.data is! Map) return null;
  return HorarioDocente.fromJson((respuesta.data as Map).cast<String, dynamic>());
});

// ---------------------------------------------------------------------------
// Grupo activo
// ---------------------------------------------------------------------------

enum EstadoGrupo { cargando, error, sinHorario, horaLibre, enClase }

class GrupoActivo {
  final EstadoGrupo estado;

  /// Grupo con el que se trabaja (11-B...). Solo si `estado == enClase`.
  final String? grado;
  final String? materia;
  final String? horario;

  /// Texto de apoyo: próxima clase, motivo del error, etc.
  final String? mensaje;

  /// true si el grupo se eligió a mano (administrador o modo manual).
  final bool manual;

  const GrupoActivo({
    required this.estado,
    this.grado,
    this.materia,
    this.horario,
    this.mensaje,
    this.manual = false,
  });
}

/// Grupo elegido a mano. `null` = usar el grupo por defecto de Configuración.
class GrupoManualNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void elegir(String grado) => state = grado;
}

final grupoManualProvider =
    NotifierProvider<GrupoManualNotifier, String?>(GrupoManualNotifier.new);

const _diasSemana = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado'];

String _hm(String hora) => hora.length >= 5 ? hora.substring(0, 5) : hora;

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// "Aula 11-B", "11B", "11 b"... → "11-B" si ese grupo existe en la lista.
String _gradoDeSalon(String salon, List<String> grados) {
  final n = _norm(salon);
  for (final g in grados) {
    if (n.contains(_norm(g))) return g;
  }
  return salon;
}

final grupoActivoProvider = Provider.autoDispose<GrupoActivo>((ref) {
  ref.watch(relojProvider); // recalcula cada 10 s (cambio de hora de clase)
  final sesion = ref.watch(authProvider).session;
  final config = ref.watch(banosConfigProvider);
  final manual = ref.watch(grupoManualProvider);
  final grados = ref.watch(gradosProvider);

  // Administración (coordinadora) y modo manual: se elige el grupo a mano.
  if (sesion == null || sesion.rol.puedeAdministrar || config.modoManual) {
    return GrupoActivo(
      estado: EstadoGrupo.enClase,
      grado: manual ?? config.gradoPorDefecto,
      manual: true,
    );
  }

  final horario = ref.watch(horarioDocenteProvider);
  return horario.when(
    loading: () => const GrupoActivo(estado: EstadoGrupo.cargando),
    error: (e, st) => const GrupoActivo(
      estado: EstadoGrupo.error,
      mensaje: 'No se pudo cargar tu horario. Revisa la conexión con el servidor.',
    ),
    data: (h) {
      if (h == null) {
        return const GrupoActivo(
          estado: EstadoGrupo.sinHorario,
          mensaje: 'Tu cuenta no tiene horario asignado todavía.',
        );
      }
      final ahora = DateTime.now();
      final hoy = ahora.weekday <= 6 ? _diasSemana[ahora.weekday - 1] : null;
      final bloques = hoy == null ? const <BloqueClase>[] : (h.porDia[hoy] ?? const []);
      final hm =
          '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';

      for (final b in bloques) {
        if (_hm(b.horaInicio).compareTo(hm) <= 0 && hm.compareTo(_hm(b.horaFin)) < 0) {
          return GrupoActivo(
            estado: EstadoGrupo.enClase,
            grado: _gradoDeSalon(b.salon, grados),
            materia: b.materia,
            horario: '${_hm(b.horaInicio)} – ${_hm(b.horaFin)}',
          );
        }
      }

      // No hay clase ahora: hora libre. Se busca la próxima del día.
      BloqueClase? proxima;
      for (final b in bloques) {
        if (_hm(b.horaInicio).compareTo(hm) > 0) {
          if (proxima == null || _hm(b.horaInicio).compareTo(_hm(proxima.horaInicio)) < 0) {
            proxima = b;
          }
        }
      }
      return GrupoActivo(
        estado: EstadoGrupo.horaLibre,
        mensaje: proxima == null
            ? 'No tienes más clases hoy.'
            : 'Próxima clase: ${_hm(proxima.horaInicio)} · ${_gradoDeSalon(proxima.salon, grados)}'
                  '${proxima.materia.isEmpty ? '' : ' (${proxima.materia})'}',
      );
    },
  );
});
