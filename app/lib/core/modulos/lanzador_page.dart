import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/modulos/modulo_app.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';

/// Pantalla que aparece justo después del login: las aplicaciones de la
/// institución a las que este usuario tiene acceso.
///
/// Pertenece a `core/` porque es de la aplicación institucional, no de ningún
/// módulo. No conoce a ninguno: recibe la lista ya construida (ver [ModuloApp]).
///
/// Aquí vive el cierre de sesión, y es el sitio correcto: la sesión es de toda
/// la aplicación, no de un módulo. Cerrarla desde dentro de un módulo daría a
/// entender que existen sesiones parciales, y no existen.
class LanzadorPage extends ConsumerWidget {
  final List<ModuloApp> modulos;

  const LanzadorPage({super.key, required this.modulos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    final disponibles = modulos
        .where((modulo) => modulo.permiteA(sesion.rol))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.fondo,
      body: Stack(
        children: [
          const FondoDecorado(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.margenLateral,
                vertical: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.esCompacta ? 448 : 880,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Encabezado(
                        nombre: sesion.primerNombre,
                        rol: sesion.rol.etiqueta,
                      ),
                      const SizedBox(height: 32),
                      Text('Aplicaciones', style: AppTextStyles.enlace),
                      const SizedBox(height: 12),
                      if (disponibles.isEmpty)
                        const _SinAcceso()
                      else
                        _Rejilla(modulos: disponibles),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends ConsumerWidget {
  final String nombre;
  final String rol;

  const _Encabezado({required this.nombre, required this.rol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hola, $nombre', style: AppTextStyles.titulo),
              const SizedBox(height: 4),
              Text(rol, style: AppTextStyles.subtitulo),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: () => ref.read(authProvider.notifier).cerrarSesion(),
          icon: const Icon(Icons.logout),
          color: AppColors.dorado,
        ),
      ],
    );
  }
}

/// Una columna en pantallas estrechas, dos en el resto.
class _Rejilla extends StatelessWidget {
  final List<ModuloApp> modulos;

  const _Rejilla({required this.modulos});

  @override
  Widget build(BuildContext context) {
    if (context.esCompacta) {
      return Column(
        children: [
          for (final modulo in modulos) _TarjetaModulo(modulo: modulo),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const separacion = 16.0;
        final ancho = (constraints.maxWidth - separacion) / 2;

        return Wrap(
          spacing: separacion,
          children: [
            for (final modulo in modulos)
              SizedBox(
                width: ancho,
                child: _TarjetaModulo(modulo: modulo),
              ),
          ],
        );
      },
    );
  }
}

class _TarjetaModulo extends StatelessWidget {
  final ModuloApp modulo;

  const _TarjetaModulo({required this.modulo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: Key('modulo-${modulo.id}'),
          onTap: () => context.push(modulo.rutaInicial),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.chipFondo),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: modulo.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(modulo.icono, color: AppColors.blanco, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modulo.nombre,
                        style: AppTextStyles.cuerpo.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.dorado,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(modulo.descripcion, style: AppTextStyles.chip),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.chipTexto),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un rol sin acceso a ningún módulo. Preferible a una pantalla vacía que
/// parezca un error de carga.
class _SinAcceso extends StatelessWidget {
  const _SinAcceso();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Text(
        'Tu cuenta no tiene acceso a ninguna aplicación todavía. '
        'Habla con el administrador.',
        style: AppTextStyles.cuerpo,
      ),
    );
  }
}
