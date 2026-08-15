import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';

/// Punto de entrada del módulo Control Baños SS.
///
/// Andamiaje de otro equipo. Lo único que demuestra por ahora es el patrón de
/// integración: el módulo **consume** la sesión de `core/auth` y no pide
/// credenciales propias.
///
/// Nótese que este archivo importa solo de `lib/core/`. No conoce ni una clase
/// del Sistema de Timbre Escolar, y por eso puede borrarse entero sin romperlo.
///
/// Usa su propia identidad visual —Azul Marino #1E2545, su RNF06— y no la
/// paleta dorada de SwiftyRing: son marcas independientes que comparten
/// aplicación, no una familia de marca.
class BanosInicioPage extends ConsumerWidget {
  const BanosInicioPage({super.key});

  static const _navy = Color(0xFF1E2545);
  static const _verde = Color(0xFF2D8C3E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    // RF02 de su documento: el rol `operador` no tiene acceso. El lanzador ya
    // no le muestra la tarjeta, pero esta comprobación queda por si se llega
    // a la ruta directamente.
    if (sesion.rol == RolUsuario.operador) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('Control Baños'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu rol de operador no tiene acceso al control de salidas al '
              'baño. Habla con coordinación si crees que es un error.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Control Baños SS'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.meeting_room_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sesión de ${sesion.nombre}',
                style: const TextStyle(fontSize: 18, color: _navy),
              ),
              const SizedBox(height: 4),
              Text(
                sesion.rol.etiqueta,
                style: const TextStyle(color: _verde, fontSize: 14),
              ),
              const SizedBox(height: 24),
              const Text(
                'Módulo pendiente de desarrollo por su equipo.\n'
                'La identidad ya llega resuelta desde el login único.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7189), height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
