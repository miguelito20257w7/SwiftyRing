import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/dispositivos_vinculados.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/tarjeta_modulo.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-07 — Configuración del sistema (RF-02, RF-03, RF-06, RF-19).
/// Frame de Figma `1:214` "Configuración (Yellow)". Solo administrador.
///
/// Tres zonas: parámetros del sistema (incluida la calibración sísmica del
/// módulo físico), cuentas de usuario y el estado del módulo ESP32. La
/// integración real con el ESP32 llega con el firmware; la tarjeta muestra el
/// estado que reporta la configuración.
class AjustesPage extends ConsumerWidget {
  const AjustesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.ajustes,
      child: CuerpoTimbre(
        children: [
          Text('Configuración', style: TimbreTextos.titulo),
          Text('Sistema, usuarios y módulo físico', style: AppTextStyles.cuerpo),
          const SizedBox(height: 24),
          const _TarjetaModuloAdmin(),
          const SizedBox(height: 16),
          const _AccesoAjustesRed(),
          const SizedBox(height: 24),
          const _SeccionSistema(),
          const SizedBox(height: 24),
          const _SeccionUsuarios(),
        ],
      ),
    );
  }
}

/// Atajo a los ajustes de red, que viven en `core/` porque la dirección del
/// servidor es de toda la aplicación institucional y no solo del timbre.
class _AccesoAjustesRed extends ConsumerWidget {
  const _AccesoAjustesRed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servidor = ref.watch(servidorProvider);

    return Material(
      color: AppColors.blanco,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(Rutas.ajustesRed),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.chipFondo),
          ),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, color: AppColors.dorado),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Servidor', style: TimbreTextos.rotulo),
                    Text(
                      servidor,
                      style: GoogleFonts.workSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TimbreColors.tinta,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (Servidor.esInseguro(servidor))
                const Icon(
                  Icons.lock_open_outlined,
                  size: 20,
                  color: Color(0xFF8A6D00),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.chipTexto),
            ],
          ),
        ),
      ),
    );
  }
}

/// El estado del ESP32, alimentado con la configuración completa que solo el
/// administrador puede pedir.
class _TarjetaModuloAdmin extends ConsumerWidget {
  const _TarjetaModuloAdmin();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configuracionProvider).value;

    return TarjetaModulo(
      // El latido real del ESP32: sus consultas de comandos al servidor.
      enLinea: config?.moduloEnLinea ?? false,
      ultimaSync: config?.ultimaSync,
    );
  }
}

/// Parámetros del sistema: nombre del colegio y calibración sísmica (RF-19).
class _SeccionSistema extends ConsumerStatefulWidget {
  const _SeccionSistema();

  @override
  ConsumerState<_SeccionSistema> createState() => _SeccionSistemaState();
}

class _SeccionSistemaState extends ConsumerState<_SeccionSistema> {
  final _nombre = TextEditingController();
  double? _umbral;
  int? _duracionMs;
  bool _enviando = false;
  bool _inicializado = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final umbral = _umbral;
    final duracion = _duracionMs;
    if (umbral == null || duracion == null) return;

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).guardarConfiguracion(
        nombreColegio: _nombre.text.trim(),
        umbralSismicoG: umbral,
        sismoDuracionMinMs: duracion,
      );
      ref.invalidate(configuracionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada.')),
        );
      }
    } on TimbreApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configuracionProvider);

    return switch (config) {
      AsyncData(:final value) => Builder(
        builder: (context) {
          if (!_inicializado) {
            _inicializado = true;
            _nombre.text = value.nombreColegio ?? '';
            _umbral = value.umbralSismicoG;
            _duracionMs = value.sismoDuracionMinMs;
          }
          final umbral = _umbral ?? value.umbralSismicoG;
          final duracion = _duracionMs ?? value.sismoDuracionMinMs;

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.blanco,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.chipFondo),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sistema',
                  style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del colegio',
                  ),
                ),
                const SizedBox(height: 20),
                // RF-19: los dos parámetros con los que el algoritmo del
                // ESP32 distingue un sismo de un camión pasando.
                Text(
                  'UMBRAL SÍSMICO · ${umbral.toStringAsFixed(1)} g',
                  style: TimbreTextos.rotulo,
                ),
                Slider(
                  value: umbral.clamp(0.1, 4.0),
                  min: 0.1,
                  max: 4.0,
                  divisions: 39,
                  activeColor: AppColors.dorado,
                  onChanged: (valor) => setState(() => _umbral = valor),
                ),
                Text(
                  'DURACIÓN MÍNIMA DEL SISMO · $duracion ms',
                  style: TimbreTextos.rotulo,
                ),
                Slider(
                  value: duracion.toDouble().clamp(100, 5000),
                  min: 100,
                  max: 5000,
                  divisions: 49,
                  activeColor: AppColors.dorado,
                  onChanged: (valor) =>
                      setState(() => _duracionMs = valor.round()),
                ),
                const SizedBox(height: 8),
                BotonGuardar(
                  texto: 'Guardar configuración',
                  cargando: _enviando,
                  onPressed: _guardar,
                ),
              ],
            ),
          );
        },
      ),
      AsyncError(:final error) => AvisoErrorCarga(
        error: error,
        alReintentar: () => ref.invalidate(configuracionProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// "Usuarios y Dispositivos" (frame 1:214): las cuentas del sistema (RF-03).
class _SeccionUsuarios extends ConsumerWidget {
  const _SeccionUsuarios();

  Future<void> _crearUsuario(BuildContext context, WidgetRef ref) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.fondo,
      builder: (context) => const _FormUsuario(),
    );
    if (guardado == true) ref.invalidate(usuariosProvider);
  }

  Future<void> _alternarActivo(
    BuildContext context,
    WidgetRef ref,
    UsuarioAdmin usuario,
  ) async {
    try {
      await ref
          .read(timbreApiProvider)
          .editarUsuario(id: usuario.id, activo: !usuario.activo);
      ref.invalidate(usuariosProvider);
    } on TimbreApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _eliminar(
    BuildContext context,
    WidgetRef ref,
    UsuarioAdmin usuario,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar a ${usuario.nombre}?'),
        content: const Text(
          'La cuenta se borra definitivamente. Para un retiro temporal usa '
          'suspender.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;
    try {
      await ref.read(timbreApiProvider).eliminarUsuario(usuario.id);
      ref.invalidate(usuariosProvider);
    } on TimbreApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarios = ref.watch(usuariosProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Usuarios y Dispositivos',
                  style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 20),
                ),
              ),
              TextButton.icon(
                onPressed: () => _crearUsuario(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('AGREGAR'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          switch (usuarios) {
            AsyncData(:final value) => Column(
              children: [
                for (final usuario in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FilaUsuario(
                      usuario: usuario,
                      alAlternar: () => _alternarActivo(context, ref, usuario),
                      alEliminar: () => _eliminar(context, ref, usuario),
                    ),
                  ),
              ],
            ),
            AsyncError(:final error) => AvisoErrorCarga(
              error: error,
              alReintentar: () => ref.invalidate(usuariosProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: 12),
          const DispositivosVinculados(),
        ],
      ),
    );
  }
}

class _FilaUsuario extends StatelessWidget {
  final UsuarioAdmin usuario;
  final VoidCallback alAlternar;
  final VoidCallback alEliminar;

  const _FilaUsuario({
    required this.usuario,
    required this.alAlternar,
    required this.alEliminar,
  });

  @override
  Widget build(BuildContext context) {
    // RF-02: la cuenta principal no expone suspender ni eliminar.
    final principal = usuario.esPrincipal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: principal
            ? const Color(0xFF2C4A6B).withValues(alpha: 0.06)
            : AppColors.fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Row(
        children: [
          Icon(
            switch (usuario.rol) {
              RolUsuario.admin => Icons.shield_outlined,
              RolUsuario.operador => Icons.support_agent_outlined,
              RolUsuario.profesor => Icons.school_outlined,
              null => Icons.person_outline,
            },
            size: 20,
            color: usuario.activo ? AppColors.dorado : AppColors.chipTexto,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        usuario.nombre,
                        style: GoogleFonts.workSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: usuario.activo
                              ? TimbreColors.tinta
                              : AppColors.chipTexto,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (principal) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TimbreColors.amarillo,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'PRINCIPAL',
                          style: GoogleFonts.workSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dorado,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${usuario.email} · ${usuario.rol?.etiqueta ?? '—'}'
                  '${usuario.activo ? '' : ' · Suspendido'}',
                  style: GoogleFonts.workSans(
                    fontSize: 12,
                    color: AppColors.textoApoyo,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!principal) ...[
            IconButton(
              onPressed: alAlternar,
              icon: Icon(
                usuario.activo
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                size: 20,
              ),
              color: AppColors.textoApoyo,
              tooltip: usuario.activo ? 'Suspender' : 'Reactivar',
            ),
            IconButton(
              onPressed: alEliminar,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.error,
              tooltip: 'Eliminar',
            ),
          ],
        ],
      ),
    );
  }
}

/// Alta de usuario secundario (RF-03): admin u operador. Los docentes se crean
/// en Gestión de Docentes, con su perfil completo.
class _FormUsuario extends ConsumerStatefulWidget {
  const _FormUsuario();

  @override
  ConsumerState<_FormUsuario> createState() => _FormUsuarioState();
}

class _FormUsuarioState extends ConsumerState<_FormUsuario> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  RolUsuario _rol = RolUsuario.operador;
  bool _enviando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).crearUsuario(
        nombre: _nombre.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        rol: _rol.name,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on TimbreApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
      );
      setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agregar usuario',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: TimbreColors.tinta,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cuentas de administración u operación. Los docentes se crean '
              'en Gestión de Docentes.',
              style: GoogleFonts.workSans(
                fontSize: 13,
                color: AppColors.textoApoyo,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
              validator: (valor) =>
                  (valor ?? '').trim().isEmpty ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo electrónico'),
              validator: (valor) {
                final texto = (valor ?? '').trim();
                if (texto.isEmpty) return 'Escribe el correo';
                if (!texto.contains('@')) return 'Ese correo no parece válido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña inicial',
                helperText: 'Mínimo 8 caracteres',
              ),
              validator: (valor) =>
                  (valor ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final rol in const [RolUsuario.operador, RolUsuario.admin])
                  ChoiceChip(
                    label: Text(rol.etiqueta),
                    selected: _rol == rol,
                    selectedColor: AppColors.dorado,
                    labelStyle: TextStyle(
                      color: _rol == rol
                          ? AppColors.blanco
                          : AppColors.textoApoyo,
                    ),
                    onSelected: (_) => setState(() => _rol = rol),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            BotonGuardar(
              texto: 'Crear usuario',
              cargando: _enviando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
