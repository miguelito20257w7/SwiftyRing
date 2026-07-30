import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/core/shared_widgets/boton_principal.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';

/// F-01, primera mitad — pantalla de bienvenida.
///
/// Traducción del frame "Bienvenida y Login (Yellow)" de Figma (archivo
/// mGuugvHdapmZgoIf0dL2MG, nodo 1:800 → 1:801 "Main - Screen 1").
///
/// El prototipo solo existe en vertical. Aquí se resuelven dos disposiciones:
///
/// * **Vertical** — la del diseño: logo arriba, acciones abajo, separados.
/// * **Horizontal** — dos columnas, logo a la izquierda y acciones a la
///   derecha. Apilarlas no cabe: en un teléfono acostado quedan unos 375 px de
///   alto y solo el logo con su título ya ocupa más de la mitad.
///
/// Vive en `core/` y no en `modules/timbre_escolar/` porque es la puerta de
/// entrada de **toda la aplicación institucional**, no de un módulo.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      body: Stack(
        children: [
          const FondoDecorado(),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.margenLateral,
                vertical: context.margenVertical,
              ),
              child: context.altoCompacto
                  ? const _DisposicionHorizontal()
                  : const _DisposicionVertical(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Teléfono o tableta en vertical: la disposición del prototipo.
class _DisposicionVertical extends StatelessWidget {
  const _DisposicionVertical();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // `minHeight` hace que en pantallas altas el logo y las acciones se
        // separen como en el diseño; el scroll evita el desbordamiento en
        // pantallas cortas o con el texto del sistema muy ampliado.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: context.anchoContenido),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(height: context.espacioVertical(48)),
                    const _BloqueLogo(),
                    SizedBox(height: context.espacioVertical(64)),
                    const _BloqueAcciones(),
                    SizedBox(height: context.espacioVertical(96)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Teléfono acostado o ventana aplastada: dos columnas.
class _DisposicionHorizontal extends StatelessWidget {
  const _DisposicionHorizontal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(child: Center(child: _BloqueLogo())),
            const SizedBox(width: 32),
            Expanded(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: context.anchoContenido),
                  child: const _BloqueAcciones(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// nodos 1:805 – 1:812
class _BloqueLogo extends StatelessWidget {
  const _BloqueLogo();

  @override
  Widget build(BuildContext context) {
    final lado = context.ladoLogo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // nodo 1:808 — cuadro dorado con el icono del timbre dentro.
        Container(
          width: lado,
          height: lado,
          decoration: BoxDecoration(
            color: AppColors.dorado,
            // El radio del prototipo (35.84 sobre 128) se mantiene en
            // proporción para que la silueta no cambie al escalar.
            borderRadius: BorderRadius.circular(lado * 0.28),
            boxShadow: AppShadows.logo,
          ),
          child: Center(
            child: Image.asset(
              'assets/images/icono_timbre.jpg',
              width: lado * 0.625,
              height: lado * 0.625,
              fit: BoxFit.contain,
            ),
          ),
        ),
        SizedBox(height: context.espacioVertical(32)),
        Text(
          'BIENVENIDO',
          textAlign: TextAlign.center,
          style: AppTextStyles.titulo,
        ),
        const SizedBox(height: 8),
        Text(
          'Timbre Escolar',
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitulo,
        ),
      ],
    );
  }
}

/// nodos 1:813 – 1:829
class _BloqueAcciones extends StatelessWidget {
  const _BloqueAcciones();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BotonPrincipal(
          texto: 'Iniciar Sesión',
          onPressed: () => context.push(Rutas.login),
        ),
        SizedBox(height: context.espacioVertical(24)),
        Text(
          '¿No tienes escuela?',
          textAlign: TextAlign.center,
          style: AppTextStyles.cuerpo,
        ),
        const SizedBox(height: 2),
        Text(
          'solicita una al administrador',
          textAlign: TextAlign.center,
          style: AppTextStyles.enlace,
        ),
        SizedBox(height: context.espacioVertical(40)),
        // nodo 1:826 — chip "Ajustes de red". Lleva a elegir el servidor del
        // colegio; hay que poder llegar sin sesión, porque con la dirección
        // mal puesta el login no falla: no llega a ninguna parte.
        Material(
          color: AppColors.chipFondo,
          borderRadius: BorderRadius.circular(9999),
          child: InkWell(
            borderRadius: BorderRadius.circular(9999),
            onTap: () => context.push(Rutas.ajustesRed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.settings,
                    size: 15,
                    color: AppColors.chipTexto,
                  ),
                  const SizedBox(width: 8),
                  Text('Ajustes de red', style: AppTextStyles.chip),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
