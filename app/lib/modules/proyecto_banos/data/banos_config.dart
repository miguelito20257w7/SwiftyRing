import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ajustes del módulo Control Baños SS.
///
/// Por ahora viven en memoria (se reinician al cerrar la app). Cuando exista
/// el backend de baños, este mismo estado se guarda en el servidor y las
/// pantallas que lo leen no cambian.
class BanosConfig {
  /// Grado que aparece ya escrito en el formulario de autorizar salida.
  final String gradoPorDefecto;

  /// Minutos máximos esperados fuera del aula. Pasado este tiempo, el
  /// estudiante se resalta en rojo en el inicio y Reportes avisa.
  final int minutosLimite;

  const BanosConfig({this.gradoPorDefecto = '11-B', this.minutosLimite = 10});

  BanosConfig copyWith({String? gradoPorDefecto, int? minutosLimite}) =>
      BanosConfig(
        gradoPorDefecto: gradoPorDefecto ?? this.gradoPorDefecto,
        minutosLimite: minutosLimite ?? this.minutosLimite,
      );
}

class BanosConfigNotifier extends Notifier<BanosConfig> {
  @override
  BanosConfig build() => const BanosConfig();

  void cambiarGrado(String grado) =>
      state = state.copyWith(gradoPorDefecto: grado.trim());

  void cambiarMinutosLimite(int minutos) =>
      state = state.copyWith(minutosLimite: minutos.clamp(1, 60));
}

final banosConfigProvider =
    NotifierProvider<BanosConfigNotifier, BanosConfig>(BanosConfigNotifier.new);
