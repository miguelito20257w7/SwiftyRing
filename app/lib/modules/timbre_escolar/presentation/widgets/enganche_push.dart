import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/notificaciones/servicio_push.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// Conecta el canal de push de `core/` con el dominio del timbre.
///
/// `core/` sabe encender Firebase y conseguir un token; este widget es el que
/// sabe **qué hacer con él**: registrarlo en `/api/dispositivos` para que el
/// backend pueda avisarle a este docente de su próxima clase (RF-32, RF-37), y
/// darle sentido a los mensajes que lleguen según su campo `tipo`.
///
/// Envuelve la pantalla de entrada del módulo en lugar de vivir en `main.dart`
/// porque el registro es asunto del Timbre Escolar, no de la aplicación
/// institucional: si el módulo se borra, esto se va con él.
///
/// Si el push no está disponible —Firebase sin configurar o permiso
/// denegado— no pasa nada: el widget muestra su hijo tal cual.
class EnganchePush extends ConsumerStatefulWidget {
  final Widget child;

  const EnganchePush({super.key, required this.child});

  @override
  ConsumerState<EnganchePush> createState() => _EnganchePushState();
}

class _EnganchePushState extends ConsumerState<EnganchePush> {
  StreamSubscription<String>? _suscripcionToken;
  StreamSubscription<Map<String, String>>? _suscripcionMensajes;

  @override
  void initState() {
    super.initState();
    // No se puede esperar dentro de initState; el registro arranca aquí y
    // termina cuando termine. Nada de la interfaz depende de que acabe.
    unawaited(_conectar());
  }

  @override
  void dispose() {
    _suscripcionToken?.cancel();
    _suscripcionMensajes?.cancel();
    super.dispose();
  }

  Future<void> _conectar() async {
    final push = ref.read(servicioPushProvider);

    final token = await push.iniciar();
    if (token != null) await _registrar(token);

    // FCM rota el token cada cierto tiempo y al reinstalar la app. Sin volver a
    // registrarlo, el docente dejaría de recibir avisos sin enterarse.
    _suscripcionToken = push.tokenRenovado.listen(_registrar);

    _suscripcionMensajes = push.mensajesEnPrimerPlano.listen(_alLlegarMensaje);
  }

  Future<void> _registrar(String token) async {
    final push = ref.read(servicioPushProvider);
    try {
      await ref.read(timbreApiProvider).registrarDispositivo(
        plataforma: push.plataforma,
        fcmToken: token,
      );
    } on TimbreApiException catch (e) {
      // Quedarse sin avisos no justifica interrumpir al usuario: se anota y la
      // app sigue. El próximo arranque lo reintenta.
      debugPrint('No se pudo registrar el dispositivo: ${e.mensaje}');
    }
  }

  /// Qué hacer con un mensaje que llega con la app abierta.
  ///
  /// En primer plano el sistema no muestra la notificación, así que la app la
  /// enseña. De paso refresca lo que el mensaje deja desactualizado: si sonó el
  /// timbre, el horario y el próximo toque ya no son los mismos (RF-43).
  void _alLlegarMensaje(Map<String, String> datos) {
    if (!mounted) return;

    switch (datos['tipo']) {
      case 'proxima_clase':
        ref.invalidate(miHorarioProvider);
        ref.invalidate(timbresHoyProvider);
      case 'sismo':
        ref.invalidate(sismosProvider);
        ref.invalidate(activacionesProvider);
      default:
        break;
    }

    final cuerpo = datos['cuerpo'];
    if (cuerpo == null) return;

    final esSismo = datos['tipo'] == 'sismo';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              esSismo ? Icons.warning_amber_rounded : Icons.notifications_active,
              color: AppColors.blanco,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(cuerpo)),
          ],
        ),
        backgroundColor: esSismo ? AppColors.error : AppColors.dorado,
        duration: Duration(seconds: esSismo ? 10 : 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
