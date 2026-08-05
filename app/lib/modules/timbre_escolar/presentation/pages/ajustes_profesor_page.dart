import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/dispositivos_vinculados.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/tarjeta_modulo.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// Ajustes del rol profesor (F-09), la contraparte de solo lectura de
/// [AjustesPage].
///
/// Es una pantalla para **consultar**, no para configurar: quién eres, de qué
/// colegio, cómo está el módulo y qué teléfonos reciben tus avisos. Lo único
/// accionable son los dispositivos, porque desvincular el propio teléfono es
/// del dueño y no del administrador.
///
/// No comparte página con [AjustesPage] escondiéndole secciones: esa pantalla
/// pide `/configuracion`, que responde 403 a este rol, y la mitad de sus
/// tarjetas quedarían en un error de carga.
class AjustesProfesorPage extends ConsumerWidget {
  const AjustesProfesorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenSistemaProvider);

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.misAjustes,
      child: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(dispositivosProvider);
          return ref.refresh(resumenSistemaProvider.future);
        },
        child: CuerpoTimbre(
          children: [
            Text('Ajustes', style: TimbreTextos.titulo),
            Text('Tu cuenta, el módulo y tus dispositivos',
                style: AppTextStyles.cuerpo),
            const SizedBox(height: 24),
            const _TarjetaPerfil(),
            const SizedBox(height: 16),
            // El colegio y el módulo llegan juntos del mismo resumen, así que
            // comparten estado de carga y un solo reintento.
            switch (resumen) {
              AsyncData(:final value) => Column(
                children: [
                  _TarjetaColegio(nombreColegio: value.nombreColegio),
                  const SizedBox(height: 16),
                  TarjetaModulo(
                    enLinea: value.moduloEnLinea,
                    ultimaSync: value.ultimaSync,
                  ),
                ],
              ),
              AsyncError(:final error) => AvisoErrorCarga(
                error: error,
                alReintentar: () => ref.invalidate(resumenSistemaProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            const SizedBox(height: 24),
            const DispositivosVinculados(),
          ],
        ),
      ),
    );
  }
}

/// Quién eres: el nombre con que te ve el sistema, tu correo y tu rol.
class _TarjetaPerfil extends ConsumerWidget {
  const _TarjetaPerfil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Row(
        children: [
          AvatarDocente(nombre: sesion.nombre),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sesion.nombre,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: TimbreColors.tinta,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sesion.email,
                  style: GoogleFonts.workSans(
                    fontSize: 13,
                    color: AppColors.textoApoyo,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: TimbreColors.amarillo.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(sesion.rol.etiqueta, style: TimbreTextos.rotulo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// De qué institución es esta instalación. El administrador lo escribe en su
/// configuración; aquí solo se lee.
class _TarjetaColegio extends StatelessWidget {
  final String? nombreColegio;

  const _TarjetaColegio({required this.nombreColegio});

  @override
  Widget build(BuildContext context) {
    final sinNombre = nombreColegio == null || nombreColegio!.trim().isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_outlined, color: AppColors.dorado),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COLEGIO', style: TimbreTextos.rotulo),
                Text(
                  sinNombre ? 'Sin nombre configurado' : nombreColegio!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: sinNombre
                        ? AppColors.textoApoyo
                        : TimbreColors.tinta,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
