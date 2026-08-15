import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';
import 'package:swiftyring/modules/proyecto_banos/presentation/widgets/banos_bottom_nav.dart';
import 'package:swiftyring/core/router/rutas.dart';

/// Pantalla "Reportes - Estadísticas" del prototipado.
///
/// Importante: estos números NO están escritos a mano — se calculan a partir
/// de lo que haya en `banosProvider` en este momento. Con los 3 datos de
/// ejemplo se van a ver pequeños; eso es correcto, es justo lo que se espera
/// que pase con pocos registros.
class ReportesPage extends ConsumerWidget {
  const ReportesPage({super.key});

  static const _navy = Color(0xFF1E2545);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todas = ref.watch(banosProvider);
    final completadas = todas.where((s) => !s.enCurso).toList();

    final total = todas.length;
    final duracionProm = completadas.isEmpty
        ? 0
        : (completadas.map((s) => s.duracionMinutos).reduce((a, b) => a + b) / completadas.length).round();

    // "Emergencias": lo interpreto como salidas por motivo Enfermería, ya
    // que el prototipo no explica qué cuenta como emergencia. Si tu
    // instructor tiene otra definición, aquí es donde se ajusta.
    final emergencias = todas.where((s) => s.motivo == MotivoSalida.enfermeria).length;

    // Agrupa por estudiante y cuenta cuántas salidas tiene cada uno.
    final conteoPorEstudiante = <String, int>{};
    for (final s in todas) {
      conteoPorEstudiante[s.estudianteNombre] = (conteoPorEstudiante[s.estudianteNombre] ?? 0) + 1;
    }
    final rankingEstudiantes = conteoPorEstudiante.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
      bottomNavigationBar: const BanosBottomNav(indiceActual: 2),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Reportes - Estadísticas',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
          ),
          const Text('Todos los registros', style: TextStyle(color: Color(0xFF6B7189), fontSize: 12)),
          const SizedBox(height: 16),
          _TarjetaMetrica(titulo: 'TOTAL SALIDAS', valor: '$total'),
          const SizedBox(height: 12),
          _TarjetaMetrica(
            titulo: 'DURACIÓN PROM',
            valor: '$duracionProm min',
            nota: completadas.isEmpty ? 'Todavía no hay salidas completadas' : null,
          ),
          const SizedBox(height: 12),
          _TarjetaMetrica(titulo: 'EMERGENCIAS', valor: '$emergencias', valorColor: Colors.red),
          const SizedBox(height: 20),
          const Text(
            'Estudiantes con más salidas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
          ),
          const SizedBox(height: 8),
          if (rankingEstudiantes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aún no hay salidas registradas.', style: TextStyle(color: Color(0xFF6B7189))),
            )
          else
            ...rankingEstudiantes.map((e) => _FilaRanking(nombre: e.key, salidas: e.value)),
        ],
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color? valorColor;
  final String? nota;

  const _TarjetaMetrica({required this.titulo, required this.valor, this.valorColor, this.nota});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7189), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: valorColor ?? const Color(0xFF1E2545))),
          if (nota != null) ...[
            const SizedBox(height: 4),
            Text(nota!, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7189))),
          ],
        ],
      ),
    );
  }
}

class _FilaRanking extends StatelessWidget {
  final String nombre;
  final int salidas;
  const _FilaRanking({required this.nombre, required this.salidas});

  @override
  Widget build(BuildContext context) {
    final iniciales = nombre.split(' ').take(2).map((p) => p.isNotEmpty ? p[0] : '').join().toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: const Color(0xFF1E2545), radius: 16, child: Text(iniciales, style: const TextStyle(color: Colors.white, fontSize: 11))),
          const SizedBox(width: 12),
          Expanded(child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('$salidas', style: const TextStyle(color: Color(0xFF2D8C3E), fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 4),
          const Text('salidas', style: TextStyle(color: Color(0xFF6B7189), fontSize: 11)),
        ],
      ),
    );
  }
}
