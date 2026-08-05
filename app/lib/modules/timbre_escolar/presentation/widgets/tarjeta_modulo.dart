import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';

/// "MÓDULO PRINCIPAL" (frame 1:214): el estado del ESP32.
///
/// Recibe los datos en vez de leerlos de un provider porque llegan de dos
/// sitios distintos según quién mire: el administrador los saca de la
/// configuración completa y el profesor del resumen, que es lo único que su
/// rol puede pedir.
class TarjetaModulo extends StatelessWidget {
  /// ¿El módulo se reportó al servidor hace segundos? Es el latido real de sus
  /// consultas de comandos.
  final bool enLinea;

  /// Última vez que el módulo descargó el horario completo (RF-30).
  final DateTime? ultimaSync;

  const TarjetaModulo({
    super.key,
    required this.enLinea,
    required this.ultimaSync,
  });

  static String _fechaCorta(DateTime momento) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(momento.day)}/${dos(momento.month)} '
        '${dos(momento.hour)}:${dos(momento.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final offline = !enLinea;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chipFondo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MÓDULO PRINCIPAL', style: TimbreTextos.rotulo),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: offline
                      ? TimbreColors.grisChip
                      : const Color(0xFFCDEFE8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  offline ? '● OFFLINE' : '● ONLINE',
                  style: GoogleFonts.workSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: offline
                        ? AppColors.textoApoyo
                        : const Color(0xFF00796B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Módulo ESP32-WROOM',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: TimbreColors.tinta,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ultimaSync == null
                ? 'El timbre físico opera de forma autónoma con el horario '
                      'sincronizado, aun sin internet (RF-31). Todavía no ha '
                      'sincronizado su primer horario.'
                : 'Opera de forma autónoma aun sin internet (RF-31). Último '
                      'horario sincronizado: ${_fechaCorta(ultimaSync!)}.',
            style: GoogleFonts.workSans(
              fontSize: 13,
              color: AppColors.textoApoyo,
            ),
          ),
        ],
      ),
    );
  }
}
