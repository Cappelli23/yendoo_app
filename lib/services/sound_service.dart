// lib/services/sound_service.dart
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    if (!Platform.isAndroid) return;
  }

  /// 🔔 Sonido genérico (el que ya usabas antes)
  static Future<void> playNotification() async {
    if (!Platform.isAndroid) return;

    try {
      await init();
      await _player.stop();
      await _player.play(
        AssetSource('sonidos/notificacion.mp3'),
      );
    } catch (_) {}
  }

  /// 🚨 Sonido EXCLUSIVO para pedidos pendientes
  static Future<void> playPedidosPendientes() async {
    if (!Platform.isAndroid) return;

    try {
      await init();
      await _player.stop();
      await _player.play(
        AssetSource('sonidos/notificacion2.mp3'),
      );
    } catch (_) {}
  }

  static Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
