import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  // Un solo player reutilizable
  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

  static Future<void> playNotification() async {
    try {
      // Por las dudas, detenemos lo anterior
      await _player.stop();
      // Asegurate de que la ruta coincida con pubspec.yaml
      await _player.play(
        AssetSource('sonidos/notificacion.mp3'),
      );
    } catch (e) {
      debugPrint('Error reproduciendo sonido de notificación: $e');
    }
  }
}
