import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/notificaciones/servicio_push.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// "TUS DISPOSITIVOS VINCULADOS" (frame 1:214): los teléfonos del usuario que
/// reciben sus notificaciones push, con su "Cerrar sesión" para desvincular.
///
/// El backend responde solo los del usuario del token, así que la misma lista
/// sirve para el administrador en su configuración y para el profesor en sus
/// ajustes: cada quien ve los suyos.
class DispositivosVinculados extends ConsumerWidget {
  const DispositivosVinculados({super.key});

  /// "hace 2 h", "hace 3 días"… o `null` si nunca se ha reportado.
  static String? _haceCuanto(DateTime? momento) {
    if (momento == null) return null;
    final delta = DateTime.now().difference(momento);
    if (delta.inMinutes < 1) return 'hace un momento';
    if (delta.inHours < 1) return 'hace ${delta.inMinutes} min';
    if (delta.inDays < 1) return 'hace ${delta.inHours} h';
    return delta.inDays == 1 ? 'hace 1 día' : 'hace ${delta.inDays} días';
  }

  Future<void> _desvincular(
    BuildContext context,
    WidgetRef ref,
    DispositivoVinculado dispositivo,
    bool esEste,
  ) async {
    final nombre = dispositivo.nombreDispositivo ?? 'este dispositivo';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Cerrar sesión de $nombre?'),
        content: Text(
          esEste
              ? 'Este dispositivo dejará de recibir notificaciones. Se volverá '
                    'a vincular solo la próxima vez que abras el módulo.'
              : 'Ese dispositivo dejará de recibir notificaciones push. La '
                    'sesión que tenga abierta seguirá funcionando hasta vencer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    try {
      await ref.read(timbreApiProvider).desvincularDispositivo(dispositivo.id);
      ref.invalidate(dispositivosProvider);
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
    final dispositivos = ref.watch(dispositivosProvider);
    // El token de este teléfono, para señalarlo en la lista. Si el push no
    // está disponible (Firebase sin configurar), simplemente ninguno lleva la
    // marca.
    final tokenActual = ref.watch(servicioPushProvider).tokenActual;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TUS DISPOSITIVOS VINCULADOS', style: TimbreTextos.rotulo),
          const SizedBox(height: 8),
          switch (dispositivos) {
            AsyncData(:final value) when value.isEmpty => Text(
              'Ningún dispositivo recibe tus notificaciones todavía. Se '
              'vinculan solos al abrir el módulo en un teléfono con '
              'notificaciones activas.',
              style: GoogleFonts.workSans(
                fontSize: 13,
                color: AppColors.textoApoyo,
              ),
            ),
            AsyncData(:final value) => Column(
              children: [
                for (final (indice, dispositivo) in value.indexed) ...[
                  if (indice > 0) const Divider(height: 16),
                  _FilaDispositivo(
                    dispositivo: dispositivo,
                    esEste: dispositivo.fcmToken == tokenActual,
                    ultimoUso: _haceCuanto(dispositivo.ultimoUsoAt),
                    alCerrar: () => _desvincular(
                      context,
                      ref,
                      dispositivo,
                      dispositivo.fcmToken == tokenActual,
                    ),
                  ),
                ],
              ],
            ),
            AsyncError(:final error) => AvisoErrorCarga(
              error: error,
              alReintentar: () => ref.invalidate(dispositivosProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

class _FilaDispositivo extends StatelessWidget {
  final DispositivoVinculado dispositivo;
  final bool esEste;
  final String? ultimoUso;
  final VoidCallback alCerrar;

  const _FilaDispositivo({
    required this.dispositivo,
    required this.esEste,
    required this.ultimoUso,
    required this.alCerrar,
  });

  @override
  Widget build(BuildContext context) {
    final (icono, etiquetaPlataforma) = switch (dispositivo.plataforma) {
      'ios' => (Icons.phone_iphone, 'iPhone o iPad'),
      'android' => (Icons.phone_android, 'Teléfono Android'),
      _ => (Icons.laptop_mac_outlined, 'Navegador o escritorio'),
    };
    final nombre = dispositivo.nombreDispositivo ?? etiquetaPlataforma;

    return Row(
      children: [
        Icon(icono, size: 22, color: TimbreColors.tinta),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                esEste ? '$nombre (Este dispositivo)' : nombre,
                style: GoogleFonts.workSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TimbreColors.tinta,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (ultimoUso != null)
                Text(
                  esEste ? 'Activo ahora' : 'Visto por última vez $ultimoUso',
                  style: GoogleFonts.workSans(
                    fontSize: 12,
                    color: AppColors.textoApoyo,
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: alCerrar,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.error,
            textStyle: GoogleFonts.workSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
