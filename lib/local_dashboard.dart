import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  static const String _mapStyle = '''
{
  "version": 8,
  "glyphs": "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
  "sources": {
    "yendo": {
      "type": "vector",
      "url": "pmtiles://https://yendo-mapa.luisilva17lccs.workers.dev/uruguay.pmtiles"
    }
  },
  "layers": [
    { "id": "background", "type": "background", "paint": { "background-color": "#f7f7f3" } },

    {
      "id": "landcover",
      "type": "fill",
      "source": "yendo",
      "source-layer": "landcover",
      "paint": {
        "fill-color": ["match", ["get", "class"], "wood", "#b8dca4", "forest", "#b8dca4", "grass", "#cfe8b8", "farmland", "#d7e8b8", "#d8edc8"],
        "fill-opacity": 0.75
      }
    },

    {
      "id": "landuse",
      "type": "fill",
      "source": "yendo",
      "source-layer": "landuse",
      "paint": {
        "fill-color": ["match", ["get", "class"], "residential", "#e2e2e2", "commercial", "#ead1dc", "retail", "#ead1dc", "industrial", "#d9c7b0", "school", "#f3dddd", "hospital", "#f3dddd", "cemetery", "#d6e4c6", "park", "#b9df9b", "#e2e2e2"],
        "fill-opacity": 0.92
      }
    },

    { "id": "parks", "type": "fill", "source": "yendo", "source-layer": "park", "paint": { "fill-color": "#b9df9b", "fill-opacity": 0.95 } },
    { "id": "water", "type": "fill", "source": "yendo", "source-layer": "water", "paint": { "fill-color": "#9fd5f2" } },

    {
      "id": "buildings",
      "type": "fill",
      "source": "yendo",
      "source-layer": "building",
      "minzoom": 13,
      "paint": {
        "fill-color": "#d0d0d0",
        "fill-outline-color": "#b5b5b5",
        "fill-opacity": 0.95
      }
    },

    {
      "id": "roads-border",
      "type": "line",
      "source": "yendo",
      "source-layer": "transportation",
      "paint": {
        "line-color": "#aaaaaa",
        "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.7, 13, 2.8, 15, 5.5, 17, 10.5]
      }
    },

    {
      "id": "roads-main",
      "type": "line",
      "source": "yendo",
      "source-layer": "transportation",
      "paint": {
        "line-color": "#ffffff",
        "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.4, 13, 1.8, 15, 4.2, 17, 8.5]
      }
    },

    {
      "id": "road-names",
      "type": "symbol",
      "source": "yendo",
      "source-layer": "transportation_name",
      "minzoom": 13,
      "layout": {
        "symbol-placement": "line",
        "text-field": ["get", "name:latin"],
        "text-size": ["interpolate", ["linear"], ["zoom"], 13, 11, 15, 15, 17, 19],
        "text-font": ["Noto Sans Regular"],
        "text-allow-overlap": false,
        "text-ignore-placement": false
      },
      "paint": { "text-color": "#222222", "text-halo-color": "#ffffff", "text-halo-width": 2 }
    },

    {
      "id": "housenumbers",
      "type": "symbol",
      "source": "yendo",
      "source-layer": "housenumber",
      "minzoom": 16,
      "layout": {
        "text-field": ["get", "housenumber"],
        "text-size": ["interpolate", ["linear"], ["zoom"], 16, 9, 17, 10, 19, 13],
        "text-font": ["Noto Sans Regular"],
        "text-allow-overlap": false
      },
      "paint": { "text-color": "#555555", "text-halo-color": "#ffffff", "text-halo-width": 1.2 }
    },

    {
      "id": "poi-labels",
      "type": "symbol",
      "source": "yendo",
      "source-layer": "poi",
      "minzoom": 14,
      "layout": {
        "text-field": ["coalesce", ["get", "name"], ["get", "name:latin"]],
        "text-size": ["interpolate", ["linear"], ["zoom"], 14, 11, 16, 13, 18, 15],
        "text-font": ["Noto Sans Regular"],
        "text-allow-overlap": false
      },
      "paint": {
        "text-color": "#8b1e3f",
        "text-halo-color": "#ffffff",
        "text-halo-width": 2
      }
    },

    {
      "id": "place-names",
      "type": "symbol",
      "source": "yendo",
      "source-layer": "place",
      "minzoom": 5,
      "layout": {
        "text-field": ["get", "name:latin"],
        "text-size": ["interpolate", ["linear"], ["zoom"], 5, 11, 10, 14, 14, 18],
        "text-font": ["Noto Sans Regular"]
      },
      "paint": { "text-color": "#333333", "text-halo-color": "#ffffff", "text-halo-width": 1.7 }
    }
  ]
}
''';

  @override
  void initState() {
    super.initState();
    _initLocation();
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
