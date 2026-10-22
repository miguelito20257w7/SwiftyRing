import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_config.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';

const _navy = Color(0xFF1E2545);
const _verde = Color(0xFF2D8C3E);
const _gris = Color(0xFF6B7189);

/// Configuración del módulo: cuenta, servidor, reglas de salidas y
/// preferencias.
///
/// Sigue la idea de "Ajustes" del timbre (tarjetas por secciones), pero solo
/// con lo que le sirve a Control Baños SS:
/// - Cuenta: quién está dentro y con qué rol (viene de `core/auth`).
/// - Servidor: atajo a los ajustes de red, que viven en `core/`.
/// - Reglas de salidas: solo las edita el administrador (la coordinadora).
/// - Preferencias: las puede cambiar cualquier docente.
class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
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
    final notifier = ref.read(banosConfigProvider.notifier);
    final servidor = ref.watch(servidorProvider);
    final grados = ref.watch(gradosProvider);
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
            'Cuenta, servidor, reglas y preferencias',
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

          // --- Reglas ---
          const _Titulo('Reglas de salidas'),
          _Tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Contador(
                  etiqueta: 'SALIDAS POR ESTUDIANTE AL DÍA',
                  valor: '${config.maxSalidasDia}',
                  ayuda: 'Enfermería no cuenta.',
                  onMenos: puedeAdministrar
                      ? () => notifier.cambiarMaxSalidasDia(config.maxSalidasDia - 1)
                      : null,
                  onMas: puedeAdministrar
                      ? () => notifier.cambiarMaxSalidasDia(config.maxSalidasDia + 1)
                      : null,
                ),
                const Divider(height: 28),
                _Contador(
                  etiqueta: 'ESTUDIANTES A LA VEZ POR GRUPO',
                  valor: '${config.capacidadPorGrupo}',
                  ayuda: 'Los demás quedan en fila de espera.',
                  onMenos: puedeAdministrar
                      ? () => notifier.cambiarCapacidadPorGrupo(config.capacidadPorGrupo - 1)
                      : null,
                  onMas: puedeAdministrar
                      ? () => notifier.cambiarCapacidadPorGrupo(config.capacidadPorGrupo + 1)
                      : null,
                ),
                const Divider(height: 28),
                _Contador(
                  etiqueta: 'TIEMPO LÍMITE FUERA DEL AULA',
                  valor: '${config.minutosLimite} min',
                  ayuda: 'Verde hasta el 70 %, amarillo hasta el límite, rojo después.',
                  onMenos: puedeAdministrar
                      ? () => notifier.cambiarMinutosLimite(config.minutosLimite - 1)
                      : null,
                  onMas: puedeAdministrar
                      ? () => notifier.cambiarMinutosLimite(config.minutosLimite + 1)
                      : null,
                ),
                if (!puedeAdministrar)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Solo el administrador puede cambiar estas reglas.',
                      style: TextStyle(fontSize: 11, color: _gris),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Preferencias ---
          const _Titulo('Preferencias'),
          _Tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alerta sonora', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Suena y vibra cuando alguien supera el tiempo límite.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: config.alertaSonora,
                  onChanged: notifier.cambiarAlertaSonora,
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Elegir grupo manualmente',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    puedeAdministrar
                        ? 'El administrador siempre elige el grupo a mano.'
                        : 'En vez de usar tu horario del timbre. Útil para pruebas.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: puedeAdministrar || config.modoManual,
                  onChanged: puedeAdministrar ? null : notifier.cambiarModoManual,
                ),
                const Divider(),
                const SizedBox(height: 8),
                const Text('GRUPO POR DEFECTO (MODO MANUAL)',
                    style: TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gradoCtrl,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: grados.isEmpty ? 'Ej: 11-B' : 'Ej: ${grados.first}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _verde,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final grado = _gradoCtrl.text.trim();
                        if (grado.isEmpty) return;
                        notifier.cambiarGrado(grado);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Grupo por defecto: $grado')),
                        );
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
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

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      texto,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
    ),
  );
}

/// Etiqueta + valor con botones − y + (null = deshabilitado).
class _Contador extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final String ayuda;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;

  const _Contador({
    required this.etiqueta,
    required this.valor,
    required this.ayuda,
    required this.onMenos,
    required this.onMas,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: const TextStyle(fontSize: 12, color: _gris, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton.outlined(onPressed: onMenos, icon: const Icon(Icons.remove)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(valor,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navy)),
            ),
            IconButton.outlined(onPressed: onMas, icon: const Icon(Icons.add)),
          ],
        ),
        Text(ayuda, style: const TextStyle(fontSize: 11, color: _gris)),
      ],
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
