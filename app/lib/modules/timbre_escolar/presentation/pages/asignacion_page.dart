import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// Una opción de los desplegables: el id que viaja al servidor y el nombre que
/// se lee en pantalla.
typedef _Opcion = ({String id, String nombre});

/// Un bloque en edición, antes de guardarlo en el servidor.
class _BloqueBorrador {
  String horaInicio;
  String horaFin;
  String materiaId;

  /// El **docente** cuando se arma el horario de un salón, y el **salón**
  /// cuando se arma el de un docente.
  ///
  /// Un bloque de clase siempre tiene los dos; lo que cambia entre los dos
  /// modos es cuál queda fijo por el encabezado y cuál se elige bloque a
  /// bloque. Por eso el borrador es uno solo y no dos casi iguales.
  String terceroId;

  _BloqueBorrador({
    required this.horaInicio,
    required this.horaFin,
    required this.materiaId,
    required this.terceroId,
  });
}

/// F-06 — Asignación horaria (RF-34, RF-35). Solo administrador.
/// Frame de Figma `1:392` "Asignación Horaria (Yellow)".
///
/// El horario es una sola tabla —bloques colgando de un salón y un día— que se
/// puede armar desde dos lados, y la pantalla ofrece los dos:
///
///   * **Por salón**: se fija el salón y cada bloque elige su docente. Es cómo
///     lo define F-06 y cómo se llena un horario desde cero, salón por salón.
///   * **Por docente**: se fija el docente y cada bloque elige su salón. Es lo
///     que sirve cuando llega un profesor nuevo o hay que recomponerle la
///     semana a uno: su jornada está repartida entre varios salones y por el
///     otro modo habría que entrar a cada uno a buscarlo.
class AsignacionPage extends ConsumerStatefulWidget {
  const AsignacionPage({super.key});

  @override
  ConsumerState<AsignacionPage> createState() => _AsignacionPageState();
}

class _AsignacionPageState extends ConsumerState<AsignacionPage> {
  bool _porDocente = false;

  @override
  Widget build(BuildContext context) {
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
                Center(
                  child: SelectorPildora(
                    izquierda: 'POR SALÓN',
                    derecha: 'POR DOCENTE',
                    derechaActiva: _porDocente,
                    holgura: 18,
                    alCambiar: (valor) => setState(() => _porDocente = valor),
                  ),
                ),
                const SizedBox(height: 20),
                // Cambiar de modo descarta el borrador a propósito: son dos
                // recortes distintos del horario y arrastrar bloques de uno al
                // otro no querría decir nada.
                if (_porDocente)
                  const _AsignarPorDocente()
                else
                  const _AsignarPorSalon(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo por salón (F-06)
// ---------------------------------------------------------------------------

class _AsignarPorSalon extends ConsumerStatefulWidget {
  const _AsignarPorSalon();

  @override
  ConsumerState<_AsignarPorSalon> createState() => _AsignarPorSalonState();
}

class _AsignarPorSalonState extends ConsumerState<_AsignarPorSalon> {
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
              terceroId: b.profesorId,
            ),
        ];
      });
    } on TimbreApiException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
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
      if (mounted) _avisar(context, e.mensaje);
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
              profesorId: b.terceroId,
            ),
        ],
      );
      // Cambió el horario de varios docentes: las pantallas que lo muestran no
      // deben quedarse con la versión vieja.
      _invalidarHorarios(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horario de ${salon.nombre} · ${_dia.etiqueta} guardado.',
          ),
        ),
      );
    } on TimbreApiException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salones = ref.watch(salonesProvider);
    final docentes = ref.watch(docentesProvider).value ?? const <Docente>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RotuloSeccion(
          icono: Icons.meeting_room_outlined,
          texto: 'Salón',
        ),
        const SizedBox(height: 8),
        switch (salones) {
          AsyncData(:final value) => Row(
            children: [
              Expanded(
                child: _Desplegable(
                  valor: _salon?.id,
                  pista: 'Selecciona un salón',
                  opciones: [
                    for (final salon in value) (id: salon.id, nombre: salon.nombre),
                  ],
                  alCambiar: (id) {
                    setState(
                      () => _salon = value.where((s) => s.id == id).firstOrNull,
                    );
                    _cargarHorario();
                  },
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
        _SelectorDia(
          dia: _dia,
          alCambiar: (dia) {
            setState(() => _dia = dia);
            _cargarHorario();
          },
        ),
        const SizedBox(height: 24),
        if (_salon == null)
          const _Vacio(
            icono: Icons.table_chart_outlined,
            mensaje:
                'Elige un salón y un día para armar su horario de clases. Ese '
                'horario alimenta las notificaciones de próxima clase a los '
                'docentes.',
          )
        else
          _EditorBloques(
            titulo: '${_salon!.nombre} · ${_dia.etiqueta}',
            etiquetaTercero: 'Docente',
            opciones: [
              for (final docente in docentes)
                (id: docente.id, nombre: docente.nombre),
            ],
            faltanOpciones:
                'Antes de armar horarios crea materias y docentes en Gestión '
                'de Docentes.',
            bloques: _bloques,
            enviando: _enviando,
            alCambiar: () => setState(() {}),
            alQuitar: (indice) => setState(() => _bloques?.removeAt(indice)),
            alGuardar: _guardar,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Modo por docente
// ---------------------------------------------------------------------------

class _AsignarPorDocente extends ConsumerStatefulWidget {
  const _AsignarPorDocente();

  @override
  ConsumerState<_AsignarPorDocente> createState() => _AsignarPorDocenteState();
}

class _AsignarPorDocenteState extends ConsumerState<_AsignarPorDocente> {
  Docente? _docente;
  DiaSemana _dia = DiaSemana.lunes;
  List<_BloqueBorrador>? _bloques;
  bool _enviando = false;

  Future<void> _cargarHorario() async {
    final docente = _docente;
    if (docente == null) return;
    setState(() => _bloques = null);
    try {
      final horario = await ref
          .read(timbreApiProvider)
          .horarioDeProfesorEnDia(docente.id, _dia);
      if (!mounted) return;
      setState(() {
        _bloques = [
          for (final b in horario.bloques)
            _BloqueBorrador(
              horaInicio: b.horaInicio,
              horaFin: b.horaFin,
              materiaId: b.materiaId,
              terceroId: b.salonId,
            ),
        ];
      });
    } on TimbreApiException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    }
  }

  Future<void> _guardar() async {
    final docente = _docente;
    final bloques = _bloques;
    if (docente == null || bloques == null) return;

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).guardarHorarioDeProfesor(
        docente.id,
        _dia,
        [
          for (final b in bloques)
            (
              horaInicio: b.horaInicio,
              horaFin: b.horaFin,
              materiaId: b.materiaId,
              salonId: b.terceroId,
            ),
        ],
      );
      _invalidarHorarios(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horario de ${docente.nombre} · ${_dia.etiqueta} guardado.',
          ),
        ),
      );
      // El servidor renumera los bloques de cada salón afectado; se relee para
      // no dejar en pantalla un borrador que ya no es lo que hay guardado.
      await _cargarHorario();
    } on TimbreApiException catch (e) {
      if (mounted) _avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docentes = ref.watch(docentesProvider);
    final salones = ref.watch(salonesProvider).value ?? const <Salon>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RotuloSeccion(icono: Icons.person_outline, texto: 'Docente'),
        const SizedBox(height: 8),
        switch (docentes) {
          AsyncData(:final value) when value.isEmpty => Text(
            'Todavía no hay docentes. Se crean en Gestión de Docentes, con su '
            'correo y sus materias.',
            style: AppTextStyles.cuerpo,
          ),
          AsyncData(:final value) => _Desplegable(
            valor: _docente?.id,
            pista: 'Selecciona un docente',
            opciones: [
              for (final docente in value)
                (id: docente.id, nombre: docente.nombre),
            ],
            alCambiar: (id) {
              setState(
                () => _docente = value.where((d) => d.id == id).firstOrNull,
              );
              _cargarHorario();
            },
          ),
          AsyncError(:final error) => AvisoErrorCarga(
            error: error,
            alReintentar: () => ref.invalidate(docentesProvider),
          ),
          _ => const LinearProgressIndicator(),
        },
        const SizedBox(height: 20),
        _SelectorDia(
          dia: _dia,
          alCambiar: (dia) {
            setState(() => _dia = dia);
            _cargarHorario();
          },
        ),
        const SizedBox(height: 24),
        if (_docente == null)
          const _Vacio(
            icono: Icons.person_search_outlined,
            mensaje:
                'Elige un docente y un día para armar su jornada. Cada bloque '
                'lleva su salón, así que su horario puede repartirse entre '
                'varios sin salir de aquí.',
          )
        else
          _EditorBloques(
            titulo: '${_docente!.nombre} · ${_dia.etiqueta}',
            etiquetaTercero: 'Salón',
            opciones: [
              for (final salon in salones) (id: salon.id, nombre: salon.nombre),
            ],
            faltanOpciones:
                'Antes de armar la jornada de un docente crea materias y '
                'salones.',
            bloques: _bloques,
            enviando: _enviando,
            alCambiar: () => setState(() {}),
            alQuitar: (indice) => setState(() => _bloques?.removeAt(indice)),
            alGuardar: _guardar,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas por los dos modos
// ---------------------------------------------------------------------------

void _avisar(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
  );
}

/// Guardar por cualquiera de los dos modos cambia el horario que ven la vista
/// del profesor y el detalle de docente. Se sueltan las copias en memoria para
/// que la próxima pantalla que las pida las traiga del servidor.
void _invalidarHorarios(WidgetRef ref) {
  ref.invalidate(horarioSalonProvider);
  ref.invalidate(horarioProfesorProvider);
  ref.invalidate(miHorarioProvider);
}

class _Desplegable extends StatelessWidget {
  final String? valor;
  final String pista;
  final List<_Opcion> opciones;
  final ValueChanged<String?> alCambiar;

  const _Desplegable({
    required this.valor,
    required this.pista,
    required this.opciones,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: valor,
      hint: Text(pista),
      items: [
        for (final opcion in opciones)
          DropdownMenuItem(value: opcion.id, child: Text(opcion.nombre)),
      ],
      onChanged: alCambiar,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.blanco,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _SelectorDia extends StatelessWidget {
  final DiaSemana dia;
  final ValueChanged<DiaSemana> alCambiar;

  const _SelectorDia({required this.dia, required this.alCambiar});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RotuloSeccion(
          icono: Icons.calendar_today_outlined,
          texto: 'Día de la semana',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final opcion in DiaSemana.values)
              ChoiceChip(
                label: Text(opcion.inicial),
                tooltip: opcion.etiqueta,
                selected: dia == opcion,
                selectedColor: AppColors.dorado,
                labelStyle: TextStyle(
                  color: dia == opcion
                      ? AppColors.blanco
                      : AppColors.textoApoyo,
                ),
                onSelected: (_) => alCambiar(opcion),
              ),
          ],
        ),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;

  const _Vacio({required this.icono, required this.mensaje});

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
          Text(mensaje, textAlign: TextAlign.center, style: AppTextStyles.cuerpo),
        ],
      ),
    );
  }
}

/// "Distribución Semanal" del prototipo, reducida a un día: la lista ordenada
/// de bloques con sus celdas amarillas, el AGREGAR punteado y guardar.
///
/// Sirve a los dos modos. Lo único que cambia es el tercer dato de cada
/// bloque: el docente cuando se arma un salón, el salón cuando se arma un
/// docente.
class _EditorBloques extends ConsumerWidget {
  final String titulo;
  final String etiquetaTercero;
  final List<_Opcion> opciones;

  /// Qué decir si aún no hay materias o no hay opciones para el tercer dato.
  final String faltanOpciones;

  final List<_BloqueBorrador>? bloques;
  final bool enviando;
  final VoidCallback alCambiar;
  final ValueChanged<int> alQuitar;
  final VoidCallback alGuardar;

  const _EditorBloques({
    required this.titulo,
    required this.etiquetaTercero,
    required this.opciones,
    required this.faltanOpciones,
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
    if (!context.mounted) return;

    if (materias.isEmpty || opciones.isEmpty) {
      _avisar(context, faltanOpciones);
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
        etiquetaTercero: etiquetaTercero,
        opciones: opciones,
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
    String nombreMateria(String id) =>
        materias.where((m) => m.id == id).firstOrNull?.nombre ?? '—';
    String nombreTercero(String id) =>
        opciones.where((o) => o.id == id).firstOrNull?.nombre ?? '—';

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
                  titulo,
                  style: TimbreTextos.etiquetaTarjeta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
                                nombreTercero(bloque.terceroId),
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

/// Captura de un bloque: horas, materia y el dato que cambia según el modo.
class _HojaBloque extends StatefulWidget {
  final _BloqueBorrador? original;
  final List<Materia> materias;
  final String etiquetaTercero;
  final List<_Opcion> opciones;
  final String horaSugerida;

  const _HojaBloque({
    required this.original,
    required this.materias,
    required this.etiquetaTercero,
    required this.opciones,
    required this.horaSugerida,
  });

  @override
  State<_HojaBloque> createState() => _HojaBloqueState();
}

class _HojaBloqueState extends State<_HojaBloque> {
  late TimeOfDay _inicio;
  late TimeOfDay _fin;
  String? _materiaId;
  String? _terceroId;

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
    // Un bloque puede venir con un salón o un docente que ya no está en la
    // lista (se suspendió, se borró); en ese caso el desplegable arranca vacío
    // en vez de reventar al no encontrar el valor.
    final tercero = original?.terceroId;
    _terceroId = widget.opciones.any((o) => o.id == tercero)
        ? tercero
        : widget.opciones.first.id;
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
            initialValue: _terceroId,
            items: [
              for (final opcion in widget.opciones)
                DropdownMenuItem(value: opcion.id, child: Text(opcion.nombre)),
            ],
            onChanged: (id) => setState(() => _terceroId = id),
            decoration: InputDecoration(labelText: widget.etiquetaTercero),
          ),
          const SizedBox(height: 24),
          BotonGuardar(
            texto: 'Listo',
            icono: Icons.check,
            onPressed: () {
              final inicio = _aTexto(_inicio);
              final fin = _aTexto(_fin);
              if (inicio.compareTo(fin) >= 0) {
                _avisar(
                  context,
                  'El bloque debe terminar después de empezar.',
                );
                return;
              }
              Navigator.of(context).pop(
                _BloqueBorrador(
                  horaInicio: inicio,
                  horaFin: fin,
                  materiaId: _materiaId!,
                  terceroId: _terceroId!,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
