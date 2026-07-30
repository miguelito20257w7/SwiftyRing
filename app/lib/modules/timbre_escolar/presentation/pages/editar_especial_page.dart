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

/// Un timbre del horario especial mientras se edita, antes de guardarlo.
class _TimbreBorrador {
  String etiqueta;
  String hora;
  int duracionSeg;
  Set<DiaSemana> dias;

  _TimbreBorrador({
    required this.etiqueta,
    required this.hora,
    required this.duracionSeg,
    required this.dias,
  });
}

/// F-04 — Editor de un horario especial (RF-10..RF-13): nombre, rango de
/// vigencia con date picker (RF-11) y sus timbres. Al vencer el rango, el
/// sistema retoma solo el horario habitual (RF-12, lo decide el servidor).
class EditarEspecialPage extends ConsumerStatefulWidget {
  final HorarioEspecial? horario;

  const EditarEspecialPage({super.key, this.horario});

  @override
  ConsumerState<EditarEspecialPage> createState() => _EditarEspecialPageState();
}

class _EditarEspecialPageState extends ConsumerState<EditarEspecialPage> {
  late final TextEditingController _nombre;
  DateTimeRange? _vigencia;
  late final List<_TimbreBorrador> _timbres;
  bool _enviando = false;

  bool get _editando => widget.horario != null;

  @override
  void initState() {
    super.initState();
    final horario = widget.horario;
    _nombre = TextEditingController(text: horario?.nombre ?? '');
    if (horario != null) {
      _vigencia = DateTimeRange(
        start: DateTime.parse(horario.fechaInicio),
        end: DateTime.parse(horario.fechaFin),
      );
    }
    _timbres = [
      for (final t in horario?.timbres ?? const <TimbreEspecialItem>[])
        _TimbreBorrador(
          etiqueta: t.etiqueta,
          hora: t.hora,
          duracionSeg: t.duracionSeg,
          dias: t.dias.toSet(),
        ),
    ];
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  String _iso(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  Future<void> _elegirVigencia() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: ahora.subtract(const Duration(days: 365)),
      lastDate: ahora.add(const Duration(days: 365 * 2)),
      initialDateRange: _vigencia,
      helpText: 'Rango de vigencia del horario especial',
    );
    if (rango != null) setState(() => _vigencia = rango);
  }

  Future<void> _agregarOEditarTimbre([int? indice]) async {
    final resultado = await showModalBottomSheet<_TimbreBorrador>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.fondo,
      builder: (context) =>
          _HojaTimbreEspecial(original: indice == null ? null : _timbres[indice]),
    );
    if (resultado == null) return;
    setState(() {
      if (indice == null) {
        _timbres.add(resultado);
      } else {
        _timbres[indice] = resultado;
      }
      _timbres.sort((a, b) => a.hora.compareTo(b.hora));
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) return _avisar('Escribe el nombre del horario especial.');
    final vigencia = _vigencia;
    if (vigencia == null) return _avisar('Selecciona el rango de vigencia.');
    if (_timbres.isEmpty) return _avisar('Agrega al menos un timbre.');

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).guardarEspecial(
        id: widget.horario?.id,
        nombre: nombre,
        fechaInicio: _iso(vigencia.start),
        fechaFin: _iso(vigencia.end),
        activo: widget.horario?.activo ?? true,
        timbres: [
          for (final t in _timbres)
            (
              etiqueta: t.etiqueta,
              hora: t.hora,
              duracionSeg: t.duracionSeg,
              dias: t.dias.toList(),
            ),
        ],
      );
      ref.invalidate(especialesProvider);
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
        title: const Text('¿Eliminar este horario especial?'),
        content: Text('"${widget.horario!.nombre}" y sus timbres se borran.'),
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
      await ref.read(timbreApiProvider).eliminarEspecial(widget.horario!.id);
      ref.invalidate(especialesProvider);
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
    final vigencia = _vigencia;

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text(
          _editando ? 'Editar horario especial' : 'Nuevo horario especial',
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
                const RotuloSeccion(
                  icono: Icons.label_outline,
                  texto: 'Nombre del horario',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombre,
                  style: GoogleFonts.workSans(
                    fontSize: 18,
                    color: AppColors.textoApoyo,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ej. Semana de exámenes',
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
                  icono: Icons.date_range_outlined,
                  texto: 'Rango de vigencia',
                ),
                const SizedBox(height: 12),
                // RF-11: el date picker del rango de vigencia.
                Material(
                  color: TimbreColors.inputFondo,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _elegirVigencia,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            color: AppColors.dorado,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              vigencia == null
                                  ? 'Seleccionar fechas'
                                  : '${_iso(vigencia.start)}  →  ${_iso(vigencia.end)}',
                              style: GoogleFonts.workSans(
                                fontSize: 16,
                                fontWeight: vigencia == null
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: vigencia == null
                                    ? AppColors.textoApoyo.withValues(alpha: 0.6)
                                    : AppColors.dorado,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    const Expanded(
                      child: RotuloSeccion(
                        icono: Icons.notifications_none,
                        texto: 'Timbres del horario',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _agregarOEditarTimbre(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_timbres.isEmpty)
                  Text(
                    'Todavía no hay timbres en este horario.',
                    style: AppTextStyles.cuerpo,
                  ),
                for (final (indice, timbre) in _timbres.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: AppColors.blanco,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _agregarOEditarTimbre(indice),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.chipFondo),
                          ),
                          child: Row(
                            children: [
                              Text(
                                timbre.hora,
                                style: GoogleFonts.workSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dorado.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      timbre.etiqueta,
                                      style: TimbreTextos.etiquetaTarjeta
                                          .copyWith(fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      timbre.dias
                                          .map((d) => d.inicial)
                                          .join(' '),
                                      style: TimbreTextos.dias,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: AppColors.error,
                                tooltip: 'Quitar timbre',
                                onPressed: () =>
                                    setState(() => _timbres.removeAt(indice)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                BotonGuardar(
                  texto: 'Guardar horario',
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
                      child: const Text('Eliminar horario especial'),
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

/// Hoja para capturar un timbre del horario especial: etiqueta, hora, duración
/// y días. Devuelve el borrador o `null` si se cancela.
class _HojaTimbreEspecial extends StatefulWidget {
  final _TimbreBorrador? original;

  const _HojaTimbreEspecial({this.original});

  @override
  State<_HojaTimbreEspecial> createState() => _HojaTimbreEspecialState();
}

class _HojaTimbreEspecialState extends State<_HojaTimbreEspecial> {
  late final TextEditingController _etiqueta;
  late TimeOfDay _hora;
  late double _duracion;
  late Set<DiaSemana> _dias;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _etiqueta = TextEditingController(text: original?.etiqueta ?? '');
    _duracion = (original?.duracionSeg ?? 5).toDouble();
    _dias = original?.dias.toSet() ?? DiaSemana.values.toSet();
    final partes = (original?.hora ?? '07:00').split(':');
    _hora = TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
  }

  @override
  void dispose() {
    _etiqueta.dispose();
    super.dispose();
  }

  String get _horaTexto =>
      '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Que el teclado no tape los campos.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.original == null ? 'Agregar timbre' : 'Editar timbre',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: TimbreColors.tinta,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _etiqueta,
            decoration: const InputDecoration(
              labelText: 'Etiqueta (ej. Inicio examen)',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final elegida = await showTimePicker(
                    context: context,
                    initialTime: _hora,
                  );
                  if (elegida != null) setState(() => _hora = elegida);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_horaTexto),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _duracion,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  activeColor: AppColors.dorado,
                  label: '${_duracion.round()} s',
                  onChanged: (valor) => setState(() => _duracion = valor),
                ),
              ),
              Text('${_duracion.round()} s', style: TimbreTextos.rotulo),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final dia in DiaSemana.values)
                FilterChip(
                  label: Text(dia.inicial),
                  selected: _dias.contains(dia),
                  selectedColor: AppColors.dorado,
                  labelStyle: TextStyle(
                    color: _dias.contains(dia)
                        ? AppColors.blanco
                        : AppColors.textoApoyo,
                  ),
                  onSelected: (activo) => setState(() {
                    activo ? _dias.add(dia) : _dias.remove(dia);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          BotonGuardar(
            texto: 'Listo',
            icono: Icons.check,
            onPressed: () {
              final etiqueta = _etiqueta.text.trim();
              if (etiqueta.isEmpty || _dias.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Falta la etiqueta o los días.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(
                _TimbreBorrador(
                  etiqueta: etiqueta,
                  hora: _horaTexto,
                  duracionSeg: _duracion.round(),
                  dias: _dias,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
