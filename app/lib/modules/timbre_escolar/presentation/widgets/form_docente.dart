import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// Abre el formulario de docente y devuelve `true` si se guardó algo.
///
/// El envoltorio existe porque el formulario se abre desde dos pantallas
/// —la lista de Gestión de Docentes y el EDITAR del detalle (frame 1:392)— y
/// las dos necesitan el mismo bottom sheet con la misma configuración.
Future<bool> abrirFormDocente(BuildContext context, [Docente? docente]) async {
  final guardado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.fondo,
    builder: (context) => FormDocente(docente: docente),
  );
  return guardado == true;
}

/// Alta y edición de docente (F-05): nombre, correo, contraseña (solo al
/// crear), jornada, dirección de grupo y materias del catálogo.
class FormDocente extends ConsumerStatefulWidget {
  final Docente? docente;

  const FormDocente({super.key, this.docente});

  @override
  ConsumerState<FormDocente> createState() => _FormDocenteState();
}

class _FormDocenteState extends ConsumerState<FormDocente> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late final TextEditingController _grupo;
  late Jornada _jornada;
  late Set<String> _materiaIds;
  bool _enviando = false;

  bool get _editando => widget.docente != null;

  @override
  void initState() {
    super.initState();
    final docente = widget.docente;
    _nombre = TextEditingController(text: docente?.nombre ?? '');
    _email = TextEditingController(text: docente?.email ?? '');
    _grupo = TextEditingController(text: docente?.directorDeGrupo ?? '');
    _jornada = docente?.jornada ?? Jornada.manana;
    _materiaIds = docente?.materias.map((m) => m.id).toSet() ?? {};
  }

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    _grupo.dispose();
    super.dispose();
  }

  Future<void> _crearMateria() async {
    final controlador = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva materia'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej. Matemáticas'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controlador.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    try {
      final materia = await ref.read(timbreApiProvider).crearMateria(nombre);
      ref.invalidate(materiasProvider);
      setState(() => _materiaIds.add(materia.id));
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_materiaIds.isEmpty) {
      _avisar('Selecciona al menos una materia.');
      return;
    }

    setState(() => _enviando = true);
    final api = ref.read(timbreApiProvider);
    final grupo = _grupo.text.trim();
    try {
      if (_editando) {
        await api.editarDocente(
          id: widget.docente!.id,
          nombre: _nombre.text.trim(),
          jornada: _jornada,
          directorDeGrupo: grupo.isEmpty ? null : grupo,
          materiaIds: _materiaIds.toList(),
        );
      } else {
        await api.crearDocente(
          nombre: _nombre.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          jornada: _jornada,
          directorDeGrupo: grupo.isEmpty ? null : grupo,
          materiaIds: _materiaIds.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
      setState(() => _enviando = false);
    }
  }

  Future<void> _suspender() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Suspender a este docente?'),
        content: Text(
          '${widget.docente!.nombre} no podrá iniciar sesión ni aparecerá en '
          'las listas. Su horario y su historial se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      await ref.read(timbreApiProvider).suspenderDocente(widget.docente!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on TimbreApiException catch (e) {
      _avisar(e.mensaje);
      setState(() => _enviando = false);
    }
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materias = ref.watch(materiasProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editando ? 'Editar docente' : 'Agregar docente',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: TimbreColors.tinta,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (valor) =>
                    (valor ?? '').trim().isEmpty ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_editando,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  helperText: _editando
                      ? 'El correo es la credencial de acceso y no se cambia aquí'
                      : null,
                ),
                validator: (valor) {
                  final texto = (valor ?? '').trim();
                  if (texto.isEmpty) return 'Escribe el correo';
                  if (!texto.contains('@')) return 'Ese correo no parece válido';
                  return null;
                },
              ),
              if (!_editando) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña inicial',
                    helperText: 'Mínimo 8 caracteres; el docente puede cambiarla después',
                  ),
                  validator: (valor) =>
                      (valor ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _grupo,
                decoration: const InputDecoration(
                  labelText: 'Director de grupo (opcional)',
                  hintText: 'Ej. 11B',
                ),
              ),
              const SizedBox(height: 20),
              Text('JORNADA', style: TimbreTextos.rotulo),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final jornada in Jornada.values)
                    ChoiceChip(
                      label: Text(jornada.etiqueta),
                      selected: _jornada == jornada,
                      selectedColor: AppColors.dorado,
                      labelStyle: TextStyle(
                        color: _jornada == jornada
                            ? AppColors.blanco
                            : AppColors.textoApoyo,
                      ),
                      onSelected: (_) => setState(() => _jornada = jornada),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('MATERIAS QUE DICTA', style: TimbreTextos.rotulo),
                  ),
                  TextButton.icon(
                    onPressed: _crearMateria,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nueva'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              switch (materias) {
                AsyncData(:final value) when value.isEmpty => Text(
                  'No hay materias en el catálogo; crea la primera con "Nueva".',
                  style: AppTextStyles.cuerpo,
                ),
                AsyncData(:final value) => Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final materia in value)
                      FilterChip(
                        label: Text(materia.nombre),
                        selected: _materiaIds.contains(materia.id),
                        selectedColor: AppColors.dorado,
                        labelStyle: TextStyle(
                          color: _materiaIds.contains(materia.id)
                              ? AppColors.blanco
                              : AppColors.textoApoyo,
                        ),
                        onSelected: (activo) => setState(() {
                          activo
                              ? _materiaIds.add(materia.id)
                              : _materiaIds.remove(materia.id);
                        }),
                      ),
                  ],
                ),
                AsyncError(:final error) => Text(
                  '$error',
                  style: const TextStyle(color: AppColors.error),
                ),
                _ => const LinearProgressIndicator(),
              },
              const SizedBox(height: 24),
              BotonGuardar(
                texto: _editando ? 'Guardar cambios' : 'Crear docente',
                cargando: _enviando,
                onPressed: _guardar,
              ),
              if (_editando)
                Center(
                  child: TextButton(
                    onPressed: _enviando ? null : _suspender,
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Suspender cuenta'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
