import 'package:flutter/material.dart';
import 'package:swiftyring/core/theme/app_theme.dart';

/// Boton dorado del prototipo (nodo 1:815): alto 64, radio 16, sombra doble,
/// texto y flecha centrados con 12 de separacion.
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;

  /// Reemplaza la flecha por un indicador de carga y bloquea el boton.
  final bool cargando;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.cargando = false,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onPressed != null && !cargando;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.botonRadio),
        boxShadow: AppShadows.boton,
      ),
      child: Material(
        color: habilitado
            ? AppColors.dorado
            : AppColors.dorado.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSizes.botonRadio),
        child: InkWell(
          onTap: habilitado ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSizes.botonRadio),
          child: SizedBox(
            height: AppSizes.botonAlto,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // `Flexible` en vez de un `Text` suelto: el botón ocupa todo el
                // ancho disponible, que en un teléfono acostado o con el texto
                // del sistema ampliado puede quedarse corto para la etiqueta.
                // Sin esto la fila se desborda y el usuario ve la advertencia
                // a rayas amarillas y negras en lugar del botón.
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      texto,
                      style: AppTextStyles.boton,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (cargando)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blanco,
                    ),
                  )
                else
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.blanco,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
