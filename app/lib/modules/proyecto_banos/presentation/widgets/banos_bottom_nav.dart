import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

/// Barra de abajo (Inicio / Historial / Reportes) del prototipado.
///
/// Vive en `widgets/` porque las tres pantallas principales la comparten
/// igual — así, si un día cambia el diseño de la barra, se edita en un solo
/// lugar en vez de en tres.
class BanosBottomNav extends StatelessWidget {
  final int indiceActual;
  const BanosBottomNav({super.key, required this.indiceActual});

  static const _navy = Color(0xFF1E2545);

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: indiceActual,
      selectedItemColor: _navy,
      unselectedItemColor: const Color(0xFF6B7189),
      onTap: (indice) {
        if (indice == indiceActual) return;
        switch (indice) {
          case 0:
            context.go(RutasBanos.inicio);
          case 1:
            context.go(RutasBanos.historial);
          case 2:
            context.go(RutasBanos.reportes);
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Inicio'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reportes'),
      ],
    );
  }
}
