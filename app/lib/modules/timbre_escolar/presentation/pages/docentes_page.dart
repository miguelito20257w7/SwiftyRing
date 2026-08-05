import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/form_docente.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-05 — Gestión de docentes (RF-32, RF-33). Solo administrador.
/// Frame de Figma `1:2` "Gestión de Docentes (Yellow)".
///
/// Tocar un docente abre su **detalle** con la distribución semanal (frame
/// `1:392`), como el chevron del prototipo; el formulario de alta queda en
/// AGREGAR y la edición vive dentro del detalle.
class DocentesPage extends ConsumerStatefulWidget {
  const DocentesPage({super.key});

  @override
  ConsumerState<DocentesPage> createState() => _DocentesPageState();
}

class _DocentesPageState extends ConsumerState<DocentesPage> {
  String _busqueda = '';

  Future<void> _agregar() async {
    if (await abrirFormDocente(context)) {
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
                  onPressed: _agregar,
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
                alTocar: (docente) => context.push(
                  RutasTimbre.docenteDetalle(docente.id),
                  extra: docente,
                ),
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
              AvatarDocente(nombre: docente.nombre),
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
