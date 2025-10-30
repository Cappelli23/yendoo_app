import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:yendoo_app/screens/local/ver_cadetes_screen.dart';

class PersonalizarPedidoScreen extends StatefulWidget {
  const PersonalizarPedidoScreen({super.key});

  @override
  State<PersonalizarPedidoScreen> createState() =>
      _PersonalizarPedidoScreenState();
}

class _PersonalizarPedidoScreenState extends State<PersonalizarPedidoScreen> {
  final MapController _map = MapController();
  LatLng? _localPos;
  LatLng? _destinoTmp;

  final TextEditingController _clienteCtl = TextEditingController();
  final TextEditingController _telefonoCtl = TextEditingController();

  final List<String> _cadetesElegidos = [];
  List<QueryDocumentSnapshot> _docsCadetesFav = [];

  double? _distKm;
  int? _montoTotal;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _cargarLocalYFavoritos().then((_) => _escucharPedidos());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clienteCtl.dispose();
    _telefonoCtl.dispose();
    super.dispose();
  }

  Future<void> _cargarLocalYFavoritos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docLocal =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final dataLocal = docLocal.data();
    if (dataLocal == null) return;

    final geo = dataLocal['ubicacion'];
    if (geo != null) _localPos = LatLng(geo['lat'], geo['lng']);

    final favRaw = dataLocal['cadetesFavoritos'];
    final favIDs =
        (favRaw is List) ? favRaw.whereType<String>().toList() : <String>[];

    if (favIDs.isNotEmpty) {
      final snapFav = await FirebaseFirestore.instance
          .collection('usuarios')
          .where(FieldPath.documentId, whereIn: favIDs)
          .get();
      _docsCadetesFav = snapFav.docs;
      _cadetesElegidos.addAll(favIDs);
    }

    if (mounted) setState(() {});
  }

  void _escucharPedidos() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idLocal', isEqualTo: uid)
        .where('tipo', isEqualTo: 'personalizado')
        .where('estado', whereIn: ['pendiente', 'aceptado'])
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _pedidos
              ..clear()
              ..addAll(
                snap.docs.where((d) => d['estado'] != 'entregado'),
              );
          });
        });
  }

  void _actualizarDistanciaMonto() {
    if (_localPos == null || _destinoTmp == null) return;

    final metros =
        const Distance().as(LengthUnit.Meter, _localPos!, _destinoTmp!);
    final distRedondeada = (metros / 100).round() / 10.0;

    int monto;
    if (distRedondeada <= 3) {
      monto = 80;
    } else if (distRedondeada <= 4.5) {
      monto = 100;
    } else if (distRedondeada <= 6) {
      monto = 150;
    } else if (distRedondeada <= 8.5) {
      monto = 200;
    } else {
      monto = 250;
    }

    setState(() {
      _distKm = distRedondeada;
      _montoTotal = monto;
    });
  }

  Future<void> _confirmarPedido() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null ||
        _localPos == null ||
        _destinoTmp == null ||
        _clienteCtl.text.trim().isEmpty ||
        _telefonoCtl.text.trim().isEmpty ||
        _cadetesElegidos.isEmpty ||
        _montoTotal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos.')),
      );
      return;
    }

    // Validación de distancia máxima
    final double distanciaKm = const Distance().as(LengthUnit.Kilometer, _localPos!, _destinoTmp!);
    final double distanciaRedondeada = (distanciaKm * 10).round() / 10.0;
    if (distanciaRedondeada > 8.5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El destino está demasiado lejos (más de 8.5 km)')),
      );
      return;
    }

    final docLocal =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final nombreLocal = docLocal.data()?['nombre'] ?? 'Local';

    const ganAdmin = 5;
    final montoCadete = _montoTotal! - ganAdmin;

    final pedidoData = {
      'tipo': 'personalizado',
      'estado': 'pendiente',
      'cliente': _clienteCtl.text.trim(),
      'telefonoCliente': _telefonoCtl.text.trim(),
      'descripcion': 'Pedido personalizado desde mapa',
      'ubicacionDestino': {
        'lat': _destinoTmp!.latitude,
        'lng': _destinoTmp!.longitude,
      },
      'ubicacionOrigen': {
        'lat': _localPos!.latitude,
        'lng': _localPos!.longitude,
      },
      'cadetesAsignados': _cadetesElegidos,
      'idLocal': uid,
      'localNombre': nombreLocal,
      'distancia_km': _distKm,
      'montoCadete': montoCadete,
      'montoGananciaAdmin': ganAdmin,
      'montoTotal': _montoTotal,
      'fechaCreado': Timestamp.now(),
      'asignado': null,
    };

    await FirebaseFirestore.instance.collection('pedidosEnCurso').add(pedidoData);

    if (!mounted) return;

    setState(() {
      _destinoTmp = null;
      _distKm = null;
      _montoTotal = null;
    });
    _clienteCtl.clear();
    _telefonoCtl.clear();
  }

  void _irAVerCadetes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final cadete = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerCadetesScreen(localId: uid),
      ),
    );

    if (cadete != null && cadete['id'] != null) {
      if (!_cadetesElegidos.contains(cadete['id'])) {
        setState(() {
          _cadetesElegidos.add(cadete['id']);
          _docsCadetesFav.add(cadete);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localPos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar pedido')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _localPos!,
              initialZoom: 15,
              onTap: (_, p) {
                setState(() => _destinoTmp = p);
                _actualizarDistanciaMonto();
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                userAgentPackageName: 'com.yendo.yendoo_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _localPos!,
                    width: 44,
                    height: 44,
                    child: Image.asset(
                      'assets/icono_local.png',
                      errorBuilder: (_, __, ___) =>
                          const Text('🏪', style: TextStyle(fontSize: 32)),
                    ),
                  ),
                ],
              ),
              MarkerLayer(
                markers: _pedidos.map((doc) {
                  final d = doc.data();
                  final LatLng pos = LatLng(
                    d['ubicacionDestino']['lat'],
                    d['ubicacionDestino']['lng'],
                  );
                  final estado = d['estado'];
                  return Marker(
                    point: pos,
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.location_on,
                      color: estado == 'pendiente' ? Colors.red : Colors.green,
                      size: 38,
                    ),
                  );
                }).toList(),
              ),
              if (_destinoTmp != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _destinoTmp!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.edit_location,
                          color: Colors.blue, size: 40),
                    ),
                  ],
                ),
            ],
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: _clienteCtl,
                        decoration: const InputDecoration(
                            labelText: 'Nombre del cliente'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _telefonoCtl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText:
                              'WhatsApp del cliente (con código de país)',
                          border: OutlineInputBorder(),
                          hintText: 'Ej: 59898123456',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _irAVerCadetes,
                        icon: const Icon(Icons.motorcycle),
                        label: const Text('Agregar cadete favorito'),
                      ),
                      const SizedBox(height: 12),
                      if (_docsCadetesFav.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: _docsCadetesFav.map((cad) {
                            final id = cad.id;
                            final nombre = cad['nombre'] ?? 'Cadete';
                            final sel = _cadetesElegidos.contains(id);
                            return FilterChip(
                              label: Text(nombre),
                              selected: sel,
                              onSelected: (v) {
                                setState(() {
                                  v
                                      ? _cadetesElegidos.add(id)
                                      : _cadetesElegidos.remove(id);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 12),
                      if (_distKm != null && _montoTotal != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Distancia: ${_distKm!.toStringAsFixed(1)} km\nPrecio total: \$$_montoTotal',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _confirmarPedido,
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmar pedido'),
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
