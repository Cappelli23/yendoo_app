import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'screens/local/historial_pedidos_screen.dart';
import 'screens/local/mis_pedidos_screen.dart';
import 'screens/local/ver_cadetes_screen.dart';
import 'login_screen.dart';

class LocalDashboard extends StatefulWidget {
  const LocalDashboard({super.key});

  @override
  State<LocalDashboard> createState() => _LocalDashboardState();
}

class _LocalDashboardState extends State<LocalDashboard> {
  LatLng? _currentPosition;
  bool _buttonsVisible = true;
  bool _locationError = false;

  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapStyleLoaded = false;

  final List<maplibre.Symbol> _symbols = [];

  static const String _mapStyle =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=jKh3fbz0oFEuYjlFsboz';

  @override
  void initState() {
    super.initState();
    _initLocation();
    _borrarFavoritosAlIniciar();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() => _locationError = true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          setState(() => _locationError = true);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationError = true);
        return;
      }

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((Position position) async {
        if (!mounted) return;

        final pos = LatLng(
          position.latitude,
          position.longitude,
        );

        setState(() {
          _currentPosition = pos;
        });

        // ✅ IMPORTANTE:
        // NO guardar ubicación actual en Firestore
        // para no pisar la ubicación fija del local

        await _dibujarMarkers();
      });
    } catch (e) {
      setState(() => _locationError = true);
    }
  }

  Future<void> _dibujarMarkers() async {
    final map = _mapLibreController;

    if (!_mapStyleLoaded || map == null || _currentPosition == null) {
      return;
    }

    for (final s in List<maplibre.Symbol>.from(_symbols)) {
      try {
        await map.removeSymbol(s);
      } catch (_) {}
    }

    _symbols.clear();

    // 🏪 marcador visual del local
    final localMarker = await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ),
        textField: '🏪',
        textSize: 30,
        textAnchor: 'center',
      ),
    );

    _symbols.add(localMarker);
  }

  Future<void> _borrarFavoritosAlIniciar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
      'cadetesFavoritos': [],
    });
  }

  Future<void> _borrarFavoritosAlCerrarSesion() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'cadetesFavoritos': [],
      });
    }
  }

  void _handleFABAction(String action) async {
    setState(() => _buttonsVisible = false);

    void safeNavigate(Function nav) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) nav();
        });
      }
    }

    switch (action) {
      case "generar":
        safeNavigate(
          () => Navigator.pushNamed(
            context,
            '/generarPedido',
          ),
        );
        break;

      case "personalizar":
        safeNavigate(
          () => Navigator.pushNamed(
            context,
            '/personalizarPedido',
          ),
        );
        break;

      case "verCadetes":
        final localId = FirebaseAuth.instance.currentUser?.uid;

        if (localId != null && mounted) {
          safeNavigate(
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VerCadetesScreen(
                  localId: localId,
                ),
              ),
            ),
          );
        }
        break;

      case "misPedidos":
        safeNavigate(
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MisPedidosScreen(),
            ),
          ),
        );
        break;

      case "historial":
        final localId = FirebaseAuth.instance.currentUser?.uid;

        if (localId != null && mounted) {
          safeNavigate(
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistorialPedidosScreen(
                  localId: localId,
                ),
              ),
            ),
          );
        }
        break;

      case "logout":
        await _borrarFavoritosAlCerrarSesion();

        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        safeNavigate(
          () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
            (route) => false,
          ),
        );
        break;
    }

    Future.delayed(
      const Duration(seconds: 2),
      () {
        if (mounted) {
          setState(() => _buttonsVisible = true);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final buttonMaxWidth = screenWidth * 0.85;

    if (_locationError) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Para usar Yendo debes activar la ubicación",
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    if (_currentPosition == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: maplibre.CameraPosition(
              target: maplibre.LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              zoom: 16,
            ),
            minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
              13,
              17,
            ),
            myLocationEnabled: false,
            onMapCreated: (controller) {
              _mapLibreController = controller;
            },
            onStyleLoadedCallback: () async {
              _mapStyleLoaded = true;
              await _dibujarMarkers();
            },
          ),
          if (_buttonsVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(217),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _actionButton(
                      "Generar pedido",
                      Icons.add_location,
                      "generar",
                      buttonMaxWidth,
                    ),
                    _actionButton(
                      "Personalizar",
                      Icons.edit_location_alt,
                      "personalizar",
                      buttonMaxWidth,
                    ),
                    _actionButton(
                      "Ver cadetes",
                      Icons.people_alt,
                      "verCadetes",
                      buttonMaxWidth,
                    ),
                    _actionButton(
                      "Mis pedidos",
                      Icons.list_alt,
                      "misPedidos",
                      buttonMaxWidth,
                    ),
                    _actionButton(
                      "Historial",
                      Icons.history,
                      "historial",
                      buttonMaxWidth,
                    ),
                    _logoutButton(
                      "Cerrar sesión",
                      Icons.logout,
                      "logout",
                      buttonMaxWidth,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    String action,
    double maxWidth,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ElevatedButton.icon(
        onPressed: () => _handleFABAction(action),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(
    String label,
    IconData icon,
    String action,
    double maxWidth,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ElevatedButton.icon(
        onPressed: () => _handleFABAction(action),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
