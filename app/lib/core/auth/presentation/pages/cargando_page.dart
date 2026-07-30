import 'package:flutter/material.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';

/// Pantalla mientras se restaura la sesión guardada.
///
/// Dura lo que tarde una lectura del almacenamiento seguro: unos milisegundos.
/// Usa el mismo fondo que la bienvenida para que la transición no se note.
class CargandoPage extends StatelessWidget {
  const CargandoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.fondo,
      body: Stack(
        children: [
          FondoDecorado(),
          Center(child: CircularProgressIndicator(color: AppColors.dorado)),
        ],
      ),
    );
  }
}
