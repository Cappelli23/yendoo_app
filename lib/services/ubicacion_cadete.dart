import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class UbicacionCadeteService {
  StreamSubscription<Position>? _sub;

  Future<void> start() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1️⃣ Verificar que el servicio de ubicación esté activo
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // No forzamos nada, simplemente no arrancamos el stream
        return;
      }

      // 2️⃣ Manejo de permisos con cuidado
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          return;
        }
      }

      if (permiso == LocationPermission.deniedForever) {
        // Usuario bloqueó permisos desde ajustes → no seguimos
        return;
      }

      // 3️⃣ Iniciar stream de ubicación con try/catch implícito
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((pos) async {
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;

          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(currentUser.uid)
              .update({
            'ubicacion': {
              'lat': pos.latitude,
              'lng': pos.longitude,
              'timestamp': FieldValue.serverTimestamp(),
            },
          });
        } catch (e) {
          // Podés loguear el error si querés, pero nunca crashear
        }
      });
    } catch (e) {
      // Cualquier error inesperado en iOS / iPadOS queda atrapado acá
      // y NO tumba la app.
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
