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

  static const String _mapStyle =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=jKh3fbz0oFEuYjlFsboz';

  LatLng? _localPos;

  final List<Map<String, dynamic>> _cadetes = [];

  final List<String> _favoritos = [];

  final List<maplibre.Symbol> _symbols = [];

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
          ..addAll(
            raw.whereType<String>(),
          );
      });

      await _dibujarMarkers();
    }
  }

  Future<void> _alternarFavorito(String idCad) async {
    final ref =
        FirebaseFirestore.instance.collection('usuarios').doc(widget.localId);

    final doc = await ref.get();

    List<dynamic> favs = doc.data()?['cadetesFavoritos'] ?? [];

    final esFavorito = favs.contains(idCad);

    if (!esFavorito && favs.length >= 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Máximo 8 cadetes favoritos alcanzado',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    esFavorito ? favs.remove(idCad) : favs.add(idCad);

    await ref.update({
      'cadetesFavoritos': favs,
    });

    if (!mounted) return;

    setState(() {
      esFavorito ? _favoritos.remove(idCad) : _favoritos.add(idCad);
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
        .where('ubicacion', isNotEqualTo: null)
        .snapshots()
        .listen((snap) async {
      final lista = snap.docs
          .map(
            (d) => {
              'id': d.id,
              'nombre': d['nombre'] ?? 'Cadete',
              'telefono': d['telefono'] ?? '',
              'mostrarTelefono': d['mostrarNumero'] == true,
              'ubicacion': d['ubicacion'],
            },
          )
          .toList();

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

    _symbols.clear();
  }

  Future<void> _dibujarMarkers() async {
    final map = _mapLibreController;

    if (!_mapStyleLoaded || map == null || _localPos == null) {
      return;
    }

    await _limpiarMarkers();

    // 🏪 LOCAL
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

    // 🛵 CADETES
    for (final cad in _cadetes) {
      final loc = cad['ubicacion'];

      if (loc == null) continue;

      final pos = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );

      final esFav = _favoritos.contains(
        cad['id'],
      );

      final symbol = await map.addSymbol(
        maplibre.SymbolOptions(
          geometry: maplibre.LatLng(
            pos.latitude,
            pos.longitude,
          ),

          // 🛵 marker
          textField: '🛵',

          textSize: 28,

          textColor: esFav ? '#FF0000' : '#00AA00',

          textAnchor: 'center',
        ),
      );

      _symbols.add(symbol);
    }
  }

  void _mostrarInfo(Map<String, dynamic> cad) {
    final esFav = _favoritos.contains(
      cad['id'],
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          cad['nombre'],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cad['mostrarTelefono'] == true)
              Text(
                'Teléfono: ${cad['telefono']}',
              ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);

                _alternarFavorito(
                  cad['id'],
                );
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
              label: const Text(
                'Seleccionar para pedido',
              ),
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
          child: Text(
            'Sin ubicación del local',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cadetes disponibles',
        ),
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

          controller.onSymbolTapped.add((symbol) {
            final index = _symbols.indexOf(
              symbol,
            );

            // El primero es el local
            if (index <= 0) return;

            final cadete = _cadetes[index - 1];

            _mostrarInfo(
              cadete,
            );
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
