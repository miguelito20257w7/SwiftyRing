import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// El canal de notificaciones push de la aplicación institucional.
///
/// Vive en `core/` porque es infraestructura, igual que el cliente HTTP: se
/// encarga de encender Firebase, pedir el permiso al usuario y conseguir el
/// token del dispositivo. **No sabe qué significan los mensajes**; eso lo
/// decide cada módulo leyendo el campo `tipo` que manda el backend. Así, si un
/// día Control Baños necesita avisos propios, no hay que tocar este archivo
/// (RNF-12).
///
/// FCM se usa exclusivamente como canal de entrega: ni la identidad ni los
/// datos del sistema pasan por Firebase.
///
/// **La app funciona sin Firebase.** Si el proyecto todavía no está
/// configurado —o falla al arrancar— [iniciar] devuelve `null`, se registra el
/// motivo y todo lo demás sigue igual: los horarios, el timbre manual y el
/// historial no dependen de esto. Es deliberado: en un colegio con internet
/// intermitente, que la app no abra porque Google no responde sería mucho peor
/// que quedarse sin avisos.
class ServicioPush {
  FirebaseMessaging? _messaging;

  /// Mensajes que llegan con la app abierta. El sistema no los muestra solo en
  /// primer plano, así que el módulo decide qué hacer con ellos.
  ///
  /// Devuelve un stream vacío mientras Firebase no haya arrancado: tocar
  /// `FirebaseMessaging` sin inicializar lanza, y quien escucha no tiene por
  /// qué saber si el push está disponible o no.
  Stream<Map<String, String>> get mensajesEnPrimerPlano => _messaging == null
      ? const Stream.empty()
      : FirebaseMessaging.onMessage.map(_datosDe);

  /// FCM rota el token cada cierto tiempo y al reinstalar la app. Si no se
  /// vuelve a registrar, el docente deja de recibir avisos sin enterarse.
  Stream<String> get tokenRenovado =>
      _messaging?.onTokenRefresh ?? const Stream.empty();

  /// Enciende Firebase, pide permiso y devuelve el token del dispositivo, o
  /// `null` si el push no está disponible aquí.
  Future<String?> iniciar() async {
    try {
      // Sin opciones explícitas: las toma de google-services.json (Android) y
      // GoogleService-Info.plist (iOS), que genera `flutterfire configure`.
      // Si no están, esto lanza y se atrapa abajo.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;

      // En iOS el permiso es obligatorio y lo pide el sistema; en Android 13+
      // también. Si el usuario dice que no, no hay token y no hay avisos: es su
      // decisión y la app no insiste.
      final permiso = await messaging.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: el usuario no autorizó las notificaciones');
        return null;
      }

      // Sin esto, en iOS un aviso que llega con la app abierta no se ve.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      return await messaging.getToken();
    } catch (e) {
      // Firebase sin configurar es el caso normal mientras el proyecto no
      // exista; no es un error que deba interrumpir a nadie.
      debugPrint('Push no disponible (Firebase sin configurar): $e');
      return null;
    }
  }

  /// La plataforma tal como la nombra el backend (enum `plataforma`).
  ///
  /// El modelo de datos solo contempla ios, android y web. Escritorio se
  /// reporta como `web` porque es la categoría que el enum reserva para "lo
  /// demás"; la app se entrega para móvil (RNF-03) y ahí la distinción no
  /// afecta a nadie.
  String get plataforma {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }

  Map<String, String> _datosDe(RemoteMessage mensaje) => {
    ...mensaje.data.map((clave, valor) => MapEntry(clave, '$valor')),
    if (mensaje.notification?.title != null) 'titulo': mensaje.notification!.title!,
    if (mensaje.notification?.body != null) 'cuerpo': mensaje.notification!.body!,
  };
}

final servicioPushProvider = Provider<ServicioPush>((ref) => ServicioPush());
