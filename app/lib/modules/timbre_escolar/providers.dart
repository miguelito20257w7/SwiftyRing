import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';

/// Providers del módulo Timbre Escolar.
///
/// Todos los de lectura son `FutureProvider.autoDispose`: cada pantalla carga
/// lo suyo al entrar y lo suelta al salir. Las escrituras llaman a [TimbreApi]
/// directamente desde la pantalla y luego invalidan el provider afectado, que
/// es la forma más simple de mantener la lista fresca sin duplicar estado.

final timbreApiProvider = Provider<TimbreApi>(
  (ref) => TimbreApi(dio: ref.watch(apiProvider).dio),
);

/// F-02: lo que suena hoy (lista, próximo, horario vigente).
final timbresHoyProvider = FutureProvider.autoDispose<TimbresHoy>(
  (ref) => ref.watch(timbreApiProvider).timbresHoy(),
);

/// RF-07..09: el horario habitual completo.
final timbresProvider = FutureProvider.autoDispose<List<TimbreHabitual>>(
  (ref) => ref.watch(timbreApiProvider).listarTimbres(),
);

/// RF-10..13: horarios especiales (solo admin; a los demás el backend les
/// responde 403 y la pantalla ni siquiera se les ofrece).
final especialesProvider = FutureProvider.autoDispose<List<HorarioEspecial>>(
  (ref) => ref.watch(timbreApiProvider).listarEspeciales(),
);

final materiasProvider = FutureProvider.autoDispose<List<Materia>>(
  (ref) => ref.watch(timbreApiProvider).listarMaterias(),
);

final salonesProvider = FutureProvider.autoDispose<List<Salon>>(
  (ref) => ref.watch(timbreApiProvider).listarSalones(),
);

/// RF-32/33: los docentes con sus materias.
final docentesProvider = FutureProvider.autoDispose<List<Docente>>(
  (ref) => ref.watch(timbreApiProvider).listarDocentes(),
);

/// F-06: el horario de un salón para un día concreto.
final horarioSalonProvider = FutureProvider.autoDispose
    .family<HorarioSalon, ({String salonId, DiaSemana dia})>(
      (ref, args) =>
          ref.watch(timbreApiProvider).horarioDeSalon(args.salonId, args.dia),
    );

/// RF-40: el horario semanal del profesor autenticado.
final miHorarioProvider = FutureProvider.autoDispose<MiHorario>(
  (ref) => ref.watch(timbreApiProvider).miHorario(),
);

/// F-08: filtro de fechas del historial (`null` = sin filtro). Vive en un
/// provider para que las tres listas lo compartan.
class FiltroHistorialNotifier extends Notifier<({String? desde, String? hasta})> {
  @override
  ({String? desde, String? hasta}) build() => (desde: null, hasta: null);

  void fijar({String? desde, String? hasta}) =>
      state = (desde: desde, hasta: hasta);

  void limpiar() => state = (desde: null, hasta: null);
}

final filtroHistorialProvider =
    NotifierProvider<FiltroHistorialNotifier, ({String? desde, String? hasta})>(
      FiltroHistorialNotifier.new,
    );

final activacionesProvider = FutureProvider.autoDispose<List<Activacion>>((ref) {
  final filtro = ref.watch(filtroHistorialProvider);
  return ref
      .watch(timbreApiProvider)
      .listarActivaciones(desde: filtro.desde, hasta: filtro.hasta);
});

final sismosProvider = FutureProvider.autoDispose<List<Sismo>>((ref) {
  final filtro = ref.watch(filtroHistorialProvider);
  return ref
      .watch(timbreApiProvider)
      .listarSismos(desde: filtro.desde, hasta: filtro.hasta);
});

final notificacionesProvider = FutureProvider.autoDispose<List<Notificacion>>(
  (ref) => ref.watch(timbreApiProvider).listarNotificaciones(),
);

final configuracionProvider = FutureProvider.autoDispose<Configuracion>(
  (ref) => ref.watch(timbreApiProvider).configuracion(),
);

final usuariosProvider = FutureProvider.autoDispose<List<UsuarioAdmin>>(
  (ref) => ref.watch(timbreApiProvider).listarUsuarios(),
);
