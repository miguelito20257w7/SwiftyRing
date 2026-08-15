import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/modules/proyecto_banos/data/banos_fake_data.dart';
import 'package:swiftyring/modules/proyecto_banos/domain/modelos_banos.dart';

/// Panel principal del módulo Control Baños SS (nodo "Buen día, 11-B" del
/// prototipado).
///
/// Sigue usando su propia identidad visual —Azul Marino #1E2545, RNF06— y no
/// la paleta dorada de SwiftyRing, tal como dejó indicado el equipo del
/// timbre: son marcas independientes que comparten aplicación.
class BanosInicioPage extends ConsumerWidget {
  const BanosInicioPage({super.key});

  static const _navy = Color(0xFF1E2545);
  static const _verde = Color(0xFF2D8C3E);
  static const _fondo = Color(0xFFF2F2F2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    // RF02 de su documento: el rol `operador` no tiene acceso.
    if (sesion.rol == RolUsuario.operador) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('Control Baños'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu rol de operador no tiene acceso al control de salidas al '
              'baño. Habla con coordinación si crees que es un error.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final enCurso = ref.watch(salidasEnCursoProvider);
    final todas = ref.watch(banosProvider);
    // "Actividad reciente": las últimas salidas ya completadas, más nueva
    // primero. Se limita a 5 para que el panel no crezca sin fin.
    final recientes = todas.where((s) => !s.enCurso).take(5).toList();

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Control Baños SS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Buen día, ${sesion.primerNombre}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _navy,
            ),
          ),
          const Text(
            'MONITOR DE AULA ACTIVO',
            style: TextStyle(
              color: Color(0xFF6B7189),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          _TarjetaEnCurso(salidas: enCurso, verde: _verde, navy: _navy),
          const SizedBox(height: 20),
          _BotonAutorizar(navy: _navy),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BotonSecundario(
                  texto: 'Ver historial del día',
                  navy: _navy,
                  onTap: () {
                    // Se conecta en el siguiente paso, cuando construyamos
                    // la pantalla de historial.
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BotonSecundario(
                  texto: 'Ir a reportes',
                  navy: _navy,
                  onTap: () {
                    // Se conecta cuando construyamos reportes.
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Actividad reciente',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _navy,
            ),
          ),
          const SizedBox(height: 8),
          if (recientes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no hay salidas completadas hoy.',
                style: TextStyle(color: Color(0xFF6B7189)),
              ),
            )
          else
            ...recientes.map((s) => _FilaActividad(salida: s)),
        ],
      ),
    );
  }
}

/// "Hace N min" para las salidas en curso.
String _haceMinutos(DateTime hora) {
  final minutos = DateTime.now().difference(hora).inMinutes;
  if (minutos <= 0) return 'Ahora mismo';
  return 'Hace $minutos min';
}

class _TarjetaEnCurso extends StatelessWidget {
  final List<SalidaBano> salidas;
  final Color verde;
  final Color navy;

  const _TarjetaEnCurso({
    required this.salidas,
    required this.verde,
    required this.navy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estudiantes fuera del aula',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E2545)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${salidas.length} ahora', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (salidas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nadie está fuera del aula ahora.', style: TextStyle(color: Color(0xFF6B7189))),
            )
          else
            ...salidas.map((s) => _FilaEnCurso(salida: s, verde: verde, navy: navy)),
        ],
      ),
    );
  }
}

class _FilaEnCurso extends ConsumerWidget {
  final SalidaBano salida;
  final Color verde;
  final Color navy;

  const _FilaEnCurso({required this.salida, required this.verde, required this.navy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iniciales = salida.estudianteNombre
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join()
        .toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: navy, child: Text(iniciales, style: const TextStyle(color: Colors.white, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(salida.estudianteNombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_haceMinutos(salida.horaSalida), style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.white),
            onPressed: () => ref.read(banosProvider.notifier).registrarRegreso(salida.id),
            child: const Text('Registrar\nRegreso', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _FilaActividad extends StatelessWidget {
  final SalidaBano salida;
  const _FilaActividad({required this.salida});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: Color(0xFF2D8C3E), width: 3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: salida.estudianteNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: ' regresó'),
              ],
            ),
          ),
          Text('Duración: ${salida.duracionMinutos} minutos', style: const TextStyle(color: Color(0xFF6B7189), fontSize: 12)),
        ],
      ),
    );
  }
}

class _BotonAutorizar extends StatelessWidget {
  final Color navy;
  const _BotonAutorizar({required this.navy});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: navy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () {
          // Se conecta al formulario en el siguiente paso.
        },
        child: const Text('Autorizar nueva salida', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _BotonSecundario extends StatelessWidget {
  final String texto;
  final Color navy;
  final VoidCallback onTap;
  const _BotonSecundario({required this.texto, required this.navy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        side: BorderSide(color: navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
