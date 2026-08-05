import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/router/rutas.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// Tokens visuales propios del módulo, tomados de los frames del prototipo
/// "Control de Timbres / Crear o Editar / Timbres Especiales (Yellow)".
/// Lo compartido con el resto de la app (dorado, fondo, tipografías) sigue en
/// `core/theme/app_theme.dart`; aquí solo vive lo que nadie más usa.
abstract class TimbreColors {
  /// Bordes izquierdos de las tarjetas de timbre (nodos 1:169/1:180/1:191).
  /// Se asignan cíclicamente: su función es distinguir filas vecinas.
  static const acentos = [
    Color(0xFF27AE60),
    Color(0xFF2980B9),
    Color(0xFF8E44AD),
  ];

  /// Amarillo del botón TIMBRAR y de los acentos de formulario.
  static const amarillo = Color(0xFFFFD54F);

  /// Fondos de campos y píldoras.
  static const inputFondo = Color(0xFFF3F4F5);
  static const selectorFondo = Color(0xFFEDEEEF);
  static const navFondo = Color(0xE6E1E3E4);
  static const bordeChip = Color(0xFFD0C6AE);
  static const grisBoton = Color(0xFFE7E8E9);
  static const grisChip = Color(0xFFE1E3E4);

  /// Texto sobre el aviso ámbar del formulario.
  static const avisoTexto = Color(0xFF574500);

  /// Tinta principal de tarjetas (etiquetas de timbre).
  static const tinta = Color(0xFF191C1D);
}

abstract class TimbreTextos {
  /// Hora grande de las tarjetas — Work Sans Bold 32/40, tracking -0.64.
  static TextStyle get horaTarjeta => GoogleFonts.workSans(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.64,
    color: AppColors.dorado.withValues(alpha: 0.7),
  );

  /// Título de pantalla — Work Sans Bold 32/40.
  static TextStyle get titulo => GoogleFonts.workSans(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.64,
    color: AppColors.dorado,
  );

  /// Etiqueta de tarjeta — Work Sans Bold 18/28.
  static TextStyle get etiquetaTarjeta => GoogleFonts.workSans(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 28 / 18,
    color: TimbreColors.tinta,
  );

  /// Días "L M M J V" — Work Sans SemiBold 12/16, tracking 1.2.
  static TextStyle get dias => GoogleFonts.workSans(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 1.2,
    color: AppColors.textoApoyo,
  );

  /// Rótulo de sección de formulario — Work Sans Medium 14, tracking 0.7,
  /// mayúsculas.
  static TextStyle get rotulo => GoogleFonts.workSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    letterSpacing: 0.7,
    color: AppColors.textoApoyo,
  );
}

/// Destino del nav flotante inferior del prototipo (nodo 62:286).
class _DestinoNav {
  final String etiqueta;
  final IconData icono;
  final String ruta;

  const _DestinoNav(this.etiqueta, this.icono, this.ruta);
}

/// Cascarón de las pantallas principales del módulo: cabecera con vuelta al
/// lanzador y la barra de navegación flotante del prototipo.
///
/// La barra muestra solo lo que el rol puede usar (RF-05): el operador no ve
/// Docentes ni Ajustes; el profesor no ve barra porque su única pantalla es su
/// horario.
class TimbreScaffold extends ConsumerWidget {
  final String titulo;

  /// Ruta activa, para resaltar la píldora correspondiente.
  final String rutaActual;
  final Widget child;

  /// Acciones extra a la derecha de la cabecera.
  final List<Widget> acciones;

  const TimbreScaffold({
    super.key,
    required this.titulo,
    required this.rutaActual,
    required this.child,
    this.acciones = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(authProvider).session?.rol;

    final destinos = switch (rol) {
      RolUsuario.admin => const [
        _DestinoNav('Horarios', Icons.calendar_today_outlined, RutasTimbre.inicio),
        _DestinoNav('Docentes', Icons.groups_outlined, RutasTimbre.docentes),
        _DestinoNav('Historial', Icons.history, RutasTimbre.historial),
        _DestinoNav('Ajustes', Icons.settings_outlined, RutasTimbre.ajustes),
      ],
      RolUsuario.operador => const [
        _DestinoNav('Horarios', Icons.calendar_today_outlined, RutasTimbre.inicio),
        _DestinoNav('Historial', Icons.history, RutasTimbre.historial),
      ],
      _ => const <_DestinoNav>[],
    };

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        // Dentro del módulo la salida natural es volver al lanzador, no cerrar
        // sesión (esa vive en el lanzador).
        leading: BackButton(onPressed: () => context.go(Rutas.lanzador)),
        title: Text(titulo, style: AppTextStyles.enlace),
        actions: acciones,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: child),
          if (destinos.length > 1)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: _BarraNav(destinos: destinos, rutaActual: rutaActual),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alto que las listas deben dejar libre al final para no quedar debajo de la
/// barra flotante.
const double alturaNavFlotante = 128;

class _BarraNav extends StatelessWidget {
  final List<_DestinoNav> destinos;
  final String rutaActual;

  const _BarraNav({required this.destinos, required this.rutaActual});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: TimbreColors.navFondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 25),
            blurRadius: 50,
            spreadRadius: -12,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Cada píldora reparte el ancho disponible: con 4 destinos en un
          // teléfono angosto, los tamaños naturales no caben.
          for (final destino in destinos)
            Expanded(
              child: _PildoraNav(
                destino: destino,
                activa: destino.ruta == rutaActual,
              ),
            ),
        ],
      ),
    );
  }
}

class _PildoraNav extends StatelessWidget {
  final _DestinoNav destino;
  final bool activa;

  const _PildoraNav({required this.destino, required this.activa});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activa ? TimbreColors.amarillo : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: activa ? null : () => context.go(destino.ruta),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                destino.icono,
                size: 20,
                color: activa ? AppColors.dorado : AppColors.textoApoyo,
              ),
              const SizedBox(height: 2),
              Text(
                destino.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.workSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: activa ? AppColors.dorado : AppColors.textoApoyo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La píldora de dos opciones del prototipo (nodo 1:162): la de la derecha
/// está activa cuando [derechaActiva].
class SelectorPildora extends StatelessWidget {
  final String izquierda;
  final String derecha;
  final bool derechaActiva;
  final ValueChanged<bool> alCambiar;

  /// Aire a los lados de cada opción; se baja cuando las etiquetas son largas
  /// y el selector no cabría en un teléfono angosto.
  final double holgura;

  const SelectorPildora({
    super.key,
    required this.izquierda,
    required this.derecha,
    required this.derechaActiva,
    required this.alCambiar,
    this.holgura = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: TimbreColors.selectorFondo,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            offset: const Offset(0, 8),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OpcionModo(
            texto: izquierda,
            activa: !derechaActiva,
            holgura: holgura,
            alTocar: () => alCambiar(false),
          ),
          _OpcionModo(
            texto: derecha,
            activa: derechaActiva,
            holgura: holgura,
            alTocar: () => alCambiar(true),
          ),
        ],
      ),
    );
  }
}

/// El selector NORMAL / ESPECIAL del prototipo (nodo 1:162).
class SelectorModo extends StatelessWidget {
  final bool especialActivo;
  final ValueChanged<bool> alCambiar;

  const SelectorModo({
    super.key,
    required this.especialActivo,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return SelectorPildora(
      izquierda: 'NORMAL',
      derecha: 'ESPECIAL',
      derechaActiva: especialActivo,
      alCambiar: alCambiar,
    );
  }
}

class _OpcionModo extends StatelessWidget {
  final String texto;
  final bool activa;
  final double holgura;
  final VoidCallback alTocar;

  const _OpcionModo({
    required this.texto,
    required this.activa,
    required this.holgura,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activa ? AppColors.dorado : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: activa ? null : alTocar,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: holgura, vertical: 10),
          child: Text(
            texto,
            style: GoogleFonts.workSans(
              fontSize: 14,
              fontWeight: activa ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.14,
              color: activa ? AppColors.blanco : AppColors.textoApoyo,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rótulo de sección de formulario con icono (nodo 1:625): "DÍAS DE LA
/// SEMANA", "NOMBRE DEL TIMBRE"…
class RotuloSeccion extends StatelessWidget {
  final IconData icono;
  final String texto;

  const RotuloSeccion({super.key, required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 17, color: AppColors.textoApoyo),
        const SizedBox(width: 8),
        Text(texto.toUpperCase(), style: TimbreTextos.rotulo),
      ],
    );
  }
}

/// Botón principal de los formularios del módulo (nodo 1:673): píldora dorada
/// de 56 con icono y texto.
class BotonGuardar extends StatelessWidget {
  final String texto;
  final IconData icono;
  final bool cargando;
  final VoidCallback? onPressed;

  const BotonGuardar({
    super.key,
    required this.texto,
    this.icono = Icons.save_outlined,
    this.cargando = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onPressed != null && !cargando;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppShadows.boton,
      ),
      child: Material(
        color: habilitado
            ? AppColors.dorado
            : AppColors.dorado.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: habilitado ? onPressed : null,
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (cargando)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blanco,
                    ),
                  )
                else
                  Icon(icono, size: 20, color: AppColors.blanco),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.blanco,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuerpo estándar de las pantallas del módulo: scroll centrado con ancho
/// máximo y espacio final para la barra flotante.
class CuerpoTimbre extends StatelessWidget {
  final List<Widget> children;

  const CuerpoTimbre({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: context.margenLateral,
        right: context.margenLateral,
        top: 8,
        bottom: alturaNavFlotante,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Avatar de docente con aro dorado e iniciales (frames 1:2 y 1:392). El
/// prototipo usa fotos; el sistema no las tiene, así que las iniciales cumplen
/// el mismo papel de reconocer a la persona de un vistazo.
class AvatarDocente extends StatelessWidget {
  final String nombre;
  final double lado;

  const AvatarDocente({super.key, required this.nombre, this.lado = 48});

  String get _iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    final primera = partes.isNotEmpty && partes.first.isNotEmpty
        ? partes.first[0]
        : '?';
    final segunda = partes.length > 1 && partes[1].isNotEmpty ? partes[1][0] : '';
    return '$primera$segunda'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TimbreColors.amarillo.withValues(alpha: 0.4),
        border: Border.all(color: TimbreColors.amarillo, width: 2),
      ),
      child: Center(
        child: Text(
          _iniciales,
          style: GoogleFonts.workSans(
            // Proporcional para que funcione igual en la lista (48) y en el
            // perfil del detalle (64).
            fontSize: lado / 3,
            fontWeight: FontWeight.w700,
            color: AppColors.dorado,
          ),
        ),
      ),
    );
  }
}

/// Cómo pintar un error de carga sin tirar la pantalla entera.
class AvisoErrorCarga extends StatelessWidget {
  final Object error;
  final VoidCallback alReintentar;

  const AvisoErrorCarga({
    super.key,
    required this.error,
    required this.alReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$error',
            style: GoogleFonts.workSans(fontSize: 14, color: AppColors.error),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
