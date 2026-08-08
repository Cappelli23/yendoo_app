import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'package:yendoo_app/services/ubicacion_cadete.dart';

// ✅ Push notifications
import 'package:yendoo_app/services/push_notification_service.dart';

// ✅ Importar las pantallas del cadete
import 'package:yendoo_app/screens/cadete/perfil_screen.dart';
import 'package:yendoo_app/screens/cadete/pedidos_pendientes_screen.dart';
import 'package:yendoo_app/screens/cadete/pedidos_personalizados_screen.dart';
import 'package:yendoo_app/screens/cadete/historial_pedidos_cadete_screen.dart';

// ✅ NUEVA pantalla
import 'package:yendoo_app/screens/cadete/listos_para_retiro_screen.dart';

class CadeteDashboardScreen extends StatefulWidget {
  const CadeteDashboardScreen({super.key});

  @override
  State<CadeteDashboardScreen> createState() => _CadeteDashboardScreenState();
}

class _CadeteDashboardScreenState extends State<CadeteDashboardScreen> {
  LatLng? _miUbicacion;
  bool _locationError = false;

  final _ubicacionService = UbicacionCadeteService();

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
    _obtenerUbicacionCadete();
    _ubicacionService.start();

    // ✅ IMPORTANTE: asegurar token + topic aunque el cadete siga logueado
    PushNotificationService.instance.registerCadeteActive();
  }

  Future<void> _obtenerUbicacionCadete() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (!doc.exists) {
        setState(() => _locationError = true);
        return;
      }

      final data = doc.data();

      if (data == null || !data.containsKey('ubicacion')) {
        setState(() => _locationError = true);
        return;
      }

      final geo = data['ubicacion'];

      double? lat;
      double? lng;

      if (geo is Map<String, dynamic>) {
        lat = (geo['lat'] as num?)?.toDouble();
        lng = (geo['lng'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) {
        setState(() => _locationError = true);
        return;
      }

      if (!mounted) return;

      setState(() {
        _miUbicacion = LatLng(lat!, lng!);
      });

      await _dibujarMarkers();
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = true);
      }
    }
  }

  Future<void> _dibujarMarkers() async {
    final map = _mapLibreController;

    if (!_mapStyleLoaded || map == null || _miUbicacion == null) {
      return;
    }

    for (final s in List<maplibre.Symbol>.from(_symbols)) {
      try {
        await map.removeSymbol(s);
      } catch (_) {}
    }

    _symbols.clear();

    // 🛵 marker cadete
    final cadeteMarker = await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(
          _miUbicacion!.latitude,
          _miUbicacion!.longitude,
        ),
        textField: '🛵',
        textSize: 30,
        textAnchor: 'center',
      ),
    );

    _symbols.add(cadeteMarker);
  }

  void _cerrarSesion(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({'activo': false});
    }

    _ubicacionService.stop();

    // ✅ Sacar del topic de cadetes activos al cerrar sesión
    await PushNotificationService.instance.unregisterCadeteActive();

    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/login');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión cerrada con éxito'),
        ),
      );
    }
  }

  // 🔢 Stream del contador de “listos para retirar” para este cadete
  Stream<int> _listosCountStream(String uidCadete) {
    return FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('estado', isEqualTo: 'entregado_al_cadete')
        .where('idCadete', isEqualTo: uidCadete)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Widget _botonFlotante(
    IconData icon,
    String texto,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(texto),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ubicacionService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cadete = FirebaseAuth.instance.currentUser;

    if (_locationError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.location_off,
                size: 48,
                color: Colors.redAccent,
              ),
              SizedBox(height: 12),
              Text(
                'No se pudo obtener la ubicación del cadete.\nVerifica tu perfil y vuelve a intentar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_miUbicacion == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 🌍 Mapa vectorial
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: maplibre.CameraPosition(
              target: maplibre.LatLng(
                _miUbicacion!.latitude,
                _miUbicacion!.longitude,
              ),
              zoom: 15,
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

          // 🧭 Botones
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _botonFlotante(
                      Icons.account_circle,
                      'Perfil',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PerfilScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // ✅ Botón: Listos para retirar con contador (N)
                    if (cadete != null)
                      StreamBuilder<int>(
                        stream: _listosCountStream(cadete.uid),
                        builder: (context, snap) {
                          final n = snap.data ?? 0;

                          final label = n > 0
                              ? 'Listos para retirar ($n)'
                              : 'Listos para retirar';

                          return _botonFlotante(
                            Icons.shopping_bag,
                            label,
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ListosParaRetiroScreen(),
                                ),
                              );
                            },
                          );
                        },
                      ),

                    if (cadete != null) const SizedBox(height: 16),

                    _botonFlotante(
                      Icons.list,
                      'Pedidos pendientes',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PedidosPendientesScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    _botonFlotante(
                      Icons.star,
                      'Pedidos personalizados',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PedidosPersonalizadosScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    _botonFlotante(
                      Icons.history,
                      'Historial',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const HistorialPedidosCadeteScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    _botonFlotante(
                      Icons.logout,
                      'Cerrar sesión',
                      () {
                        _cerrarSesion(context);
                      },
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
