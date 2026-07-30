import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-02 — Control de timbres, la pantalla principal del módulo.
/// Frame de Figma `1:113` "Control de Timbres (Yellow)".
///
/// Muestra la programación del día (habitual o especial, decidido por el
/// servidor), el próximo toque y el botón de timbre manual (RF-14). El selector
/// NORMAL/ESPECIAL y el lápiz de las tarjetas solo aparecen para el
/// administrador (RF-09, RF-13).
class ControlTimbresPage extends ConsumerWidget {
  const ControlTimbresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(authProvider).session?.rol;
    if (rol == null) return const SizedBox.shrink();

    final hoy = ref.watch(timbresHoyProvider);

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.inicio,
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(timbresHoyProvider.future),
        child: CuerpoTimbre(
          children: [
            _Cabecera(rol: rol),
            const SizedBox(height: 24),
            if (rol.puedeAdministrar) ...[
              Center(
                child: SelectorModo(
                  especialActivo: false,
                  alCambiar: (especial) {
                    if (especial) context.push(RutasTimbre.especiales);
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            switch (hoy) {
              AsyncData(:final value) => _ListaDelDia(hoy: value, rol: rol),
              AsyncError(:final error) => AvisoErrorCarga(
                error: error,
                alReintentar: () => ref.invalidate(timbresHoyProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            if (rol.puedeAccionarTimbre) ...[
              const SizedBox(height: 32),
              const Center(child: _BotonTimbrar()),
              const SizedBox(height: 24),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    'Toque el botón central para activar el timbre de forma inmediata',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.cuerpo,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends ConsumerWidget {
  final RolUsuario rol;

  const _Cabecera({required this.rol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = ref.watch(timbresHoyProvider).value;

    // RF-10: si rige un horario especial, la pantalla lo dice.
    final subtitulo = hoy?.fuente == 'especial'
        ? 'Horario especial: ${hoy?.nombreEspecial ?? ''}'
        : 'Programación diaria vigente';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Timbres', style: TimbreTextos.titulo),
              Text(subtitulo, style: AppTextStyles.cuerpo),
            ],
          ),
        ),
        if (rol.puedeAdministrar)
          _BotonRedondo(
            icono: Icons.add,
            tooltip: 'Agregar timbre',
            alTocar: () => context.push(RutasTimbre.editarTimbre),
          ),
      ],
    );
  }
}

/// Botón circular gris de las acciones de cabecera (nodo 1:155).
class _BotonRedondo extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback alTocar;

  const _BotonRedondo({
    required this.icono,
    required this.tooltip,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TimbreColors.grisBoton,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: alTocar,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip,
            child: Icon(icono, size: 20, color: AppColors.dorado),
          ),
        ),
      ),
    );
  }
}

class _ListaDelDia extends ConsumerWidget {
  final TimbresHoy hoy;
  final RolUsuario rol;

  const _ListaDelDia({required this.hoy, required this.rol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hoy.dia == null) {
      return _MensajeVacio(
        icono: Icons.weekend_outlined,
        texto: 'Hoy es domingo: no hay timbres programados.',
      );
    }
    if (hoy.timbres.isEmpty) {
      return _MensajeVacio(
        icono: Icons.notifications_off_outlined,
        texto: rol.puedeAdministrar
            ? 'No hay timbres para hoy. Agrega el primero con el botón +.'
            : 'No hay timbres programados para hoy.',
      );
    }

    return Column(
      children: [
        for (final (indice, timbre) in hoy.timbres.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _TarjetaTimbre(
              timbre: timbre,
              acento: TimbreColors.acentos[indice % TimbreColors.acentos.length],
              esProximo: timbre.id == hoy.proximo?.id,
              // Los toques de un horario especial se editan en su pantalla,
              // no aquí: el lápiz solo aplica al horario habitual.
              editable: rol.puedeAdministrar && hoy.fuente == 'habitual',
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de un toque del día (nodo 1:169): borde izquierdo de color, hora
/// grande, etiqueta y lápiz de edición.
class _TarjetaTimbre extends ConsumerWidget {
  final TimbreDelDia timbre;
  final Color acento;
  final bool esProximo;
  final bool editable;

  const _TarjetaTimbre({
    required this.timbre,
    required this.acento,
    required this.esProximo,
    required this.editable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: acento, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 24, 20),
      child: Row(
        children: [
          Text(timbre.hora, style: TimbreTextos.horaTarjeta),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timbre.etiqueta,
                  style: TimbreTextos.etiquetaTarjeta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  esProximo ? 'PRÓXIMO' : 'SUENA ${timbre.duracionSeg} S',
                  style: esProximo
                      ? TimbreTextos.dias.copyWith(color: TimbreColors.acentos[0])
                      : TimbreTextos.dias,
                ),
              ],
            ),
          ),
          if (editable)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppColors.textoApoyo,
              tooltip: 'Editar timbre',
              onPressed: () async {
                // La tarjeta del día no trae los días de la semana; el
                // formulario necesita el timbre completo.
                final timbres = await ref.read(timbresProvider.future);
                final completo = timbres.where((t) => t.id == timbre.id).firstOrNull;
                if (context.mounted && completo != null) {
                  context.push(RutasTimbre.editarTimbre, extra: completo);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _MensajeVacio extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _MensajeVacio({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        children: [
          Icon(icono, size: 40, color: AppColors.chipTexto),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center, style: AppTextStyles.cuerpo),
        ],
      ),
    );
  }
}

/// El botón físico de la pantalla (nodo 1:204): círculo amarillo de 208 con
/// anillo gris, campana y "TIMBRAR".
class _BotonTimbrar extends ConsumerStatefulWidget {
  const _BotonTimbrar();

  @override
  ConsumerState<_BotonTimbrar> createState() => _BotonTimbrarState();
}

class _BotonTimbrarState extends ConsumerState<_BotonTimbrar> {
  bool _enviando = false;

  Future<void> _timbrar() async {
    setState(() => _enviando = true);
    try {
      final notificados = await ref.read(timbreApiProvider).timbreManual();
      if (!mounted) return;
      // El overlay de éxito del prototipo (nodo 1:114).
      await showDialog<void>(
        context: context,
        builder: (context) => _DialogoTimbreActivo(notificados: notificados),
      );
      ref.invalidate(timbresHoyProvider);
    } on TimbreApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TimbreColors.amarillo,
      shape: CircleBorder(
        side: BorderSide(color: TimbreColors.grisChip, width: 10),
      ),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _enviando ? null : _timbrar,
        child: SizedBox(
          width: 208,
          height: 208,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_enviando)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(color: AppColors.dorado),
                )
              else
                const Icon(
                  Icons.notifications,
                  size: 56,
                  color: AppColors.dorado,
                ),
              const SizedBox(height: 8),
              Text(
                'TIMBRAR',
                style: GoogleFonts.workSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                  color: AppColors.dorado,
                ),
              ),
              Text(
                'PRESIONAR',
                style: GoogleFonts.workSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.dorado.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "¡Timbre Activo!" (nodo 1:114): confirmación de que la señal está sonando.
class _DialogoTimbreActivo extends StatelessWidget {
  final int notificados;

  const _DialogoTimbreActivo({required this.notificados});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.dorado,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active,
                size: 48,
                color: AppColors.blanco,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '¡Timbre Activo!',
              style: GoogleFonts.workSans(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.dorado,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              notificados == 0
                  ? 'La señal está sonando ahora...'
                  : 'La señal está sonando. Se notificó su próxima clase a '
                        '$notificados docente${notificados == 1 ? '' : 's'}.',
              textAlign: TextAlign.center,
              style: AppTextStyles.cuerpo,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}
