import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

class VerCadetesScreen extends StatefulWidget {
  final String localId;

  const VerCadetesScreen({
    super.key,
    required this.localId,
  });

  @override
  State<VerCadetesScreen> createState() => _VerCadetesScreenState();
}

class _VerCadetesScreenState extends State<VerCadetesScreen> {
  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapStyleLoaded = false;

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

  LatLng? _localPos;

  final List<Map<String, dynamic>> _cadetes = [];
  final List<String> _favoritos = [];

  final List<maplibre.Symbol> _symbols = [];
  final List<maplibre.Circle> _cadeteCircles = [];
  final Map<maplibre.Circle, Map<String, dynamic>> _circleCadetes = {};

  @override
  void initState() {
    super.initState();
    _cargarLocal();
    _cargarFavoritos();
    _escucharCadetes();
  }

  Future<void> _cargarLocal() async {
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.localId)
        .get();

    final geo = doc.data()?['ubicacion'];

    if (geo != null && mounted) {
      setState(() {
        _localPos = LatLng(
          (geo['lat'] as num).toDouble(),
          (geo['lng'] as num).toDouble(),
        );
      });

      await _dibujarMarkers();
    }
  }

  Future<void> _cargarFavoritos() async {
    final d = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.localId)
        .get();

    final raw = d.data()?['cadetesFavoritos'];

    if (raw is List && mounted) {
      setState(() {
        _favoritos
          ..clear()
          ..addAll(raw.whereType<String>());
      });

      await _dibujarMarkers();
    }
  }

  Future<void> _alternarFavorito(String idCad) async {
    final ref =
        FirebaseFirestore.instance.collection('usuarios').doc(widget.localId);

    final esFavorito = _favoritos.contains(idCad);

    if (!esFavorito && _favoritos.length >= 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Máximo 8 cadetes favoritos alcanzado'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (esFavorito) {
      await ref.update({
        'cadetesFavoritos': FieldValue.arrayRemove([idCad]),
      });
    } else {
      await ref.update({
        'cadetesFavoritos': FieldValue.arrayUnion([idCad]),
      });
    }

    if (!mounted) return;

    setState(() {
      if (esFavorito) {
        _favoritos.remove(idCad);
      } else {
        _favoritos.add(idCad);
      }
    });

    await _dibujarMarkers();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          esFavorito
              ? 'Cadete quitado de favoritos'
              : 'Cadete agregado a favoritos',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _escucharCadetes() {
    FirebaseFirestore.instance
        .collection('usuarios')
        .where('rol', isEqualTo: 'cadete')
        .snapshots()
        .listen((snap) async {
      debugPrint('Cadetes encontrados: ${snap.docs.length}');

      final lista = snap.docs.where((d) {
        final data = d.data();
        return data['ubicacion'] != null;
      }).map((d) {
        final data = d.data();

        return {
          'id': d.id,
          'nombre': data['nombre'] ?? 'Cadete',
          'telefono': data['telefono'] ?? '',
          'mostrarTelefono': data['mostrarNumero'] == true,
          'ubicacion': data['ubicacion'],
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _cadetes
          ..clear()
          ..addAll(lista);
      });

      await _dibujarMarkers();
    });
  }

  Future<void> _limpiarMarkers() async {
    final map = _mapLibreController;
    if (map == null) return;

    for (final s in List<maplibre.Symbol>.from(_symbols)) {
      try {
        await map.removeSymbol(s);
      } catch (_) {}
    }

    for (final c in List<maplibre.Circle>.from(_cadeteCircles)) {
      try {
        await map.removeCircle(c);
      } catch (_) {}
    }

    _symbols.clear();
    _cadeteCircles.clear();
    _circleCadetes.clear();
  }

  Future<void> _dibujarMarkers() async {
    final map = _mapLibreController;

    if (!_mapStyleLoaded || map == null || _localPos == null) {
      return;
    }

    await _limpiarMarkers();

    final localSymbol = await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(
          _localPos!.latitude,
          _localPos!.longitude,
        ),
        textField: '🏪',
        textSize: 30,
        textAnchor: 'center',
      ),
    );

    _symbols.add(localSymbol);

    for (final cad in _cadetes) {
      final loc = cad['ubicacion'];
      if (loc == null) continue;

      final pos = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );

      final esFav = _favoritos.contains(cad['id']);

      final circle = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(
            pos.latitude,
            pos.longitude,
          ),
          circleColor: esFav ? '#FF0000' : '#00AA00',
          circleRadius: 11,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );

      _cadeteCircles.add(circle);
      _circleCadetes[circle] = cad;
    }
  }

  void _mostrarInfo(Map<String, dynamic> cad) {
    final esFav = _favoritos.contains(cad['id']);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(cad['nombre']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cad['mostrarTelefono'] == true)
              Text('Teléfono: ${cad['telefono']}'),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _alternarFavorito(cad['id']);
              },
              icon: Icon(
                esFav ? Icons.favorite : Icons.favorite_border,
              ),
              label: Text(
                esFav
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos (${_favoritos.length}/8)',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(
                  context,
                  {
                    'id': cad['id'],
                    'nombre': cad['nombre'],
                  },
                );
              },
              icon: const Icon(Icons.check),
              label: const Text('Seleccionar para pedido'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localPos == null) {
      return const Scaffold(
        body: Center(
          child: Text('Sin ubicación del local'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadetes disponibles'),
      ),
      body: maplibre.MapLibreMap(
        styleString: _mapStyle,
        initialCameraPosition: maplibre.CameraPosition(
          target: maplibre.LatLng(
            _localPos!.latitude,
            _localPos!.longitude,
          ),
          zoom: 14,
        ),
        minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
          13,
          17,
        ),
        myLocationEnabled: false,
        onMapCreated: (controller) {
          _mapLibreController = controller;

          controller.onCircleTapped.add((circle) {
            final cadete = _circleCadetes[circle];
            if (cadete != null) {
              _mostrarInfo(cadete);
            }
          });
        },
        onStyleLoadedCallback: () async {
          _mapStyleLoaded = true;
          await _dibujarMarkers();
        },
      ),
    );
  }
}
