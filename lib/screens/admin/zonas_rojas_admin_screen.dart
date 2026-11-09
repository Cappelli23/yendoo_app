import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

class ZonasRojasAdminScreen extends StatefulWidget {
  const ZonasRojasAdminScreen({super.key});

  @override
  State<ZonasRojasAdminScreen> createState() => _ZonasRojasAdminScreenState();
}

class _ZonasRojasAdminScreenState extends State<ZonasRojasAdminScreen> {
  maplibre.MapLibreMapController? _map;
  bool _estiloListo = false;
  bool _guardando = false;
  final List<maplibre.LatLng> _puntos = [];
  final List<maplibre.Fill> _rellenos = [];
  final List<maplibre.Line> _lineas = [];
  final List<maplibre.Circle> _circulos = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _suscripcion;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _zonas = [];
  bool _redibujando = false;
  bool _redibujarPendiente = false;

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
    _suscripcion = FirebaseFirestore.instance
        .collection('zonasRojas')
        .snapshots()
        .listen((snapshot) {
      _zonas = snapshot.docs;
      if (mounted) setState(() {});
      _dibujarTodo();
    }, onError: (Object error) {
      if (mounted) _mensaje('No se pudieron leer las zonas: $error');
    });
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  void _mensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  List<maplibre.LatLng> _leerPuntos(dynamic raw) {
    if (raw is! List) return [];
    final puntos = <maplibre.LatLng>[];
    for (final item in raw) {
      if (item is! Map) return [];
      final lat = item['lat'];
      final lng = item['lng'];
      if (lat is! num || lng is! num) return [];
      if (!lat.isFinite ||
          !lng.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        return [];
      }
      puntos.add(maplibre.LatLng(lat.toDouble(), lng.toDouble()));
    }
    return puntos;
  }

  Future<void> _dibujarTodo() async {
    if (!_estiloListo || _map == null) return;
    if (_redibujando) {
      _redibujarPendiente = true;
      return;
    }
    _redibujando = true;
    try {
      do {
        _redibujarPendiente = false;
        final mapa = _map;
        if (mapa == null || !_estiloListo) break;
        for (final fill in _rellenos) {
          try {
            await mapa.removeFill(fill);
          } catch (_) {}
        }
        for (final line in _lineas) {
          try {
            await mapa.removeLine(line);
          } catch (_) {}
        }
        for (final circle in _circulos) {
          try {
            await mapa.removeCircle(circle);
          } catch (_) {}
        }
        _rellenos.clear();
        _lineas.clear();
        _circulos.clear();

        for (final doc in _zonas) {
          final datos = doc.data();
          if (datos['activo'] != true) continue;
          final puntos = _leerPuntos(datos['puntos']);
          if (puntos.length < 3) {
            continue; // Ignora 'configuracion' y documentos inválidos.
          }
          final relleno = await mapa.addFill(maplibre.FillOptions(
            geometry: [puntos],
            fillColor: '#E53935',
            fillOpacity: 0.30,
            fillOutlineColor: '#B71C1C',
          ));
          _rellenos.add(relleno);
        }

        if (_puntos.length >= 3) {
          final relleno = await mapa.addFill(maplibre.FillOptions(
            geometry: [List<maplibre.LatLng>.from(_puntos)],
            fillColor: '#FF1744',
            fillOpacity: 0.35,
            fillOutlineColor: '#D50000',
          ));
          _rellenos.add(relleno);
        }
        if (_puntos.length >= 2) {
          final linea = await mapa.addLine(maplibre.LineOptions(
            geometry: List<maplibre.LatLng>.from(_puntos),
            lineColor: '#D50000',
            lineWidth: 3,
          ));
          _lineas.add(linea);
        }
        for (final punto in _puntos) {
          final circulo = await mapa.addCircle(maplibre.CircleOptions(
            geometry: punto,
            circleColor: '#D50000',
            circleRadius: 6,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ));
          _circulos.add(circulo);
        }
      } while (_redibujarPendiente && mounted);
    } catch (e) {
      _mensaje('No se pudo dibujar el mapa: $e');
    } finally {
      _redibujando = false;
    }
  }

  Future<void> _guardar() async {
    if (_puntos.length < 3 || _guardando) {
      _mensaje('Marcá al menos 3 puntos para formar una zona.');
      return;
    }
    final controlador = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar zona roja'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Nombre de la zona',
            hintText: 'Ej.: Barrio Norte',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controlador.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controlador.dispose();
    if (!mounted || nombre == null) return;
    if (nombre.isEmpty) {
      _mensaje('Escribí un nombre para la zona.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('zonasRojas').add({
        'nombre': nombre,
        'activo': true,
        'puntos': _puntos
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _puntos.clear());
      await _dibujarTodo();
      _mensaje('Zona roja guardada correctamente.');
    } catch (e) {
      _mensaje('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarEstado(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      await doc.reference.update({
        'activo': doc.data()['activo'] != true,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _mensaje('No se pudo actualizar: $e');
    }
  }

  Future<void> _eliminar(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar zona'),
        content: Text(
            '¿Eliminar definitivamente "${doc.data()['nombre'] ?? 'Sin nombre'}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await doc.reference.delete();
      _mensaje('Zona eliminada.');
    } catch (e) {
      _mensaje('No se pudo eliminar: $e');
    }
  }

  void _mostrarZonas() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('zonasRojas').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final zonas = snapshot.data!.docs
                  .where((d) => _leerPuntos(d.data()['puntos']).length >= 3)
                  .toList();
              return Column(children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Zonas guardadas',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                    child: zonas.isEmpty
                        ? const Center(
                            child: Text('Todavía no hay zonas guardadas.'))
                        : ListView.builder(
                            itemCount: zonas.length,
                            itemBuilder: (context, index) {
                              final doc = zonas[index];
                              final activo = doc.data()['activo'] == true;
                              return ListTile(
                                title: Text(
                                    (doc.data()['nombre'] ?? 'Sin nombre')
                                        .toString()),
                                subtitle:
                                    Text(activo ? 'Activa' : 'Desactivada'),
                                leading: Icon(Icons.location_on,
                                    color: activo ? Colors.red : Colors.grey),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip:
                                            activo ? 'Desactivar' : 'Activar',
                                        icon: Icon(activo
                                            ? Icons.visibility
                                            : Icons.visibility_off),
                                        onPressed: () => _cambiarEstado(doc),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red),
                                        onPressed: () => _eliminar(doc),
                                      ),
                                    ]),
                              );
                            },
                          )),
              ]);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrar zonas rojas'),
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Zonas guardadas',
            icon: const Icon(Icons.list_alt),
            onPressed: _mostrarZonas,
          ),
        ],
      ),
      body: Stack(children: [
        maplibre.MapLibreMap(
          styleString: _mapStyle,
          initialCameraPosition: const maplibre.CameraPosition(
            target: maplibre.LatLng(-34.73, -56.22),
            zoom: 14,
          ),
          minMaxZoomPreference: const maplibre.MinMaxZoomPreference(10, 18),
          myLocationEnabled: false,
          onMapCreated: (controller) => _map = controller,
          onStyleLoadedCallback: () {
            _estiloListo = true;
            _dibujarTodo();
          },
          onMapClick: (_, punto) {
            if (_guardando) return;
            setState(() => _puntos.add(punto));
            _dibujarTodo();
          },
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Tocá el mapa para marcar el contorno de la zona. '
                'Mínimo 3 puntos. Puntos marcados: ${_puntos.length}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 18,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _puntos.isEmpty || _guardando
                          ? null
                          : () {
                              setState(() => _puntos.removeLast());
                              _dibujarTodo();
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _puntos.isEmpty || _guardando
                          ? null
                          : () {
                              setState(() => _puntos.clear());
                              _dibujarTodo();
                            },
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpiar'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _puntos.length < 3 || _guardando ? null : _guardar,
                      icon: const Icon(Icons.save),
                      label: Text(_guardando ? 'Guardando...' : 'Guardar zona'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
