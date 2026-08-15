import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/presentation/pages/autorizar_salida_page.dart'
    show formatearHora;
import 'package:swiftyring/modules/proyecto_banos/presentation/widgets/banos_bottom_nav.dart';
import 'package:swiftyring/core/router/rutas.dart';

/// Pantalla "Historial de salidas" del prototipado: buscador + tabla con
/// fecha, estudiante, duración y estado.
class HistorialPage extends ConsumerStatefulWidget {
  const HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  static const _navy = Color(0xFF1E2545);
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todas = ref.watch(banosProvider);
    final filtradas = todas
        .where((s) => s.estudianteNombre.toLowerCase().contains(_busqueda.toLowerCase()))
        .toList();

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
      bottomNavigationBar: const BanosBottomNav(indiceActual: 1),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historial de salidas',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
                ),
                const Text(
                  'CONSULTA TODAS LAS SALIDAS REGISTRADAS.',
                  style: TextStyle(color: Color(0xFF6B7189), fontSize: 12),
                ),
                const SizedBox(height: 12),
                // "EXPORTAR" del prototipo: se deja lista la pantalla, pero
                // exportar de verdad (a Excel/PDF) solo tiene sentido cuando
                // los datos vengan del backend real, así que por ahora avisa
                // que está pendiente en vez de fingir que ya funciona.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D8C3E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Exportar estará disponible cuando el historial venga del servidor.')),
                      );
                    },
                    child: const Text('EXPORTAR'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Buscar estudiante...',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                SizedBox(width: 56, child: Text('FECHA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7189)))),
                Expanded(child: Text('ESTUDIANTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7189)))),
                SizedBox(width: 8),
                SizedBox(width: 64, child: Text('DURACIÓN', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7189)))),
                SizedBox(width: 8),
                SizedBox(width: 76, child: Text('ESTADO', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7189)))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtradas.isEmpty
                ? const Center(
                    child: Text('No hay salidas que coincidan.', style: TextStyle(color: Color(0xFF6B7189))),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtradas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _FilaHistorial(salida: filtradas[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  final SalidaBano salida;
  const _FilaHistorial({required this.salida});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(formatearHora(salida.horaSalida), style: const TextStyle(fontSize: 12, color: Color(0xFF6B7189)))),
          Expanded(
            child: Text(salida.estudianteNombre, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              salida.enCurso ? '—' : '${salida.duracionMinutos} min',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Center(child: _EtiquetaEstado(enCurso: salida.enCurso)),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  final bool enCurso;
  const _EtiquetaEstado({required this.enCurso});

  @override
  Widget build(BuildContext context) {
    final color = enCurso ? const Color(0xFF2D8C3E) : const Color(0xFF1E2545);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(20)),
      child: Text(
        enCurso ? 'en curso' : 'OK',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
