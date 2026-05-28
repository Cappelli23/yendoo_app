// lib/services/push_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'sound_service.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // ✅ Pedir permisos (Android 13+ e iOS)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ✅ Foreground (app abierta): sonido + lógica por data
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      final screen = (data['screen'] ?? '').toString();

      // Si querés que suene siempre con pedido nuevo, también podés chequear tipo:
      // final tipo = (data['tipo'] ?? '').toString();

      if (screen == 'pedidos_pendientes' || screen.isEmpty) {
        await SoundService.playPedidosPendientes();
      }
    });

    // ✅ Cuando el usuario toca la notificación
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Si después querés navegar a una pantalla:
      // final pedidoId = message.data['pedidoId'];
      // ...
    });

    // ✅ Si el token cambia (muy común), lo actualizamos en Firestore
    _fcm.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (newToken.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .set({
          'fcmToken': newToken,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  /// ✅ Llamar al loguear cadete (y también al loguear local/admin si querés)
  Future<void> registerCadeteActive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await init();

    // ✅ Obtener y guardar token
    final token = await _fcm.getToken();
    if (token != null && token.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // ✅ Topic (opcional, hoy tu function NO lo usa, pero lo dejamos)
    // En iOS también sirve, y en Android también.
    try {
      await _fcm.subscribeToTopic('cadetes_activos');
    } catch (_) {}
  }

  /// ❌ Llamar al cerrar sesión
  Future<void> unregisterCadeteActive() async {
    try {
      await _fcm.unsubscribeFromTopic('cadetes_activos');
    } catch (_) {}
  }
}
