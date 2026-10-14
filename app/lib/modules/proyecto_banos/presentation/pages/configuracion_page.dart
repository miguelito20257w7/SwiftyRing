import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

/// Configuración del módulo: cuenta, servidor y parámetros de salidas.
///
/// Sigue la idea de "Ajustes" del timbre (tarjetas por secciones), pero solo
/// con lo que le sirve a Control Baños SS:
/// - Cuenta: quién está dentro y con qué rol (viene de `core/auth`).
/// - Servidor: atajo a los ajustes de red, que viven en `core/` porque la
///   dirección del servidor es de toda la aplicación.
/// - Parámetros: grado por defecto (cualquiera) y minutos límite (solo admin).
class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
  static const _navy = Color(0xFF1E2545);
  static const _verde = Color(0xFF2D8C3E);
  static const _gris = Color(0xFF6B7189);

  late final TextEditingController _gradoCtrl;

  @override
  void initState() {
    super.initState();
    _gradoCtrl = TextEditingController(
      text: ref.read(banosConfigProvider).gradoPorDefecto,
    );
  }

  @override
  void dispose() {
    _gradoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    final config = ref.watch(banosConfigProvider);
    final servidor = ref.watch(servidorProvider);
    final puedeAdministrar = sesion.rol.puedeAdministrar;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(RutasBanos.inicio),
        ),
        title: const Text('Control Baños SS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Configuración',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
          ),
          const Text(
            'Cuenta, servidor y parámetros de salidas',
            style: TextStyle(color: _gris, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // --- Cuenta ---
          _Tarjeta(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: _navy,
                  child: Icon(Icons.person_outline, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sesion.nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                      Text(sesion.email,
                          style: const TextStyle(color: _gris, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _verde.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sesion.rol.etiqueta,
                    style: const TextStyle(color: _verde, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Servidor ---
          _Tarjeta(
            onTap: () => context.push(Rutas.ajustesRed),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, color: _navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Servidor',
                          style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                      Text(servidor,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _navy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _gris),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Parámetros ---
          const Text('Parámetros de salidas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 8),
          _Tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GRADO POR DEFECTO',
                    style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gradoCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Ej: 11-B',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _verde, foregroundColor: Colors.white),
                      onPressed: () {
                        final grado = _gradoCtrl.text.trim();
                        if (grado.isEmpty) return;
                        ref.read(banosConfigProvider.notifier).cambiarGrado(grado);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Grado por defecto: $grado')),
                        );
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
                const Text('Aparece ya escrito al autorizar una salida.',
                    style: TextStyle(fontSize: 11, color: _gris)),
                const Divider(height: 28),
                const Text('TIEMPO LÍMITE FUERA DEL AULA',
                    style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton.outlined(
                      onPressed: puedeAdministrar
                          ? () => ref
                              .read(banosConfigProvider.notifier)
                              .cambiarMinutosLimite(config.minutosLimite - 1)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('${config.minutosLimite} min',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold, color: _navy)),
                    ),
                    IconButton.outlined(
                      onPressed: puedeAdministrar
                          ? () => ref
                              .read(banosConfigProvider.notifier)
                              .cambiarMinutosLimite(config.minutosLimite + 1)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Text(
                  puedeAdministrar
                      ? 'Pasado este tiempo, el estudiante se resalta en rojo.'
                      : 'Solo el administrador puede cambiar este valor.',
                  style: const TextStyle(fontSize: 11, color: _gris),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Cerrar sesión ---
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => ref.read(authProvider.notifier).cerrarSesion(),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Tarjeta({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
