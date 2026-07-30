import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';

/// Pantalla de entrada del módulo Sistema de Timbre Escolar.
///
/// Se llega desde el lanzador, así que lleva `AppBar` con retroceso: dentro de
/// un módulo la salida natural es volver a la lista de aplicaciones, no cerrar
/// la sesión. El cierre de sesión vive en el lanzador, porque la sesión es de
/// toda la aplicación institucional y no de un módulo.
///
/// Andamiaje: muestra qué podrá hacer cada rol. Las funciones reales
/// (horarios, timbre manual, sismos, notificaciones) se construyen encima.
class TimbreInicioPage extends ConsumerWidget {
  const TimbreInicioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;

    // El router garantiza que no se llega aquí sin sesión; el guardia es por si
    // alguien navega a esta ruta directamente durante el desarrollo.
    if (sesion == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text('SwiftyRing', style: AppTextStyles.enlace),
      ),
      body: Stack(
        children: [
          const FondoDecorado(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.margenLateral,
                vertical: 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.esCompacta ? 448 : 900,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timbre Escolar', style: AppTextStyles.titulo),
                      const SizedBox(height: 4),
                      Text(
                        'Entraste como ${sesion.rol.etiqueta}',
                        style: AppTextStyles.subtitulo,
                      ),
                      const SizedBox(height: 32),
                      _RejillaDeTarjetas(
                        tarjetas: [
                          _Tarjeta(
                            icono: Icons.schedule,
                            titulo: 'Horarios',
                            descripcion:
                                'Timbres del horario habitual y horarios especiales.',
                            habilitado: sesion.rol.puedeAdministrar,
                            motivoDeshabilitado:
                                'Solo el administrador gestiona horarios.',
                          ),
                          _Tarjeta(
                            icono: Icons.notifications_active_outlined,
                            titulo: 'Timbre manual',
                            descripcion: 'Accionar el timbre fuera de horario.',
                            habilitado: sesion.rol.puedeAccionarTimbre,
                            motivoDeshabilitado:
                                'Solo administrador y operador accionan el timbre.',
                          ),
                          _Tarjeta(
                            icono: Icons.calendar_month_outlined,
                            titulo: 'Mi horario',
                            descripcion: 'Clase en curso y próxima clase.',
                            habilitado: sesion.rol == RolUsuario.profesor,
                            motivoDeshabilitado: 'Disponible para profesores.',
                          ),
                        ],
                      ),
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

/// Coloca las tarjetas en una columna o en filas de dos, según el ancho.
///
/// Se usa `Wrap` y no `GridView` a propósito: la altura de cada tarjeta depende
/// de su texto, y una rejilla con `childAspectRatio` fijo obligaría a recortar
/// o a dejar huecos cuando un motivo de bloqueo ocupa dos líneas.
class _RejillaDeTarjetas extends StatelessWidget {
  final List<Widget> tarjetas;

  const _RejillaDeTarjetas({required this.tarjetas});

  @override
  Widget build(BuildContext context) {
    if (context.esCompacta) {
      return Column(children: tarjetas);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const separacion = 12.0;
        final anchoTarjeta = (constraints.maxWidth - separacion) / 2;

        return Wrap(
          spacing: separacion,
          children: [
            for (final tarjeta in tarjetas)
              SizedBox(width: anchoTarjeta, child: tarjeta),
          ],
        );
      },
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final bool habilitado;
  final String motivoDeshabilitado;

  const _Tarjeta({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.habilitado,
    required this.motivoDeshabilitado,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: habilitado ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.blanco,
          borderRadius: BorderRadius.circular(AppSizes.botonRadio),
          border: Border.all(color: AppColors.chipFondo),
        ),
        child: Row(
          children: [
            Icon(icono, color: AppColors.dorado),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: AppTextStyles.cuerpo.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.dorado,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    habilitado ? descripcion : motivoDeshabilitado,
                    style: AppTextStyles.chip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
