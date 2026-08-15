import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

/// Pantalla "Autorizar salida" del prototipado: hora, fecha (fijas, las pone
/// el sistema), estudiante, motivo y una nota opcional.
class AutorizarSalidaPage extends ConsumerStatefulWidget {
  const AutorizarSalidaPage({super.key});

  @override
  ConsumerState<AutorizarSalidaPage> createState() => _AutorizarSalidaPageState();
}

class _AutorizarSalidaPageState extends ConsumerState<AutorizarSalidaPage> {
  static const _navy = Color(0xFF1E2545);
  static const _verde = Color(0xFF2D8C3E);

  final _formKey = GlobalKey<FormState>();
  final _estudianteCtrl = TextEditingController();
  final _gradoCtrl = TextEditingController(text: '11-B');
  final _notaCtrl = TextEditingController();
  MotivoSalida _motivo = MotivoSalida.bano;

  @override
  void dispose() {
    _estudianteCtrl.dispose();
    _gradoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  void _autorizar() {
    // Valida que el nombre del estudiante no esté vacío antes de seguir.
    if (!_formKey.currentState!.validate()) return;

    ref.read(banosProvider.notifier).autorizarSalida(
          estudianteNombre: _estudianteCtrl.text.trim(),
          grado: _gradoCtrl.text.trim(),
          motivo: _motivo,
          nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
        );

    // La salida que se acaba de crear es siempre la primera de la lista
    // (autorizarSalida la agrega al inicio), así que la tomamos de ahí para
    // llevarla a la pantalla de confirmación.
    final creada = ref.read(banosProvider).first;
    context.go(RutasBanos.confirmacion, extra: creada);
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Control Baños SS'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Autorizar salida',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
            ),
            const Text(
              'REGISTRA UNA NUEVA SALIDA AL BAÑO DESDE EL AULA.',
              style: TextStyle(color: Color(0xFF6B7189), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _CampoFijo(etiqueta: 'HORA', valor: formatearHora(ahora)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CampoFijo(etiqueta: 'FECHA', valor: formatearFecha(ahora)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('ESTUDIANTE', style: TextStyle(fontSize: 12, color: Color(0xFF6B7189))),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _estudianteCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Nombre completo'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre del estudiante' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('GRADO', style: TextStyle(fontSize: 12, color: Color(0xFF6B7189))),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _gradoCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el grado' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('MOTIVO', style: TextStyle(fontSize: 12, color: Color(0xFF6B7189))),
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
                        labelStyle: TextStyle(color: seleccionado ? Colors.white : _navy, fontWeight: FontWeight.w600),
                        onSelected: (_) => setState(() => _motivo = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('NOTA (OPCIONAL)', style: TextStyle(fontSize: 12, color: Color(0xFF6B7189))),
                  const SizedBox(height: 4),
                  TextFormField(
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
                    child: const Text('AUTORIZAR\nSALIDA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
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
                    onPressed: () => context.pop(),
                    child: const Text('CANCELAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        Text(etiqueta, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7189))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDDDDD)), borderRadius: BorderRadius.circular(8)),
          child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
