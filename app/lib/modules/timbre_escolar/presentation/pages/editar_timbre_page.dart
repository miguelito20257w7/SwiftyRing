import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// F-03 — Crear o editar un timbre del horario habitual (RF-07..RF-09).
/// Frame de Figma `1:606` "Crear o Editar Timbre (Yellow)".
///
/// Con [timbre] nulo crea; con timbre, edita ese registro. Solo llega aquí el
/// administrador (la pantalla anterior esconde los accesos a otros roles y el
/// backend rechaza con 403 de todos modos).
class EditarTimbrePage extends ConsumerStatefulWidget {
  final TimbreHabitual? timbre;

  const EditarTimbrePage({super.key, this.timbre});

  @override
  ConsumerState<EditarTimbrePage> createState() => _EditarTimbrePageState();
}

class _EditarTimbrePageState extends ConsumerState<EditarTimbrePage> {
  late final TextEditingController _etiqueta;
  late TimeOfDay _hora;
  late double _duracion;
  late Set<DiaSemana> _dias;
  bool _enviando = false;

  bool get _editando => widget.timbre != null;

  @override
  void initState() {
    super.initState();
    final timbre = widget.timbre;
    _etiqueta = TextEditingController(text: timbre?.etiqueta ?? '');
    _duracion = (timbre?.duracionSeg ?? 5).toDouble();
    _dias = timbre?.dias.toSet() ??
        {
          DiaSemana.lunes,
          DiaSemana.martes,
          DiaSemana.miercoles,
          DiaSemana.jueves,
          DiaSemana.viernes,
        };
    final partes = (timbre?.hora ?? '07:00').split(':');
    _hora = TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
  }

  @override
  void dispose() {
    _etiqueta.dispose();
    super.dispose();
  }

  String get _horaTexto =>
      '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';

  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(context: context, initialTime: _hora);
    if (elegida != null) setState(() => _hora = elegida);
  }

  Future<void> _guardar() async {
    final etiqueta = _etiqueta.text.trim();
    if (etiqueta.isEmpty) {
      _avisar('Escribe el nombre del timbre.');
      return;
    }
    if (_dias.isEmpty) {
      _avisar('El timbre debe sonar al menos un día.');
      return;
    }

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).guardarTimbre(
        id: widget.timbre?.id,
        etiqueta: etiqueta,
        hora: _horaTexto,
        duracionSeg: _duracion.round(),
        activo: widget.timbre?.activo ?? true,
        dias: _dias.toList(),
      );
      ref.invalidate(timbresProvider);
      ref.invalidate(timbresHoyProvider);
      if (mounted) context.pop();
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _eliminar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este timbre?'),
        content: Text(
          '"${widget.timbre!.etiqueta}" dejará de sonar. Las activaciones ya '
          'registradas se conservan en el historial.',
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
    if (confirmado != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).eliminarTimbre(widget.timbre!.id);
      ref.invalidate(timbresProvider);
      ref.invalidate(timbresHoyProvider);
      if (mounted) context.pop();
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text(
          _editando ? 'Editar timbre' : 'Agregar timbre',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: TimbreColors.tinta,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: context.margenLateral,
          vertical: 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector de hora (nodo 1:611): la hora grande es el botón.
                Center(
                  child: Column(
                    children: [
                      Material(
                        color: TimbreColors.inputFondo,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _elegirHora,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 24,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _horaTexto,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.64,
                                    color: AppColors.dorado,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.schedule,
                                  color: AppColors.dorado,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Seleccionar hora exacta',
                        style: TimbreTextos.rotulo.copyWith(letterSpacing: 0.14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const RotuloSeccion(
                  icono: Icons.calendar_today_outlined,
                  texto: 'Días de la semana',
                ),
                const SizedBox(height: 12),
                // Chips de días (nodo 1:629). Domingo no existe: el sistema no
                // programa timbres ese día (enum dia_semana, L-S).
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final dia in DiaSemana.values)
                      _ChipDia(
                        dia: dia,
                        activo: _dias.contains(dia),
                        alTocar: () => setState(() {
                          _dias.contains(dia) ? _dias.remove(dia) : _dias.add(dia);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                const RotuloSeccion(
                  icono: Icons.label_outline,
                  texto: 'Nombre del timbre',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _etiqueta,
                  style: GoogleFonts.workSans(
                    fontSize: 18,
                    color: AppColors.textoApoyo,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ej. Inicio de clases',
                    hintStyle: GoogleFonts.workSans(
                      fontSize: 18,
                      color: AppColors.textoApoyo.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: TimbreColors.inputFondo,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 20,
                    ),
                    // El borde inferior amarillo del prototipo (nodo 1:649).
                    border: const UnderlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      borderSide: BorderSide(color: TimbreColors.amarillo),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      borderSide: BorderSide(
                        color: TimbreColors.amarillo,
                        width: 2,
                      ),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      borderSide: BorderSide(color: AppColors.dorado, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const RotuloSeccion(
                  icono: Icons.timer_outlined,
                  texto: 'Duración del timbre',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 21,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: TimbreColors.inputFondo,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: TimbreColors.bordeChip.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_none,
                        size: 20,
                        color: AppColors.textoApoyo,
                      ),
                      Expanded(
                        child: Slider(
                          value: _duracion,
                          min: 1,
                          max: 30,
                          divisions: 29,
                          activeColor: AppColors.dorado,
                          onChanged: (valor) =>
                              setState(() => _duracion = valor),
                        ),
                      ),
                      Text(
                        '${_duracion.round()}',
                        style: GoogleFonts.workSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dorado,
                        ),
                      ),
                      Text(' s', style: TimbreTextos.rotulo),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Aviso ámbar (nodo 1:668).
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: TimbreColors.amarillo.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: TimbreColors.amarillo.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 20,
                        color: TimbreColors.avisoTexto,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Este timbre se activará automáticamente según el '
                          'horario establecido. Puedes editarlo más tarde desde '
                          'la pantalla de horarios.',
                          style: GoogleFonts.workSans(
                            fontSize: 16,
                            height: 20 / 16,
                            color: TimbreColors.avisoTexto,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                BotonGuardar(
                  texto: 'Guardar cambios',
                  cargando: _enviando,
                  onPressed: _guardar,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _enviando ? null : () => context.pop(),
                    child: Text(
                      'Cancelar y volver',
                      style: TimbreTextos.rotulo.copyWith(letterSpacing: 0.14),
                    ),
                  ),
                ),
                if (_editando)
                  Center(
                    child: TextButton(
                      onPressed: _enviando ? null : _eliminar,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Eliminar timbre'),
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

/// Chip circular de día (nodo 1:630): dorado si está activo, gris si no.
class _ChipDia extends StatelessWidget {
  final DiaSemana dia;
  final bool activo;
  final VoidCallback alTocar;

  const _ChipDia({
    required this.dia,
    required this.activo,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: dia.etiqueta,
      child: Material(
        color: activo ? AppColors.dorado : TimbreColors.grisChip,
        shape: const CircleBorder(
          side: BorderSide(color: TimbreColors.bordeChip),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: alTocar,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                dia.inicial,
                style: GoogleFonts.workSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: activo ? AppColors.blanco : AppColors.textoApoyo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
