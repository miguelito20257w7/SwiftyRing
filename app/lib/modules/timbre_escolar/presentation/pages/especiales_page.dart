import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// F-04 — Timbres especiales (RF-10..RF-13). Solo administrador.
/// Frame de Figma `1:689` "Timbres Especiales (Yellow)".
///
/// Lista los programas especiales con su estado; el selector vuelve a NORMAL
/// regresando a la pantalla principal.
class EspecialesPage extends ConsumerWidget {
  const EspecialesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final especiales = ref.watch(especialesProvider);

    return TimbreScaffold(
      titulo: 'SwiftyRing',
      rutaActual: RutasTimbre.inicio,
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(especialesProvider.future),
        child: CuerpoTimbre(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timbres', style: TimbreTextos.titulo),
                      Text(
                        'Gestión de Horarios Especiales',
                        style: AppTextStyles.cuerpo,
                      ),
                    ],
                  ),
                ),
                Material(
                  color: AppColors.dorado,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push(RutasTimbre.editarEspecial),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Tooltip(
                        message: 'Nuevo horario especial',
                        child: Icon(Icons.add, color: AppColors.blanco),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: SelectorModo(
                especialActivo: true,
                alCambiar: (especial) {
                  if (!especial) context.pop();
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('PROGRAMAS DISPONIBLES', style: TimbreTextos.rotulo),
            const SizedBox(height: 12),
            switch (especiales) {
              AsyncData(:final value) when value.isEmpty => Container(
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
                      Icons.event_outlined,
                      size: 40,
                      color: AppColors.chipTexto,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay horarios especiales. Crea uno para exámenes, '
                      'actos cívicos o jornadas recortadas.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.cuerpo,
                    ),
                  ],
                ),
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final (indice, horario) in value.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _TarjetaEspecial(horario: horario, indice: indice),
                    ),
                ],
              ),
              AsyncError(:final error) => AvisoErrorCarga(
                error: error,
                alReintentar: () => ref.invalidate(especialesProvider),
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

/// Tarjeta de programa especial (frame 1:689): icono de color, nombre, estado
/// y chevron para abrir el editor.
class _TarjetaEspecial extends StatelessWidget {
  final HorarioEspecial horario;
  final int indice;

  const _TarjetaEspecial({required this.horario, required this.indice});

  @override
  Widget build(BuildContext context) {
    // Paleta de los iconos del prototipo: rojo (emergencia), azul, amarillo.
    final tintes = [
      (const Color(0xFFFFD3D6), const Color(0xFFC0392B)),
      (const Color(0xFFCFE5F7), const Color(0xFF2980B9)),
      (TimbreColors.amarillo.withValues(alpha: 0.5), AppColors.dorado),
    ];
    final (fondoIcono, colorIcono) = tintes[indice % tintes.length];

    final estado = horario.vigente
        ? '● Activo ahora'
        : '${horario.fechaInicio} → ${horario.fechaFin}';

    return Material(
      color: AppColors.blanco,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(RutasTimbre.editarEspecial, extra: horario),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: horario.vigente
                ? const Border(
                    left: BorderSide(color: Color(0xFFC0392B), width: 4),
                  )
                : Border.all(color: AppColors.chipFondo),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: fondoIcono,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  horario.vigente ? Icons.error_outline : Icons.event_note,
                  color: colorIcono,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      horario.nombre,
                      style: TimbreTextos.etiquetaTarjeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      estado,
                      style: GoogleFonts.workSans(
                        fontSize: 14,
                        color: horario.vigente
                            ? const Color(0xFF00796B)
                            : AppColors.textoApoyo,
                      ),
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
