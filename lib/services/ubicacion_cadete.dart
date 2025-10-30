import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class UbicacionCadeteService {
  StreamSubscription<Position>? _sub;

  Future<void> start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return;
    }
    if (permiso == LocationPermission.deniedForever) return;

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({
        'ubicacion': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}