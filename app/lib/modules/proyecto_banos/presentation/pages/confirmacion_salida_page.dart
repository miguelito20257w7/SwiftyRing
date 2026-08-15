import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/presentation/pages/autorizar_salida_page.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';
import 'package:swiftyring/core/router/rutas.dart';

/// Pantalla "Confirmación de salida" del prototipado: el check verde, los
/// datos del registro, y los dos botones de siguiente acción.
class ConfirmacionSalidaPage extends StatelessWidget {
  final SalidaBano salida;
  const ConfirmacionSalidaPage({super.key, required this.salida});

  static const _navy = Color(0xFF1E2545);
  static const _verde = Color(0xFF2D8C3E);

  @override
  Widget build(BuildContext context) {
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('CONFIRMACIÓN DE SALIDA', style: TextStyle(color: Color(0xFF6B7189), fontSize: 12)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: _verde, size: 48),
                const SizedBox(height: 12),
                const Text('Salida autorizada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  'Ha sido autorizada la salida de ${salida.estudianteNombre}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7189)),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(salida.estudianteNombre, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatearFecha(salida.horaSalida)),
                    Text(formatearHora(salida.horaSalida), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Grado: ${salida.grado}'),
                    Text(salida.motivo.etiqueta.toLowerCase()),
                  ],
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
                  onPressed: () => context.go(RutasBanos.inicio),
                  child: const Text('VOLVER AL\nINICIO', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
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
                  onPressed: () => context.go(RutasBanos.autorizar),
                  child: const Text('+ NUEVA SALIDA', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
