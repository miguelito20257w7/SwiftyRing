import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_horario.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

const _navy = Color(0xFF1E2545);
const _verde = Color(0xFF2D8C3E);
const _gris = Color(0xFF6B7189);

/// Pantalla "Autorizar salida" del prototipado: hora y fecha (las pone el
/// sistema), grupo (el que le toca al docente), estudiante de ESE grupo,
/// motivo y una nota opcional.
///
/// Aquí se aplican las reglas: un estudiante a la vez por grupo (los demás
/// quedan en fila de espera) y máximo de salidas por día.
class AutorizarSalidaPage extends ConsumerStatefulWidget {
  const AutorizarSalidaPage({super.key});

  @override
  ConsumerState<AutorizarSalidaPage> createState() => _AutorizarSalidaPageState();
}

class _AutorizarSalidaPageState extends ConsumerState<AutorizarSalidaPage> {
  final _notaCtrl = TextEditingController();
  Estudiante? _estudiante;
  MotivoSalida _motivo = MotivoSalida.bano;

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  void _salir() => context.canPop() ? context.pop() : context.go(RutasBanos.inicio);

  void _aviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Por qué un estudiante no se puede elegir ahora (null = sí se puede).
  String? _bloqueo(Estudiante e) {
    final salidas = ref.read(banosProvider);
    final config = ref.read(banosConfigProvider);
    if (salidas.any((s) => s.enCurso && s.estudianteId == e.id)) {
      return 'Fuera del aula';
    }
    final usadas = salidasContadasHoy(salidas, e.id);
    if (!_motivo.exento && usadas >= config.maxSalidasDia) {
      return 'Ya usó sus ${config.maxSalidasDia} salidas de hoy';
    }
    return null;
  }

  Future<void> _elegirEstudiante(List<Estudiante> estudiantes) async {
    final config = ref.read(banosConfigProvider);
    final salidas = ref.read(banosProvider);
    final elegido = await showModalBottomSheet<Estudiante>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Elegir estudiante',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              for (final e in estudiantes)
                Builder(builder: (_) {
                  final bloqueo = _bloqueo(e);
                  final usadas = salidasContadasHoy(salidas, e.id);
                  return ListTile(
                    enabled: bloqueo == null,
                    title: Text(e.nombre),
                    subtitle: Text(
                      bloqueo ?? '$usadas de ${config.maxSalidasDia} salidas hoy',
                      style: TextStyle(color: bloqueo == null ? _gris : Colors.red, fontSize: 12),
                    ),
                    trailing: _estudiante?.id == e.id
                        ? const Icon(Icons.check, color: _verde)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(e),
                  );
                }),
            ],
          ),
        ),
      ),
    );
    if (elegido != null) setState(() => _estudiante = elegido);
  }

  void _autorizar() {
    final estudiante = _estudiante;
    if (estudiante == null) {
      _aviso('Elige un estudiante.');
      return;
    }
    final nota = _notaCtrl.text.trim();
    final resultado = ref.read(banosProvider.notifier).solicitarSalida(
      estudiante: estudiante,
      motivo: _motivo,
      nota: nota.isEmpty ? null : nota,
    );

    switch (resultado) {
      case Autorizada(:final salida):
        // `pushReplacement` cambia esta pantalla por la confirmación sin
        // borrar el camino de regreso (así Cancelar siempre funciona).
        context.pushReplacement(RutasBanos.confirmacion, extra: salida);
      case EnEspera(:final espera, :final posicion):
        _aviso(
          'El grupo ya tiene a alguien fuera. ${espera.estudiante.nombre} quedó '
          'en la fila de espera (lugar #$posicion).',
        );
        _salir();
      case Rechazada(:final razon):
        _aviso(razon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupo = ref.watch(grupoActivoProvider);
    final todos = ref.watch(estudiantesProvider);
    final ahora = DateTime.now();
    final grado = grupo.grado;
    final hayGrupo = grupo.estado == EstadoGrupo.enClase && grado != null;
    final estudiantes = hayGrupo ? todos.where((e) => e.grado == grado).toList() : <Estudiante>[];

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
      ),
      body: !hayGrupo
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No hay un grupo activo en este momento.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _salir, child: const Text('Volver')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Autorizar salida',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
                ),
                const Text(
                  'REGISTRA UNA NUEVA SALIDA DESDE EL AULA.',
                  style: TextStyle(color: _gris, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _CampoFijo(etiqueta: 'HORA', valor: formatearHora(ahora))),
                          const SizedBox(width: 12),
                          Expanded(child: _CampoFijo(etiqueta: 'FECHA', valor: formatearFecha(ahora))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _CampoFijo(etiqueta: 'GRUPO', valor: grado ?? ''),
                      const SizedBox(height: 16),
                      const Text('ESTUDIANTE',
                          style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: estudiantes.isEmpty ? null : () => _elegirEstudiante(estudiantes),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Text(
                            estudiantes.isEmpty
                                ? 'No hay estudiantes cargados para este grupo'
                                : (_estudiante?.nombre ?? 'Toca para elegir'),
                            style: TextStyle(
                              color: _estudiante == null ? _gris : _navy,
                              fontWeight: _estudiante == null ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('MOTIVO',
                          style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: MotivoSalida.values.map((m) {
                          final seleccionado = m == _motivo;
                          return ChoiceChip(
                            label: Text(m.etiqueta),
                            selected: seleccionado,
                            selectedColor: _verde,
                            labelStyle: TextStyle(
                              color: seleccionado ? Colors.white : _navy,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() {
                              _motivo = m;
                              // Si el estudiante elegido ya no aplica con este
                              // motivo, se deselecciona.
                              final e = _estudiante;
                              if (e != null && _bloqueo(e) != null) _estudiante = null;
                            }),
                          );
                        }).toList(),
                      ),
                      if (_motivo.exento)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Enfermería no cuenta para el límite diario ni ocupa el cupo del grupo.',
                            style: TextStyle(fontSize: 11, color: _gris),
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text('NOTA (OPCIONAL)',
                          style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _notaCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Ej: se sintió mal después del recreo',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _verde,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _autorizar,
                        child: const Text('AUTORIZAR\nSALIDA',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _salir,
                        child: const Text('CANCELAR', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// dd/MM/yyyy, sin depender del paquete `intl`.
String formatearFecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// HH:mm en formato 24 horas.
String formatearHora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _CampoFijo extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _CampoFijo({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: const TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
