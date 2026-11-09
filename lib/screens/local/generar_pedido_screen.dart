// lib/screens/local/generar_pedido_screen.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:latlong2/latlong.dart' as latlng2;

class GenerarPedidoScreen extends StatefulWidget {
  const GenerarPedidoScreen({super.key});

  @override
  State<GenerarPedidoScreen> createState() => _GenerarPedidoScreenState();
}

class _GenerarPedidoScreenState extends State<GenerarPedidoScreen> {
  maplibre.MapLibreMapController? _map;
  bool _styleReady = false;

  latlng2.LatLng? _localPos;
  latlng2.LatLng? _destinoTmp;

  final TextEditingController _clienteCtl = TextEditingController();
  final TextEditingController _telefonoCtl = TextEditingController();
  final TextEditingController _linkCtl = TextEditingController();

  bool _marcandoDesdeLink = false;
  bool _seleccionando = false;

  double? _distKm;
  int? _montoTotal;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  String? _clientOrderId;
  bool _guardando = false;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _saldoStream;

  final List<maplibre.Circle> _circles = [];
  final List<maplibre.Symbol> _symbols = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subZonasRojas;

  List<List<maplibre.LatLng>> _zonasRojas = [];

  static const String _zonasSourceId = 'yendo-zonas-rojas';
  static const String _zonasLayerId = 'yendo-zonas-rojas-visual';

  bool _capaZonasCreada = false;
  bool _dibujandoZonas = false;
  bool _redibujarZonasPendiente = false;

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

  double _to1DecimalDouble(double km) => (km * 10).ceil() / 10.0;

  double _as1DecimalDouble(dynamic v, {double def = 0}) {
    if (v == null) return def;
    if (v is double) return _to1DecimalDouble(v);
    if (v is int) return _to1DecimalDouble(v.toDouble());
    if (v is num) return _to1DecimalDouble(v.toDouble());
    if (v is String) return _to1DecimalDouble(double.tryParse(v) ?? def);
    return def;
  }

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
    _nuevoOrderId();
    _cargarLocal().then((_) => _escucharPedidos());
    _escucharZonasRojas();
  }

  @override
  void dispose() {
    _clienteCtl.dispose();
    _telefonoCtl.dispose();
    _linkCtl.dispose();
    _sub?.cancel();
    _subZonasRojas?.cancel();
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

  bool _destinoEnZonaRoja(latlng2.LatLng destino) {
    for (final zona in _zonasRojas) {
      if (zona.length < 3) continue;

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
    final map = _map;
    if (!_styleReady || map == null) return;

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

  void _nuevoOrderId() {
    _clientOrderId =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc().id;
  }

  void _resetNuevoPedido() {
    setState(() {
      _destinoTmp = null;
      _seleccionando = false;
      _distKm = null;
      _montoTotal = null;
      _clienteCtl.clear();
      _telefonoCtl.clear();
    });

    _nuevoOrderId();
    _refreshMapMarkers();
  }

  Future<void> _cargarLocal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final data = doc.data();

    if (!mounted || data?['ubicacion'] == null) return;

    setState(() {
      _localPos = latlng2.LatLng(
        (data!['ubicacion']['lat'] as num).toDouble(),
        (data['ubicacion']['lng'] as num).toDouble(),
      );
    });
  }

  void _escucharPedidos() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idLocal', isEqualTo: uid)
        .where('estado', whereIn: ['pendiente', 'aceptado'])
        .snapshots()
        .listen((snap) {
          if (!mounted) return;

          setState(() {
            _pedidos
              ..clear()
              ..addAll(snap.docs);
          });

          _refreshMapMarkers();
        });
  }

  double _ceilTo01KmFromMeters(double meters) => (meters / 100).ceil() / 10.0;

  int _precioCadeteDesdeKmMostrable(double km) {
    if (km <= 1.0) return 65;
    if (km <= 2.0) return 85;
    if (km <= 3.0) return 105;
    if (km <= 4.0) return 125;
    if (km <= 5.0) return 145;
    if (km <= 6.0) return 165;
    if (km <= 7.0) return 185;
    if (km <= 8.0) return 205;
    return 225;
  }

  void _actualizarMontos() {
    if (_localPos == null || _destinoTmp == null) return;

    final metros = const latlng2.Distance().as(
      latlng2.LengthUnit.Meter,
      _localPos!,
      _destinoTmp!,
    );

    final distRed = _ceilTo01KmFromMeters(metros);

    if (distRed > 8.5) {
      setState(() {
        _distKm = distRed;
        _montoTotal = null;
      });
      return;
    }

    final montoCad = _precioCadeteDesdeKmMostrable(distRed);
    const ganAdmin = 15;

    setState(() {
      _distKm = distRed;
      _montoTotal = montoCad + ganAdmin;
    });
  }

  Future<void> _guardarPedido() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _destinoTmp == null || _localPos == null) return;

    if (_guardando) return;
    setState(() => _guardando = true);

    try {
      final cliente = _clienteCtl.text.trim();
      final telefono = _telefonoCtl.text.trim();

      if (cliente.isEmpty ||
          telefono.isEmpty ||
          _montoTotal == null ||
          _distKm == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa nombre, teléfono y destino.')),
        );
        return;
      }

      final double distanciaMostrable = _as1DecimalDouble(_distKm!, def: 0);

      if (distanciaMostrable > 8.5) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El destino está demasiado lejos (más de 8.5 km)'),
          ),
        );
        return;
      }

      final String orderId = _clientOrderId ??
          FirebaseFirestore.instance.collection('pedidosEnCurso').doc().id;

      _clientOrderId = orderId;

      final callable = FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('crearPedidoYendo');

      final resultado = await callable.call({
        'orderId': orderId,
        'tipo': 'normal',
        'cliente': cliente,
        'telefonoCliente': telefono,
        'ubicacionDestino': {
          'lat': _destinoTmp!.latitude,
          'lng': _destinoTmp!.longitude,
        },
      });

      final bool creado = resultado.data['creado'] == true;

      if (!mounted) return;

      if (!creado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ese pedido ya fue confirmado. Para otro, generá uno nuevo.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido generado con éxito.')),
      );

      _resetNuevoPedido();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'failed-precondition'
                ? 'Saldo insuficiente'
                : 'No se pudo generar el pedido',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo generar el pedido'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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
        const SnackBar(content: Text('Pegá un link de Google Maps primero.')),
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
        _seleccionando = true;
      });

      _actualizarMontos();
      _refreshMapMarkers();

      await _map?.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(coords.latitude, coords.longitude),
          16,
        ),
      );
    } finally {
      if (mounted) setState(() => _marcandoDesdeLink = false);
    }
  }

  Future<latlng2.LatLng?> _coordsFromGoogleMapsLink(String url) async {
    final direct = _tryParseCoords(url);
    if (direct != null) return direct;

    final resolved = await _resolveFinalUrl(url);
    if (resolved == null) return null;

    return _tryParseCoords(resolved.toString());
  }

  latlng2.LatLng? _tryParseCoords(String url) {
    final s = url.trim();

    final at = RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)');
    final mAt = at.firstMatch(s);

    if (mAt != null) {
      final lat = double.tryParse(mAt.group(1) ?? '');
      final lng = double.tryParse(mAt.group(2) ?? '');

      if (lat != null && lng != null) {
        return latlng2.LatLng(lat, lng);
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
        return latlng2.LatLng(lat, lng);
      }
    }

    final bang = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
    final mB = bang.firstMatch(s);

    if (mB != null) {
      final lat = double.tryParse(mB.group(1) ?? '');
      final lng = double.tryParse(mB.group(2) ?? '');

      if (lat != null && lng != null) {
        return latlng2.LatLng(lat, lng);
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

    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

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

  Future<void> _onMapCreated(maplibre.MapLibreMapController controller) async {
    _map = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    _capaZonasCreada = false;

    await _dibujarZonasRojas();
    await _refreshMapMarkers();
  }

  Future<void> _clearMapMarkers() async {
    if (_map == null) return;

    for (final circle in List<maplibre.Circle>.from(_circles)) {
      try {
        await _map!.removeCircle(circle);
      } catch (_) {}
    }

    for (final symbol in List<maplibre.Symbol>.from(_symbols)) {
      try {
        await _map!.removeSymbol(symbol);
      } catch (_) {}
    }

    _circles.clear();
    _symbols.clear();
  }

  String _colorToHex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2)}';
  }

  Future<void> _refreshMapMarkers() async {
    if (!_styleReady || _map == null || _localPos == null) return;

    await _clearMapMarkers();

    final localSymbol = await _map!.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(_localPos!.latitude, _localPos!.longitude),
        textField: '🏪',
        textSize: 28,
        textAnchor: 'center',
      ),
    );

    _symbols.add(localSymbol);

    for (final doc in _pedidos) {
      final d = doc.data();
      final u = d['ubicacionDestino'];

      if (u is! Map || u['lat'] == null || u['lng'] == null) continue;

      final lat = (u['lat'] as num).toDouble();
      final lng = (u['lng'] as num).toDouble();
      final estado = (d['estado'] ?? '').toString();

      final color = estado == 'pendiente' ? Colors.red : Colors.green;

      final circle = await _map!.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(lat, lng),
          circleColor: _colorToHex(color),
          circleRadius: 9,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );

      _circles.add(circle);
    }

    if (_destinoTmp != null) {
      final destinoCircle = await _map!.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(
            _destinoTmp!.latitude,
            _destinoTmp!.longitude,
          ),
          circleColor: _colorToHex(Colors.blue),
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );

      _circles.add(destinoCircle);

      final destinoSymbol = await _map!.addSymbol(
        maplibre.SymbolOptions(
          geometry: maplibre.LatLng(
            _destinoTmp!.latitude,
            _destinoTmp!.longitude,
          ),
          textField: '✎',
          textSize: 18,
          textColor: '#FFFFFF',
          textAnchor: 'center',
        ),
      );

      _symbols.add(destinoSymbol);
    }
  }

  void _onMapLongClick(
    dynamic point,
    maplibre.LatLng coordinates,
  ) {
    setState(() {
      _destinoTmp = latlng2.LatLng(
        coordinates.latitude,
        coordinates.longitude,
      );
      _seleccionando = true;
    });

    _actualizarMontos();
    _refreshMapMarkers();
  }

  Future<void> _zoomTo(double zoom) async {
    final current = _destinoTmp ?? _localPos;
    if (current == null || _map == null) return;

    await _map!.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(current.latitude, current.longitude),
        zoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localPos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Generar pedido')),
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: maplibre.CameraPosition(
              target: maplibre.LatLng(
                _localPos!.latitude,
                _localPos!.longitude,
              ),
              zoom: 14,
            ),
            minMaxZoomPreference: const maplibre.MinMaxZoomPreference(13, 17),
            myLocationEnabled: true,
            myLocationTrackingMode: maplibre.MyLocationTrackingMode.none,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapLongClick,
            onMapLongClick: _onMapLongClick,
          ),
          Positioned(
            right: 12,
            top: 120,
            child: Column(
              children: [
                _ZoomButton(label: '13', onTap: () => _zoomTo(13)),
                const SizedBox(height: 6),
                _ZoomButton(label: '15', onTap: () => _zoomTo(15)),
                const SizedBox(height: 6),
                _ZoomButton(label: '17', onTap: () => _zoomTo(17)),
              ],
            ),
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
                        style: TextStyle(fontWeight: FontWeight.w700),
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
          if (_seleccionando && _destinoTmp != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _telefonoCtl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp del cliente (con código de país)',
                        border: OutlineInputBorder(),
                        hintText: 'Ej: +598 98 123 456',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_distKm != null && _montoTotal != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Distancia: ${_distKm!.toStringAsFixed(1)} km — Envío: \$$_montoTotal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _saldoStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Text('Consultando saldo...');
                        }

                        final data = snapshot.data?.data();
                        final saldo = data?['saldo'];
                        final disponible = saldo is num ? saldo : 0;

                        final insuficiente =
                            _montoTotal != null && disponible < _montoTotal!;

                        return Column(
                          children: [
                            Text(
                              'Saldo disponible: \$$disponible',
                              style: TextStyle(
                                color: insuficiente ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (insuficiente)
                              const Text(
                                'Saldo insuficiente para generar el pedido',
                                style: TextStyle(color: Colors.red),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_distKm != null &&
                        _distKm! > 8.5 &&
                        _montoTotal == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'El destino está demasiado lejos (más de 8.5 km)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (_distKm != null &&
                                  _distKm! <= 8.5 &&
                                  _montoTotal != null &&
                                  !_guardando)
                              ? _guardarPedido
                              : null,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(_guardando ? 'Guardando…' : 'Confirmar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _guardando
                              ? null
                              : () {
                                  setState(() {
                                    _destinoTmp = null;
                                    _seleccionando = false;
                                    _distKm = null;
                                    _montoTotal = null;
                                  });

                                  _refreshMapMarkers();
                                },
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 46,
          height: 40,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
