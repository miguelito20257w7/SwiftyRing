import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-05 — Gestión de docentes (RF-32, RF-33). Solo administrador.
/// Frame de Figma `1:2` "Gestión de Docentes (Yellow)".
class DocentesPage extends ConsumerStatefulWidget {
  const DocentesPage({super.key});

  @override
  ConsumerState<DocentesPage> createState() => _DocentesPageState();
}

class _DocentesPageState extends ConsumerState<DocentesPage> {
  String _busqueda = '';

  Future<void> _abrirFormulario([Docente? docente]) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.fondo,
      builder: (context) => _FormDocente(docente: docente),
    );
    if (guardado == true) {
      ref.invalidate(docentesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docentes = ref.watch(docentesProvider);
    final nombreAdmin =
        ref.watch(authProvider).session?.nombre.split(' ').first ?? 'Admin';

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.docentes,
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(docentesProvider.future),
        child: CuerpoTimbre(
          children: [
            Text('Buenos días, $nombreAdmin', style: TimbreTextos.titulo),
            Text(
              'Gestión de docentes y horarios escolares',
              style: AppTextStyles.cuerpo,
            ),
            const SizedBox(height: 24),
            // Buscador (frame 1:2).
            TextField(
              onChanged: (texto) => setState(() => _busqueda = texto),
              style: GoogleFonts.workSans(
                fontSize: 16,
                color: AppColors.textoApoyo,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar docente...',
                hintStyle: GoogleFonts.workSans(
                  fontSize: 16,
                  color: AppColors.chipTexto,
                ),
                prefixIcon: const Icon(Icons.search, color: AppColors.chipTexto),
                filled: true,
                fillColor: AppColors.blanco,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.chipFondo),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.dorado, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Docentes',
                    style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 22),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _abrirFormulario(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('AGREGAR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Acceso a la asignación horaria por salón (F-06): desde aquí
            // porque el horario académico es la otra mitad de esta gestión.
            Material(
              color: TimbreColors.amarillo.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(RutasTimbre.asignacion),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart_outlined,
                          color: AppColors.dorado),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Asignación horaria por salón',
                          style: AppTextStyles.enlace,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.dorado),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            switch (docentes) {
              AsyncData(:final value) => _ListaDocentes(
                docentes: value
                    .where(
                      (d) => d.nombre.toLowerCase().contains(
                        _busqueda.toLowerCase().trim(),
                      ),
                    )
                    .toList(),
                hayBusqueda: _busqueda.trim().isNotEmpty,
                alTocar: _abrirFormulario,
              ),
              AsyncError(:final error) => AvisoErrorCarga(
                error: error,
                alReintentar: () => ref.invalidate(docentesProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _ListaDocentes extends StatelessWidget {
  final List<Docente> docentes;
  final bool hayBusqueda;
  final ValueChanged<Docente> alTocar;

  const _ListaDocentes({
    required this.docentes,
    required this.hayBusqueda,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    if (docentes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          hayBusqueda
              ? 'Ningún docente coincide con la búsqueda.'
              : 'Aún no hay docentes. Agrega el primero con AGREGAR.',
          style: AppTextStyles.cuerpo,
        ),
      );
    }

    return Column(
      children: [
        for (final docente in docentes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TarjetaDocente(
              docente: docente,
              alTocar: () => alTocar(docente),
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de docente (frame 1:2): avatar con aro dorado, nombre y
/// "MATERIA · GRUPO".
class _TarjetaDocente extends StatelessWidget {
  final Docente docente;
  final VoidCallback alTocar;

  const _TarjetaDocente({required this.docente, required this.alTocar});

  String get _iniciales {
    final partes = docente.nombre.trim().split(RegExp(r'\s+'));
    final primera = partes.isNotEmpty && partes.first.isNotEmpty
        ? partes.first[0]
        : '?';
    final segunda = partes.length > 1 && partes[1].isNotEmpty ? partes[1][0] : '';
    return '$primera$segunda'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final materias = docente.materias.map((m) => m.nombre).join(', ');
    final detalle = [
      if (materias.isNotEmpty) materias.toUpperCase(),
      if (docente.directorDeGrupo != null) docente.directorDeGrupo!,
    ].join(' · ');

    return Material(
      color: AppColors.blanco,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: alTocar,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.chipFondo),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TimbreColors.amarillo.withValues(alpha: 0.4),
                  border: Border.all(color: TimbreColors.amarillo, width: 2),
                ),
                child: Center(
                  child: Text(
                    _iniciales,
                    style: GoogleFonts.workSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dorado,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docente.nombre,
                      style: TimbreTextos.etiquetaTarjeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detalle.isNotEmpty)
                      Text(
                        detalle,
                        style: TimbreTextos.dias,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.chipTexto),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alta y edición de docente (F-05): nombre, correo, contraseña (solo al
/// crear), jornada, dirección de grupo y materias del catálogo.
class _FormDocente extends ConsumerStatefulWidget {
  final Docente? docente;

  const _FormDocente({this.docente});

  @override
  ConsumerState<_FormDocente> createState() => _FormDocenteState();
}

class _FormDocenteState extends ConsumerState<_FormDocente> {
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
