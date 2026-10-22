import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ajustes del módulo Control Baños SS.
///
/// Por ahora viven en memoria (se reinician al cerrar la app). Cuando exista
/// el backend de baños, este mismo estado se guarda en el servidor y las
/// pantallas que lo leen no cambian.
class BanosConfig {
  /// Grupo con el que se trabaja cuando no hay horario (administrador o modo
  /// manual).
  final String gradoPorDefecto;

  /// Minutos máximos esperados fuera del aula. Verde por debajo del 70 %,
  /// amarillo hasta el límite, rojo parpadeante al superarlo.
  final int minutosLimite;

  /// Máximo de salidas por estudiante en un día (no cuenta enfermería).
  final int maxSalidasDia;

  /// Cuántos estudiantes de un mismo grupo pueden estar fuera a la vez.
  final int capacidadPorGrupo;

  /// Sonido y vibración cuando alguien supera el tiempo límite.
  final bool alertaSonora;

  /// Elegir el grupo a mano en vez de usar el horario del docente.
  final bool modoManual;

  const BanosConfig({
    this.gradoPorDefecto = '11-B',
    this.minutosLimite = 10,
    this.maxSalidasDia = 2,
    this.capacidadPorGrupo = 1,
    this.alertaSonora = false,
    this.modoManual = false,
  });

  BanosConfig copyWith({
    String? gradoPorDefecto,
    int? minutosLimite,
    int? maxSalidasDia,
    int? capacidadPorGrupo,
    bool? alertaSonora,
    bool? modoManual,
  }) => BanosConfig(
    gradoPorDefecto: gradoPorDefecto ?? this.gradoPorDefecto,
    minutosLimite: minutosLimite ?? this.minutosLimite,
    maxSalidasDia: maxSalidasDia ?? this.maxSalidasDia,
    capacidadPorGrupo: capacidadPorGrupo ?? this.capacidadPorGrupo,
    alertaSonora: alertaSonora ?? this.alertaSonora,
    modoManual: modoManual ?? this.modoManual,
  );
}

class BanosConfigNotifier extends Notifier<BanosConfig> {
  @override
  BanosConfig build() => const BanosConfig();

  void cambiarGrado(String grado) =>
      state = state.copyWith(gradoPorDefecto: grado.trim());

  void cambiarMinutosLimite(int minutos) =>
      state = state.copyWith(minutosLimite: minutos.clamp(1, 60));

  void cambiarMaxSalidasDia(int cantidad) =>
      state = state.copyWith(maxSalidasDia: cantidad.clamp(1, 10));

  void cambiarCapacidadPorGrupo(int cantidad) =>
      state = state.copyWith(capacidadPorGrupo: cantidad.clamp(1, 5));

  void cambiarAlertaSonora(bool valor) =>
      state = state.copyWith(alertaSonora: valor);

  void cambiarModoManual(bool valor) =>
      state = state.copyWith(modoManual: valor);
}

final banosConfigProvider =
    NotifierProvider<BanosConfigNotifier, BanosConfig>(BanosConfigNotifier.new);
