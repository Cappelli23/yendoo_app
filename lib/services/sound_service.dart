// Servicio de sonido temporal SIN audioplayers para que la app no crashee en iOS.
// De momento solo dejamos métodos estáticos vacíos para que el resto del código compile.

class SoundService {
  // Si en algún lado usás inicialización, no va a hacer nada.
  static Future<void> init() async {
    // No-op
  }

  // Llamada estática para reproducir sonido de notificación.
  // Antes usaba audioplayers, ahora queda vacío para no romper iOS.
  static Future<void> playNotification() async {
    // No-op por ahora
  }
}
