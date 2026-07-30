import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// Un bloque en edición, antes de guardarlo en el servidor.
class _BloqueBorrador {
  String horaInicio;
  String horaFin;
  String materiaId;
  String profesorId;

  _BloqueBorrador({
    required this.horaInicio,
    required this.horaFin,
    required this.materiaId,
    required this.profesorId,
  });
}

/// F-06 — Asignación horaria (RF-34, RF-35). Solo administrador.
/// Frame de Figma `1:392` "Asignación Horaria (Yellow)".
///
/// El formulario es por **salón y día**, como lo define F-06 y el modelo de
/// datos (`horario_salon` + `bloques`); el frame del prototipo muestra la
/// distribución resultante de un docente, que aquí corresponde a la Vista
/// Profesor. Se conserva su lenguaje visual: celdas amarillas por bloque.
class AsignacionPage extends ConsumerStatefulWidget {
  const AsignacionPage({super.key});

  @override
  ConsumerState<AsignacionPage> createState() => _AsignacionPageState();
}

class _AsignacionPageState extends ConsumerState<AsignacionPage> {
  Salon? _salon;
  DiaSemana _dia = DiaSemana.lunes;

  /// Bloques en edición. `null` mientras no se haya cargado el horario del
  /// salón/día elegido.
  List<_BloqueBorrador>? _bloques;
  bool _enviando = false;

  Future<void> _cargarHorario() async {
    final salon = _salon;
    if (salon == null) return;
    setState(() => _bloques = null);
    try {
      final horario = await ref
          .read(timbreApiProvider)
          .horarioDeSalon(salon.id, _dia);
      if (!mounted) return;
      setState(() {
        _bloques = [
          for (final b in horario.bloques)
            _BloqueBorrador(
              horaInicio: b.horaInicio,
              horaFin: b.horaFin,
              materiaId: b.materiaId,
              profesorId: b.profesorId,
            ),
        ];
      });
    } on TimbreApiException catch (e) {
      if (mounted) _avisar(e.mensaje);
    }
  }

  Future<void> _crearSalon() async {
    final controlador = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo salón'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej. Salón 201'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controlador.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    try {
      final salon = await ref.read(timbreApiProvider).crearSalon(nombre: nombre);
      ref.invalidate(salonesProvider);
      setState(() => _salon = salon);
      await _cargarHorario();
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
    }
  }

  Future<void> _guardar() async {
    final salon = _salon;
    final bloques = _bloques;
    if (salon == null || bloques == null) return;

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).guardarHorarioDeSalon(
        salon.id,
        _dia,
        [
          for (final (indice, b) in bloques.indexed)
            (
              numero: indice + 1,
              horaInicio: b.horaInicio,
              horaFin: b.horaFin,
              materiaId: b.materiaId,
              profesorId: b.profesorId,
            ),
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horario de ${salon.nombre} · ${_dia.etiqueta} guardado.',
          ),
        ),
      );
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
    } finally {
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
    final salones = ref.watch(salonesProvider);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text(
          'Asignación horaria',
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
          vertical: 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RotuloSeccion(icono: Icons.meeting_room_outlined, texto: 'Salón'),
                const SizedBox(height: 8),
                switch (salones) {
                  AsyncData(:final value) => Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _salon?.id,
                          hint: const Text('Selecciona un salón'),
                          items: [
                            for (final salon in value)
                              DropdownMenuItem(
                                value: salon.id,
                                child: Text(salon.nombre),
                              ),
                          ],
                          onChanged: (id) {
                            final salon =
                                value.where((s) => s.id == id).firstOrNull;
                            setState(() => _salon = salon);
                            _cargarHorario();
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.blanco,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _crearSalon,
                        icon: const Icon(Icons.add_circle_outline),
                        color: AppColors.dorado,
                        tooltip: 'Nuevo salón',
                      ),
                    ],
                  ),
                  AsyncError(:final error) => AvisoErrorCarga(
                    error: error,
                    alReintentar: () => ref.invalidate(salonesProvider),
                  ),
                  _ => const LinearProgressIndicator(),
                },
                const SizedBox(height: 20),
                const RotuloSeccion(
                  icono: Icons.calendar_today_outlined,
                  texto: 'Día de la semana',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final dia in DiaSemana.values)
                      ChoiceChip(
                        label: Text(dia.inicial),
                        tooltip: dia.etiqueta,
                        selected: _dia == dia,
                        selectedColor: AppColors.dorado,
                        labelStyle: TextStyle(
                          color: _dia == dia
                              ? AppColors.blanco
                              : AppColors.textoApoyo,
                        ),
                        onSelected: (_) {
                          setState(() => _dia = dia);
                          _cargarHorario();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_salon == null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.blanco,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.chipFondo),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.table_chart_outlined,
                          size: 40,
                          color: AppColors.chipTexto,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Elige un salón y un día para armar su horario de '
                          'clases. Ese horario alimenta las notificaciones de '
                          'próxima clase a los docentes.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.cuerpo,
                        ),
                      ],
                    ),
                  )
                else
                  _EditorBloques(
                    salon: _salon!,
                    dia: _dia,
                    bloques: _bloques,
                    enviando: _enviando,
                    alCambiar: () => setState(() {}),
                    alQuitar: (indice) =>
                        setState(() => _bloques?.removeAt(indice)),
                    alGuardar: _guardar,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Distribución Semanal" del prototipo, reducida a un día: la lista ordenada
/// de bloques con sus celdas amarillas, el AGREGAR JORNADA punteado y guardar.
class _EditorBloques extends ConsumerWidget {
  final Salon salon;
  final DiaSemana dia;
  final List<_BloqueBorrador>? bloques;
  final bool enviando;
  final VoidCallback alCambiar;
  final ValueChanged<int> alQuitar;
  final VoidCallback alGuardar;

  const _EditorBloques({
    required this.salon,
    required this.dia,
    required this.bloques,
    required this.enviando,
    required this.alCambiar,
    required this.alQuitar,
    required this.alGuardar,
  });

  Future<void> _editarBloque(
    BuildContext context,
    WidgetRef ref, [
    int? indice,
  ]) async {
    final materias = await ref.read(materiasProvider.future);
    final docentes = await ref.read(docentesProvider.future);
    if (!context.mounted) return;

    if (materias.isEmpty || docentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Antes de armar horarios crea materias y docentes en Gestión de Docentes.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final actual = indice == null ? null : bloques![indice];
    final resultado = await showModalBottomSheet<_BloqueBorrador>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.fondo,
      builder: (context) => _HojaBloque(
        original: actual,
        materias: materias,
        docentes: docentes,
        // El nuevo bloque arranca donde terminó el anterior.
        horaSugerida: bloques!.isEmpty ? '07:00' : bloques!.last.horaFin,
      ),
    );
    if (resultado == null) return;
    if (indice == null) {
      bloques!.add(resultado);
    } else {
      bloques![indice] = resultado;
    }
    bloques!.sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
    alCambiar();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = bloques;
    if (lista == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final materias = ref.watch(materiasProvider).value ?? const <Materia>[];
    final docentes = ref.watch(docentesProvider).value ?? const <Docente>[];
    String nombreMateria(String id) =>
        materias.where((m) => m.id == id).firstOrNull?.nombre ?? '—';
    String nombreDocente(String id) =>
        docentes.where((d) => d.id == id).firstOrNull?.nombre ?? '—';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${salon.nombre} · ${dia.etiqueta}',
                  style: TimbreTextos.etiquetaTarjeta,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFCFE5F7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${lista.length} BLOQUE${lista.length == 1 ? '' : 'S'}',
                  style: GoogleFonts.workSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: const Color(0xFF2980B9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (lista.isEmpty)
            Text(
              'Este día aún no tiene bloques de clase.',
              style: AppTextStyles.cuerpo,
            ),
          for (final (indice, bloque) in lista.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: TimbreColors.amarillo
                    .withValues(alpha: indice.isEven ? 0.55 : 0.3),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editarBloque(context, ref, indice),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BLOQUE ${indice + 1}',
                              style: GoogleFonts.workSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppColors.dorado,
                              ),
                            ),
                            Text(
                              '${bloque.horaInicio} – ${bloque.horaFin}',
                              style: GoogleFonts.workSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dorado,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombreMateria(bloque.materiaId),
                                style: TimbreTextos.etiquetaTarjeta
                                    .copyWith(fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                nombreDocente(bloque.profesorId),
                                style: GoogleFonts.workSans(
                                  fontSize: 13,
                                  color: AppColors.textoApoyo,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: AppColors.error,
                          tooltip: 'Quitar bloque',
                          onPressed: () => alQuitar(indice),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // "AGREGAR JORNADA" punteado del prototipo.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _editarBloque(context, ref),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: TimbreColors.bordeChip,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline,
                      size: 18, color: AppColors.textoApoyo),
                  const SizedBox(width: 8),
                  Text('AGREGAR BLOQUE', style: TimbreTextos.rotulo),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          BotonGuardar(
            texto: 'Guardar horario',
            cargando: enviando,
            onPressed: alGuardar,
          ),
        ],
      ),
    );
  }
}

/// Captura de un bloque: horas, materia y docente.
class _HojaBloque extends StatefulWidget {
  final _BloqueBorrador? original;
  final List<Materia> materias;
  final List<Docente> docentes;
  final String horaSugerida;

  const _HojaBloque({
    required this.original,
    required this.materias,
    required this.docentes,
    required this.horaSugerida,
  });

  @override
  State<_HojaBloque> createState() => _HojaBloqueState();
}

class _HojaBloqueState extends State<_HojaBloque> {
  late TimeOfDay _inicio;
  late TimeOfDay _fin;
  String? _materiaId;
  String? _profesorId;

  TimeOfDay _desdeTexto(String hora) {
    final partes = hora.split(':');
    return TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
  }

  String _aTexto(TimeOfDay hora) =>
      '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _inicio = _desdeTexto(original?.horaInicio ?? widget.horaSugerida);
    final finPorDefecto = _inicio.replacing(hour: (_inicio.hour + 1) % 24);
    _fin = original == null ? finPorDefecto : _desdeTexto(original.horaFin);
    _materiaId = original?.materiaId ?? widget.materias.first.id;
    _profesorId = original?.profesorId ?? widget.docentes.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            widget.original == null ? 'Agregar bloque' : 'Editar bloque',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: TimbreColors.tinta,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final elegida = await showTimePicker(
                      context: context,
                      initialTime: _inicio,
                    );
                    if (elegida != null) setState(() => _inicio = elegida);
                  },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Inicio ${_aTexto(_inicio)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final elegida = await showTimePicker(
                      context: context,
                      initialTime: _fin,
                    );
                    if (elegida != null) setState(() => _fin = elegida);
                  },
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text('Fin ${_aTexto(_fin)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _materiaId,
            items: [
              for (final materia in widget.materias)
                DropdownMenuItem(value: materia.id, child: Text(materia.nombre)),
            ],
            onChanged: (id) => setState(() => _materiaId = id),
            decoration: const InputDecoration(labelText: 'Materia'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _profesorId,
            items: [
              for (final docente in widget.docentes)
                DropdownMenuItem(value: docente.id, child: Text(docente.nombre)),
            ],
            onChanged: (id) => setState(() => _profesorId = id),
            decoration: const InputDecoration(labelText: 'Docente'),
          ),
          const SizedBox(height: 24),
          BotonGuardar(
            texto: 'Listo',
            icono: Icons.check,
            onPressed: () {
              final inicio = _aTexto(_inicio);
              final fin = _aTexto(_fin);
              if (inicio.compareTo(fin) >= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El bloque debe terminar después de empezar.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(
                _BloqueBorrador(
                  horaInicio: inicio,
                  horaFin: fin,
                  materiaId: _materiaId!,
                  profesorId: _profesorId!,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
