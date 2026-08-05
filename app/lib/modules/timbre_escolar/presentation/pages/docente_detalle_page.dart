import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/cuadricula_semanal.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/form_docente.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// Detalle de un docente. Solo administrador.
/// Frame de Figma `1:392` "Asignación Horaria (Yellow)".
///
/// En el prototipo esta pantalla se abre al tocar un docente en Gestión de
/// Docentes: su perfil con EDITAR y la **Distribución Semanal** que le
/// resultó de los horarios por salón (F-06). Aquí se **consulta** esa
/// distribución; se **arma** en Asignación horaria, porque el horario se
/// captura por salón y día, no por docente.
class DocenteDetallePage extends ConsumerWidget {
  final String docenteId;

  /// El docente tal como venía en la lista, para pintar el perfil sin esperar
  /// la recarga. La verdad fresca es la de [docentesProvider].
  final Docente? inicial;

  const DocenteDetallePage({super.key, required this.docenteId, this.inicial});

  Future<void> _editar(BuildContext context, WidgetRef ref, Docente docente) async {
    if (!await abrirFormDocente(context, docente)) return;

    ref.invalidate(docentesProvider);
    // Si el docente fue suspendido desde el formulario ya no está en la
    // lista: esta pantalla se queda sin sujeto y se vuelve a la gestión.
    final lista = await ref.read(docentesProvider.future);
    if (!lista.any((d) => d.id == docente.id) && context.mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La lista fresca manda; el extra de la navegación solo evita el
    // parpadeo mientras llega.
    final docente = ref
            .watch(docentesProvider)
            .value
            ?.where((d) => d.id == docenteId)
            .firstOrNull ??
        inicial;
    final colegio = ref.watch(configuracionProvider).value?.nombreColegio;

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text(
          colegio ?? 'SwiftyRing',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.dorado,
          ),
        ),
      ),
      body: docente == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                      _TarjetaPerfil(
                        docente: docente,
                        alEditar: () => _editar(context, ref, docente),
                      ),
                      const SizedBox(height: 24),
                      _DistribucionSemanal(docente: docente),
                      const SizedBox(height: 24),
                      _NotaAdministrativa(docente: docente),
                      const SizedBox(height: 16),
                      const _EstadoDeSistema(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// La tarjeta de perfil del frame 1:392: avatar, nombre, materia y EDITAR.
class _TarjetaPerfil extends StatelessWidget {
  final Docente docente;
  final VoidCallback alEditar;

  const _TarjetaPerfil({required this.docente, required this.alEditar});

  @override
  Widget build(BuildContext context) {
    final materias = docente.materias.map((m) => m.nombre).join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Row(
        children: [
          AvatarDocente(nombre: docente.nombre, lado: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docente.nombre,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dorado,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  materias.isEmpty ? 'Docente' : 'Docente de $materias',
                  style: GoogleFonts.workSans(
                    fontSize: 14,
                    color: TimbreColors.tinta,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: alEditar,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('EDITAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dorado,
                    side: const BorderSide(color: AppColors.dorado),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    textStyle: GoogleFonts.workSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Distribución Semanal": la cuadrícula días × bloques del frame 1:392,
/// armada con el horario real del docente.
class _DistribucionSemanal extends ConsumerWidget {
  final Docente docente;

  const _DistribucionSemanal({required this.docente});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horario = ref.watch(horarioProfesorProvider(docente.id));

    return Container(
      width: double.infinity,
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
                  'Distribución Semanal',
                  style: TimbreTextos.etiquetaTarjeta.copyWith(fontSize: 18),
                ),
              ),
              // El chip azul del prototipo dice "CICLO REGULAR"; aquí lleva
              // un dato real del docente: su jornada.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFCFE5F7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'JORNADA ${docente.jornada.etiqueta.toUpperCase()}',
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
          switch (horario) {
            AsyncData(:final value) => CuadriculaSemanal(
              horario: value,
              mensajeVacio:
                  'Este docente aún no tiene clases asignadas. Se asignan por '
                  'salón desde Asignación horaria.',
            ),
            AsyncError(:final error) => AvisoErrorCarga(
              error: error,
              alReintentar: () =>
                  ref.invalidate(horarioProfesorProvider(docente.id)),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: 16),
          // "AGREGAR JORNADA" punteado del prototipo: el horario se arma por
          // salón en Asignación horaria (F-06), así que el botón lleva allá.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push(RutasTimbre.asignacion),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TimbreColors.bordeChip),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline,
                      size: 18, color: AppColors.textoApoyo),
                  const SizedBox(width: 8),
                  Text('AGREGAR JORNADA', style: TimbreTextos.rotulo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Nota Administrativa" del prototipo, con los datos administrativos reales
/// del docente: jornada y dirección de grupo.
class _NotaAdministrativa extends StatelessWidget {
  final Docente docente;

  const _NotaAdministrativa({required this.docente});

  @override
  Widget build(BuildContext context) {
    final grupo = docente.directorDeGrupo;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TimbreColors.grisChip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.dorado),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nota Administrativa',
                  style: GoogleFonts.workSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TimbreColors.tinta,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  grupo == null
                      ? 'Jornada de la ${docente.jornada.etiqueta.toLowerCase()}, '
                            'sin dirección de grupo.'
                      : 'Jornada de la ${docente.jornada.etiqueta.toLowerCase()} y '
                            'director del grupo $grupo.',
                  style: GoogleFonts.workSans(
                    fontSize: 13,
                    color: AppColors.textoApoyo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Estado de Sistema" del prototipo, con el latido real del módulo físico.
class _EstadoDeSistema extends ConsumerWidget {
  const _EstadoDeSistema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enLinea =
        ref.watch(configuracionProvider).value?.moduloEnLinea ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enLinea ? const Color(0xFFE3F6EC) : TimbreColors.grisChip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enLinea ? Icons.check_circle_outline : Icons.cloud_off_outlined,
            size: 20,
            color: enLinea ? const Color(0xFF00796B) : AppColors.textoApoyo,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado de Sistema',
                  style: GoogleFonts.workSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: enLinea
                        ? const Color(0xFF00796B)
                        : TimbreColors.tinta,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enLinea
                      ? 'Sincronización de timbres activa: el módulo físico '
                            'está en línea.'
                      : 'El módulo físico está fuera de línea; opera con el '
                            'último horario sincronizado (RF-31).',
                  style: GoogleFonts.workSans(
                    fontSize: 13,
                    color: AppColors.textoApoyo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
