import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'package:yendoo_app/screens/local/ver_cadetes_screen.dart';

class PersonalizarPedidoScreen extends StatefulWidget {
  const PersonalizarPedidoScreen({super.key});

  @override
  State<PersonalizarPedidoScreen> createState() =>
      _PersonalizarPedidoScreenState();
}

class _PersonalizarPedidoScreenState extends State<PersonalizarPedidoScreen> {
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
  LatLng? _destinoTmp;

  final TextEditingController _clienteCtl = TextEditingController();

  final TextEditingController _telefonoCtl = TextEditingController();

  final TextEditingController _linkCtl = TextEditingController();

  bool _marcandoDesdeLink = false;

  final List<String> _cadetesElegidos = [];

  List<QueryDocumentSnapshot> _docsCadetesFav = [];

  bool _mostrarCadetes = false;

  int? _tiempoPreparacion;

  double? _distKm;
  int? _montoTotal;
  bool _guardando = false;
  String? _clientOrderId;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _saldoStream;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  final List<maplibre.Symbol> _symbols = [];

  final List<maplibre.Circle> _circles = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subZonasRojas;
  List<List<maplibre.LatLng>> _zonasRojas = [];
  static const String _zonasSourceId = 'yendo-zonas-rojas';
  static const String _zonasLayerId = 'yendo-zonas-rojas-visual';

  bool _capaZonasCreada = false;
  bool _dibujandoZonas = false;
  bool _redibujarZonasPendiente = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      _saldoStream = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots();
    }

    _cargarLocalYFavoritos().then((_) => _escucharPedidos());
    _escucharZonasRojas();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subZonasRojas?.cancel();
    _clienteCtl.dispose();
    _telefonoCtl.dispose();
    _linkCtl.dispose();
    super.dispose();
  }

  List<maplibre.LatLng> _leerPuntosZona(dynamic raw) {
    if (raw is! List) return [];

    final puntos = <maplibre.LatLng>[];

    for (final item in raw) {
      if (item is! Map) return [];

      final lat = item['lat'];
      final lng = item['lng'];

      if (lat is! num || lng is! num) return [];

      puntos.add(
        maplibre.LatLng(lat.toDouble(), lng.toDouble()),
      );
    }

    return puntos;
  }

  bool _destinoEnZonaRoja(LatLng destino) {
    for (final zona in _zonasRojas) {
      bool dentro = false;
      int j = zona.length - 1;

      for (int i = 0; i < zona.length; i++) {
        final xi = zona[i].longitude;
        final yi = zona[i].latitude;
        final xj = zona[j].longitude;
        final yj = zona[j].latitude;

        if ((yi > destino.latitude) != (yj > destino.latitude) &&
            destino.longitude <
                (xj - xi) * (destino.latitude - yi) / (yj - yi) + xi) {
          dentro = !dentro;
        }

        j = i;
      }

      if (dentro) return true;
    }

    return false;
  }

  void _escucharZonasRojas() {
    _subZonasRojas = FirebaseFirestore.instance
        .collection('zonasRojas')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final nuevasZonas = <List<maplibre.LatLng>>[];

      for (final doc in snapshot.docs) {
        final datos = doc.data();

        if (datos['activo'] != true) continue;

        final puntos = _leerPuntosZona(datos['puntos']);

        if (puntos.length >= 3) {
          nuevasZonas.add(puntos);
        }
      }

      setState(() {
        _zonasRojas = nuevasZonas;
      });

      unawaited(_dibujarZonasRojas());
    }, onError: (Object error) {
      debugPrint('Error leyendo zonas rojas: $error');
    });
  }

  Future<void> _dibujarZonasRojas() async {
    final map = _mapLibreController;
    if (!_mapStyleLoaded || map == null) return;

    if (_dibujandoZonas) {
      _redibujarZonasPendiente = true;
      return;
    }

    _dibujandoZonas = true;

    try {
      do {
        _redibujarZonasPendiente = false;

        final features = <Map<String, dynamic>>[];

        for (final puntos in _zonasRojas) {
          if (puntos.length < 3) continue;

          final coordenadas =
              puntos.map((p) => [p.longitude, p.latitude]).toList();

          coordenadas.add([
            puntos.first.longitude,
            puntos.first.latitude,
          ]);

          features.add({
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [coordenadas],
            },
          });
        }

        final geojson = <String, dynamic>{
          'type': 'FeatureCollection',
          'features': features,
        };

        if (!_capaZonasCreada) {
          await map.addGeoJsonSource(
            _zonasSourceId,
            geojson,
          );

          await map.addFillLayer(
            _zonasSourceId,
            _zonasLayerId,
            const maplibre.FillLayerProperties(
              fillColor: '#E53935',
              fillOpacity: 0.30,
              fillOutlineColor: '#B71C1C',
            ),
            enableInteraction: false,
          );

          _capaZonasCreada = true;
        } else {
          await map.setGeoJsonSource(
            _zonasSourceId,
            geojson,
          );
        }
      } while (_redibujarZonasPendiente && mounted);
    } catch (e) {
      debugPrint('Error dibujando zonas rojas: $e');
    } finally {
      _dibujandoZonas = false;
    }
  }

  Future<void> _cargarLocalYFavoritos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    final docLocal =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    final dataLocal = docLocal.data();

    if (dataLocal == null) return;

    final geo = dataLocal['ubicacion'];

    if (geo != null) {
      _localPos = LatLng(
        (geo['lat'] as num).toDouble(),
        (geo['lng'] as num).toDouble(),
      );
    }

    final favRaw = dataLocal['cadetesFavoritos'];

    final favIDs =
        (favRaw is List) ? favRaw.whereType<String>().toList() : <String>[];

    _docsCadetesFav = [];
    _cadetesElegidos.clear();

    if (favIDs.isNotEmpty) {
      final snapFav = await FirebaseFirestore.instance
          .collection('usuarios')
          .where(
            FieldPath.documentId,
            whereIn: favIDs,
          )
          .get();

      _docsCadetesFav = snapFav.docs;
      _cadetesElegidos.addAll(favIDs);
    }

    if (mounted) {
      setState(() {});
    }

    await _dibujarMarkers();
  }

  void _escucharPedidos() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idLocal', isEqualTo: uid)
        .where('tipo', isEqualTo: 'personalizado')
        .where(
          'estado',
          whereIn: ['pendiente', 'aceptado'],
        )
        .snapshots()
        .listen((snap) async {
          if (!mounted) return;

          setState(() {
            _pedidos
              ..clear()
              ..addAll(
                snap.docs.where(
                  (d) => d['estado'] != 'entregado',
                ),
              );
          });

          await _dibujarMarkers();
        });
  }

  void _actualizarDistanciaMonto() {
    if (_localPos == null || _destinoTmp == null) {
      return;
    }

    final metros = const Distance().as(
      LengthUnit.Meter,
      _localPos!,
      _destinoTmp!,
    );

    final distRedondeada = ((metros / 100).ceil()) / 10.0;
    int monto;

    if (distRedondeada <= 1.0) {
      monto = 80;
    } else if (distRedondeada <= 2.0) {
      monto = 100;
    } else if (distRedondeada <= 3.0) {
      monto = 120;
    } else if (distRedondeada <= 4.0) {
      monto = 140;
    } else if (distRedondeada <= 5.0) {
      monto = 160;
    } else if (distRedondeada <= 6.0) {
      monto = 180;
    } else if (distRedondeada <= 7.0) {
      monto = 200;
    } else if (distRedondeada <= 8.0) {
      monto = 220;
    } else {
      monto = 240;
    }

    setState(() {
      _distKm = distRedondeada;
      _montoTotal = monto;
    });
  }

  Future<void> _confirmarPedido() async {
    if (_guardando) return;

    setState(() => _guardando = true);

    try {
      await _procesarPedidoPersonalizado();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _procesarPedidoPersonalizado() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null ||
        _localPos == null ||
        _destinoTmp == null ||
        _clienteCtl.text.trim().isEmpty ||
        _telefonoCtl.text.trim().isEmpty ||
        _cadetesElegidos.isEmpty ||
        _tiempoPreparacion == null ||
        _distKm == null ||
        _montoTotal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa todos los campos.',
          ),
        ),
      );
      return;
    }

    final double distanciaRedondeada = _distKm!;

    if (distanciaRedondeada > 8.5) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El destino está demasiado lejos (más de 8.5 km)',
          ),
        ),
      );
      return;
    }

    final String orderId = _clientOrderId ??
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc().id;

    _clientOrderId = orderId;

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('crearPedidoYendo');

      final resultado = await callable.call({
        'orderId': orderId,
        'tipo': 'personalizado',
        'cliente': _clienteCtl.text.trim(),
        'telefonoCliente': _telefonoCtl.text.trim(),
        'ubicacionDestino': {
          'lat': _destinoTmp!.latitude,
          'lng': _destinoTmp!.longitude,
        },
        'cadetesAsignados': List<String>.from(_cadetesElegidos),
        'tiempoPreparacion': _tiempoPreparacion,
      });

      final bool creado = resultado.data['creado'] == true;

      if (!creado) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este pedido ya fue confirmado.'),
          ),
        );
        return;
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'No se pudo generar el pedido.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el pedido: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _destinoTmp = null;
      _distKm = null;
      _montoTotal = null;
    });

    _clienteCtl.clear();
    _telefonoCtl.clear();
    _linkCtl.clear();
    _clientOrderId = null;

    await _dibujarMarkers();
  }

  Future<void> _pegarLink() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').trim();

    if (text.isEmpty) return;

    setState(() {
      _linkCtl.text = text;
    });
  }

  Future<void> _marcarDesdeLink() async {
    final raw = _linkCtl.text.trim();

    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pegá un link de Google Maps primero.'),
        ),
      );
      return;
    }

    setState(() => _marcandoDesdeLink = true);

    try {
      final coords = await _coordsFromGoogleMapsLink(raw);

      if (coords == null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pude leer coordenadas de ese link. Probá con “Compartir > Copiar vínculo” o un link que tenga @lat,lng.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        _destinoTmp = coords;
      });

      _actualizarDistanciaMonto();

      await Future.delayed(const Duration(milliseconds: 50));
      await _dibujarMarkers();

      await _mapLibreController?.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(
            coords.latitude,
            coords.longitude,
          ),
          16,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _marcandoDesdeLink = false);
      }
    }
  }

  Future<LatLng?> _coordsFromGoogleMapsLink(String url) async {
    final direct = _tryParseCoords(url);

    if (direct != null) return direct;

    final resolved = await _resolveFinalUrl(url);

    if (resolved == null) return null;

    return _tryParseCoords(resolved.toString());
  }

  LatLng? _tryParseCoords(String url) {
    final s = url.trim();

    final at = RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)');
    final mAt = at.firstMatch(s);

    if (mAt != null) {
      final lat = double.tryParse(mAt.group(1) ?? '');
      final lng = double.tryParse(mAt.group(2) ?? '');

      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final q = RegExp(
      r'(?:\?|&)(?:q|query|destination|ll)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
    );
    final mQ = q.firstMatch(s);

    if (mQ != null) {
      final lat = double.tryParse(mQ.group(1) ?? '');
      final lng = double.tryParse(mQ.group(2) ?? '');

      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final bang = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
    final mB = bang.firstMatch(s);

    if (mB != null) {
      final lat = double.tryParse(mB.group(1) ?? '');
      final lng = double.tryParse(mB.group(2) ?? '');

      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }

  Future<Uri?> _resolveFinalUrl(String input) async {
    Uri uri;

    try {
      uri = Uri.parse(input.trim());
    } catch (_) {
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final req = await client.getUrl(uri);

      req.followRedirects = true;
      req.maxRedirects = 8;
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');

      final res = await req.close();

      await res.drain();

      if (res.redirects.isNotEmpty) {
        Uri current = uri;

        for (final r in res.redirects) {
          current = current.resolveUri(r.location);
        }

        return current;
      }

      return uri;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _irAVerCadetes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerCadetesScreen(
          localId: uid,
        ),
      ),
    );

    final docLocal =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    final favRaw = docLocal.data()?['cadetesFavoritos'];
    final favIDs =
        (favRaw is List) ? favRaw.whereType<String>().toList() : <String>[];

    QuerySnapshot? snapFav;

    if (favIDs.isNotEmpty) {
      snapFav = await FirebaseFirestore.instance
          .collection('usuarios')
          .where(FieldPath.documentId, whereIn: favIDs)
          .get();
    }

    if (!mounted) return;

    setState(() {
      _docsCadetesFav = snapFav?.docs ?? [];
      _cadetesElegidos
        ..clear()
        ..addAll(favIDs);
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

    for (final c in List<maplibre.Circle>.from(_circles)) {
      try {
        await map.removeCircle(c);
      } catch (_) {}
    }

    _symbols.clear();
    _circles.clear();
  }

  String _colorToHex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');

    return '#${argb.substring(2)}';
  }

  Future<void> _dibujarMarkers() async {
    final map = _mapLibreController;

    if (!_mapStyleLoaded || map == null || _localPos == null) {
      return;
    }

    await _limpiarMarkers();

    // 🏪 local
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

    // 🔴🟢 pedidos
    for (final doc
        in List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_pedidos)) {
      final d = doc.data();

      final pos = LatLng(
        (d['ubicacionDestino']['lat'] as num).toDouble(),
        (d['ubicacionDestino']['lng'] as num).toDouble(),
      );

      final estado = d['estado'];

      final color = estado == 'pendiente' ? Colors.red : Colors.green;

      final circle = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(
            pos.latitude,
            pos.longitude,
          ),
          circleColor: _colorToHex(color),
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );

      _circles.add(circle);
    }

    // 🔵 destino temporal
    if (_destinoTmp != null) {
      final destinoCircle = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(
            _destinoTmp!.latitude,
            _destinoTmp!.longitude,
          ),
          circleColor: '#0066FF',
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );

      _circles.add(destinoCircle);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localPos == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Personalizar pedido',
        ),
      ),
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: maplibre.CameraPosition(
              target: maplibre.LatLng(
                _localPos!.latitude,
                _localPos!.longitude,
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
              _capaZonasCreada = false;

              await _dibujarZonasRojas();
              await _dibujarMarkers();
            },
            onMapClick: (_, point) async {
              setState(() {
                _destinoTmp = LatLng(
                  point.latitude,
                  point.longitude,
                );
              });

              _actualizarDistanciaMonto();

              await Future.delayed(const Duration(milliseconds: 50));
              await _dibujarMarkers();
            },
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Pegar link de Google Maps (opcional)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _linkCtl,
                        decoration: const InputDecoration(
                          hintText: 'Pegá un link de Google Maps…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _marcandoDesdeLink ? null : _pegarLink,
                              icon: const Icon(Icons.paste),
                              label: const Text('Pegar link'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  _marcandoDesdeLink ? null : _marcarDesdeLink,
                              icon: _marcandoDesdeLink
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.place),
                              label: Text(
                                _marcandoDesdeLink ? 'Marcando…' : 'Marcar',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_destinoTmp != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_destinoTmp != null &&
                          _destinoEnZonaRoja(_destinoTmp!)) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '⚠️ ZONA ROJA\n'
                            'Esta dirección está dentro de una zona de precaución.\n'
                            'Si no es un cliente habitual, recomendamos aceptar únicamente pagos por transferencia.\n'
                            'Podés continuar con el pedido normalmente.',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _clienteCtl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del cliente',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _telefonoCtl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp del cliente',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _tiempoPreparacion,
                        decoration: const InputDecoration(
                          labelText: 'Tiempo de preparación',
                          prefixIcon: Icon(Icons.access_time),
                          border: OutlineInputBorder(),
                        ),
                        hint: const Text('Seleccionar tiempo'),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 minutos')),
                          DropdownMenuItem(
                              value: 10, child: Text('10 minutos')),
                          DropdownMenuItem(
                              value: 15, child: Text('15 minutos')),
                          DropdownMenuItem(
                              value: 20, child: Text('20 minutos')),
                          DropdownMenuItem(
                              value: 21, child: Text('Más de 20 minutos')),
                        ],
                        onChanged: (valor) {
                          setState(() {
                            _tiempoPreparacion = valor;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _irAVerCadetes,
                        icon: const Icon(Icons.delivery_dining),
                        label: const Text(
                          'Agregar cadete favorito',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_docsCadetesFav.isNotEmpty)
                        Column(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _mostrarCadetes = !_mostrarCadetes;
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delivery_dining,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Cadetes agregados (${_docsCadetesFav.length}/12)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      _mostrarCadetes
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_mostrarCadetes) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _docsCadetesFav.map((cad) {
                                  final id = cad.id;
                                  final nombre = cad['nombre'] ?? 'Cadete';
                                  final sel = _cadetesElegidos.contains(id);

                                  return FilterChip(
                                    label: Text(nombre),
                                    selected: sel,
                                    onSelected: (v) {
                                      if (v && _cadetesElegidos.length >= 12) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Podés seleccionar un máximo de 12 cadetes.'),
                                          ),
                                        );
                                        return;
                                      }

                                      setState(() {
                                        if (v) {
                                          _cadetesElegidos.add(id);
                                        } else {
                                          _cadetesElegidos.remove(id);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(height: 12),
                      if (_distKm != null && _montoTotal != null)
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _saldoStream,
                          builder: (context, snapshot) {
                            final data = snapshot.data?.data();
                            final prepagoActivo =
                                data?['saldoPrepagoActivo'] == true;
                            final saldoDato = data?['saldo'];

                            final saldoValido = saldoDato is num &&
                                saldoDato.isFinite &&
                                saldoDato >= 0 &&
                                saldoDato % 1 == 0;

                            final saldo = saldoValido ? saldoDato.toInt() : 0;
                            final alcanza =
                                saldoValido && saldo >= _montoTotal!;

                            return Column(
                              children: [
                                Text(
                                  'Distancia: ${_distKm!.toStringAsFixed(1)} km\n'
                                  'Precio total: \$$_montoTotal',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (prepagoActivo) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    !snapshot.hasData
                                        ? 'Consultando saldo...'
                                        : !saldoValido
                                            ? 'Saldo no disponible'
                                            : 'Saldo disponible: \$$saldo',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          alcanza ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (snapshot.hasData && !alcanza)
                                    const Text(
                                      'Saldo insuficiente para generar el pedido',
                                      style: TextStyle(color: Colors.red),
                                      textAlign: TextAlign.center,
                                    ),
                                ],
                              ],
                            );
                          },
                        ),
                      ElevatedButton.icon(
                        onPressed: _guardando ? null : _confirmarPedido,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _guardando ? 'Guardando...' : 'Confirmar pedido',
                        ),
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
