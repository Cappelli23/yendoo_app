import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ✅ Canal FIJO para pedidos pendientes
  static const String _channelId = 'pedidos_pendientes_channel';
  static const String _channelName = 'Pedidos Pendientes';
  static const String _channelDesc = 'Notificaciones de nuevos pedidos pendientes';

  /// 🔹 Inicializar servicio (llamar UNA sola vez al iniciar la app)
  static Future<void> init() async {
    if (_initialized) return;

    if (!Platform.isAndroid) return;

    // ✅ Permiso Android 13+
    await _requestPermissionIfNeeded();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _notifications.initialize(initSettings);

    // ✅ CREAR CANAL con sonido (CLAVE para que suene)
    await _createAndroidChannel();

    _initialized = true;
  }

  /// 🔹 Pedir permiso de notificaciones (Android 13+)
  static Future<void> _requestPermissionIfNeeded() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  /// ✅ Crea el canal con sonido en Android
  static Future<void> _createAndroidChannel() async {
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notificacion2'), // SIN .mp3
      enableVibration: true,
    );

    await androidPlugin.createNotificationChannel(channel);
  }

  /// 🔔 Notificación para NUEVO PEDIDO PENDIENTE
  static Future<void> notifyNuevoPedido() async {
    if (!Platform.isAndroid) return;
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notificacion2'),
      enableVibration: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1001,
      '📦 Nuevo pedido disponible',
      'Entró un pedido en Pedidos Pendientes',
      details,
    );
  }

  /// 🧪 Prueba rápida para verificar sonido
  static Future<void> testSound() async {
    await notifyNuevoPedido();
  }
}
