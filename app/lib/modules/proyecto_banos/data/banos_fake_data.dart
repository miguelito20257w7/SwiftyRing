import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';

/// Guarda y modifica la lista de salidas mientras no existe el backend real.
///
/// Es un `Notifier` (el mismo patrón que usa el módulo del timbre, ver
/// `FiltroHistorialNotifier` en `providers.dart`), así que el día que
/// conectemos al backend, esta clase se puede volver un `AsyncNotifier` que
/// llame a la API en vez de tocar una lista en memoria — las pantallas que la
/// consumen no tendrían que cambiar casi nada.
class BanosNotifier extends Notifier<List<SalidaBano>> {
  @override
  List<SalidaBano> build() {
    final ahora = DateTime.now();
    // Datos de ejemplo, tomados de tu prototipo, para que el panel no se vea
    // vacío mientras desarrollas.
    return [
      SalidaBano(
        id: '1',
        estudianteNombre: 'Santiago Chalarca',
        grado: '11-B',
        motivo: MotivoSalida.bano,
        horaSalida: ahora.subtract(const Duration(minutes: 3)),
      ),
      SalidaBano(
        id: '2',
        estudianteNombre: 'Isabel Galeano',
        grado: '11-B',
        motivo: MotivoSalida.bano,
        horaSalida: ahora.subtract(const Duration(minutes: 12)),
        horaRegreso: ahora.subtract(const Duration(minutes: 6)),
      ),
      SalidaBano(
        id: '3',
        estudianteNombre: 'Miguel Angel Salazar',
        grado: '11-B',
        motivo: MotivoSalida.agua,
        horaSalida: ahora.subtract(const Duration(minutes: 40)),
        horaRegreso: ahora.subtract(const Duration(minutes: 37)),
      ),
    ];
  }

  /// RF: registrar una nueva salida al baño (pantalla "Autorizar salida").
  void autorizarSalida({
    required String estudianteNombre,
    required String grado,
    required MotivoSalida motivo,
    String? nota,
  }) {
    final nueva = SalidaBano(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      estudianteNombre: estudianteNombre,
      grado: grado,
      motivo: motivo,
      horaSalida: DateTime.now(),
      nota: nota,
    );
    state = [nueva, ...state];
  }

  /// RF: marcar que un estudiante ya regresó al aula.
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

/// Derivado: solo los estudiantes que siguen fuera del aula ahora mismo.
final salidasEnCursoProvider = Provider<List<SalidaBano>>(
  (ref) => ref.watch(banosProvider).where((s) => s.enCurso).toList(),
);
