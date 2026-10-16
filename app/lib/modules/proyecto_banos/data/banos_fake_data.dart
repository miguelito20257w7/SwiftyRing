import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';

/// Datos de prueba y reglas de negocio mientras no existe el backend de baños.
///
/// Todo lo que está aquí (lista de estudiantes, salidas) vive en memoria. El
/// día que exista el servidor, `estudiantesProvider` y `BanosNotifier` se
/// cambian para leer/escribir en la API; las REGLAS (un estudiante a la vez
/// por grupo, máximo de salidas por día, fila de espera) pasan al servidor y
/// las pantallas casi no se tocan.

// ---------------------------------------------------------------------------
// Estudiantes de prueba, por grupo
// ---------------------------------------------------------------------------

const _estudiantesDePrueba = <Estudiante>[
  Estudiante(id: 'e-11B-01', nombre: 'Santiago Chalarca', grado: '11-B'),
  Estudiante(id: 'e-11B-02', nombre: 'Isabel Galeano', grado: '11-B'),
  Estudiante(id: 'e-11B-03', nombre: 'Miguel Angel Salazar', grado: '11-B'),
  Estudiante(id: 'e-11B-04', nombre: 'Nicolas Ferrer', grado: '11-B'),
  Estudiante(id: 'e-11B-05', nombre: 'Juan Esteban Lopez', grado: '11-B'),
  Estudiante(id: 'e-11B-06', nombre: 'Valentina Ríos', grado: '11-B'),
  Estudiante(id: 'e-11B-07', nombre: 'Camila Torres', grado: '11-B'),
  Estudiante(id: 'e-11B-08', nombre: 'Samuel Ospina', grado: '11-B'),
  Estudiante(id: 'e-10A-01', nombre: 'Daniela Marín', grado: '10-A'),
  Estudiante(id: 'e-10A-02', nombre: 'Andrés Cardona', grado: '10-A'),
  Estudiante(id: 'e-10A-03', nombre: 'Laura Henao', grado: '10-A'),
  Estudiante(id: 'e-10A-04', nombre: 'Sebastián Gil', grado: '10-A'),
  Estudiante(id: 'e-9C-01', nombre: 'Mariana Zapata', grado: '9-C'),
  Estudiante(id: 'e-9C-02', nombre: 'Felipe Arango', grado: '9-C'),
  Estudiante(id: 'e-9C-03', nombre: 'Sara Quintero', grado: '9-C'),
  Estudiante(id: 'e-7A-01', nombre: 'Tomás Vargas', grado: '7-A'),
  Estudiante(id: 'e-7A-02', nombre: 'Luciana Parra', grado: '7-A'),
  Estudiante(id: 'e-7A-03', nombre: 'Emanuel Cruz', grado: '7-A'),
];

final estudiantesProvider = Provider<List<Estudiante>>(
  (ref) => _estudiantesDePrueba,
);

/// Grupos que existen (11-B, 10-A...), sin repetir y ordenados.
final gradosProvider = Provider<List<String>>((ref) {
  final grados = ref.watch(estudiantesProvider).map((e) => e.grado).toSet().toList();
  grados.sort();
  return grados;
});

// ---------------------------------------------------------------------------
// Reglas
// ---------------------------------------------------------------------------

/// Cuántas salidas "que cuentan" lleva hoy un estudiante (enfermería no
/// cuenta).
int salidasContadasHoy(List<SalidaBano> salidas, String estudianteId) =>
    salidas
        .where((s) => s.estudianteId == estudianteId && s.esDeHoy && !s.motivo.exento)
        .length;

// ---------------------------------------------------------------------------
// Fila de espera
// ---------------------------------------------------------------------------

class EsperaNotifier extends Notifier<List<EsperaSalida>> {
  @override
  List<EsperaSalida> build() => const [];

  /// Agrega al estudiante al final de la fila (si ya estaba, no lo repite).
  EsperaSalida agregar(Estudiante estudiante, MotivoSalida motivo, String? nota) {
    for (final e in state) {
      if (e.estudiante.id == estudiante.id) return e;
    }
    final nueva = EsperaSalida(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      estudiante: estudiante,
      motivo: motivo,
      nota: nota,
      desde: DateTime.now(),
    );
    state = [...state, nueva];
    return nueva;
  }

  void quitar(String id) => state = state.where((e) => e.id != id).toList();

  void quitarEstudiante(String estudianteId) =>
      state = state.where((e) => e.estudiante.id != estudianteId).toList();

  /// Lugar en la fila de su grupo (1 = el siguiente).
  int posicionDe(EsperaSalida espera) {
    final fila = state.where((e) => e.estudiante.grado == espera.estudiante.grado).toList();
    return fila.indexWhere((e) => e.id == espera.id) + 1;
  }
}

final esperaProvider =
    NotifierProvider<EsperaNotifier, List<EsperaSalida>>(EsperaNotifier.new);

// ---------------------------------------------------------------------------
// Salidas
// ---------------------------------------------------------------------------

class BanosNotifier extends Notifier<List<SalidaBano>> {
  @override
  List<SalidaBano> build() {
    final ahora = DateTime.now();
    // Datos de ejemplo del prototipo: Santiago está fuera ahora; Isabel y
    // Miguel Ángel ya volvieron.
    return [
      SalidaBano(
        id: '1',
        estudianteId: 'e-11B-01',
        estudianteNombre: 'Santiago Chalarca',
        grado: '11-B',
        motivo: MotivoSalida.bano,
        horaSalida: ahora.subtract(const Duration(minutes: 3)),
      ),
      SalidaBano(
        id: '2',
        estudianteId: 'e-11B-02',
        estudianteNombre: 'Isabel Galeano',
        grado: '11-B',
        motivo: MotivoSalida.bano,
        horaSalida: ahora.subtract(const Duration(minutes: 12)),
        horaRegreso: ahora.subtract(const Duration(minutes: 6)),
      ),
      SalidaBano(
        id: '3',
        estudianteId: 'e-11B-03',
        estudianteNombre: 'Miguel Angel Salazar',
        grado: '11-B',
        motivo: MotivoSalida.agua,
        horaSalida: ahora.subtract(const Duration(minutes: 40)),
        horaRegreso: ahora.subtract(const Duration(minutes: 37)),
      ),
    ];
  }

  /// ¿El grupo ya tiene a todos sus cupos fuera del aula?
  bool grupoLleno(String grado) {
    final capacidad = ref.read(banosConfigProvider).capacidadPorGrupo;
    final fuera = state.where((s) => s.enCurso && s.grado == grado && !s.motivo.exento).length;
    return fuera >= capacidad;
  }

  /// Pide una salida aplicando las reglas:
  /// 1. Si ya está fuera del aula, no.
  /// 2. Si ya usó sus salidas del día, no (enfermería es excepción).
  /// 3. Si el grupo está lleno, o hay alguien esperando antes que él, va a la
  ///    fila de espera.
  /// 4. Si no, sale.
  ResultadoAutorizacion solicitarSalida({
    required Estudiante estudiante,
    required MotivoSalida motivo,
    String? nota,
  }) {
    final config = ref.read(banosConfigProvider);
    final espera = ref.read(esperaProvider.notifier);

    if (state.any((s) => s.enCurso && s.estudianteId == estudiante.id)) {
      return Rechazada('${estudiante.nombre} ya está fuera del aula.');
    }

    if (!motivo.exento &&
        salidasContadasHoy(state, estudiante.id) >= config.maxSalidasDia) {
      return Rechazada(
        '${estudiante.nombre} ya usó sus ${config.maxSalidasDia} salidas de hoy.',
      );
    }

    if (!motivo.exento) {
      final fila = ref
          .read(esperaProvider)
          .where((e) => e.estudiante.grado == estudiante.grado)
          .toList();
      final esSuTurno = fila.isEmpty || fila.first.estudiante.id == estudiante.id;
      if (grupoLleno(estudiante.grado) || !esSuTurno) {
        final enFila = espera.agregar(estudiante, motivo, nota);
        return EnEspera(enFila, espera.posicionDe(enFila));
      }
    }

    espera.quitarEstudiante(estudiante.id);
    final nueva = SalidaBano(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      estudianteId: estudiante.id,
      estudianteNombre: estudiante.nombre,
      grado: estudiante.grado,
      motivo: motivo,
      horaSalida: DateTime.now(),
      nota: nota,
    );
    state = [nueva, ...state];
    return Autorizada(nueva);
  }

  /// El profesor toca "Autorizar ahora" sobre alguien de la fila.
  ResultadoAutorizacion autorizarDesdeFila(EsperaSalida e) => solicitarSalida(
    estudiante: e.estudiante,
    motivo: e.motivo,
    nota: e.nota,
  );

  /// Marca que un estudiante ya regresó al aula.
  void registrarRegreso(String id) {
    state = [
      for (final salida in state)
        if (salida.id == id) salida.conRegreso() else salida,
    ];
  }
}

final banosProvider = NotifierProvider<BanosNotifier, List<SalidaBano>>(
  BanosNotifier.new,
);

/// Los que siguen fuera del aula ahora mismo (de todos los grupos).
final salidasEnCursoProvider = Provider<List<SalidaBano>>(
  (ref) => ref.watch(banosProvider).where((s) => s.enCurso).toList(),
);
