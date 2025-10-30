import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GenerarPedidoScreen extends StatefulWidget {
  const GenerarPedidoScreen({super.key});

  @override
  State<GenerarPedidoScreen> createState() => _GenerarPedidoScreenState();
}

class _GenerarPedidoScreenState extends State<GenerarPedidoScreen> {
  /* ───────── MAPA ───────── */
  final MapController _map = MapController();

  /* ───────── Estado propio de creación ───────── */
  LatLng? _localPos;
  LatLng? _destinoTmp; // punto mientras seleccionás
  final TextEditingController _clienteCtl = TextEditingController();
  final TextEditingController _telefonoCtl = TextEditingController();
  bool _seleccionando = false;
  double? _distKm; // precisión 0.1 km
  int? _montoTotal; // 80-100-150-200

  /* ───────── Pedidos en vivo del local ───────── */
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /* ───────── ciclo ───────── */
  @override
  void initState() {
    super.initState();
    _cargarLocal().then((_) => _escucharPedidos());
  }

  @override
  void dispose() {
    _clienteCtl.dispose();
    _telefonoCtl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  /* ───────── Carga ubicación fija del local ───────── */
  Future<void> _cargarLocal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final data = doc.data();
    if (!mounted || data?['ubicacion'] == null) return;

    setState(() {
      _localPos = LatLng(data!['ubicacion']['lat'], data['ubicacion']['lng']);
    });
  }

  /* ───────── Listener en vivo de pedidos del local ───────── */
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
        });
  }

  /* ───────── Distancia y monto ───────── */
  void _actualizarMontos() {
    if (_localPos == null || _destinoTmp == null) return;

    final metros =
        const Distance().as(LengthUnit.Meter, _localPos!, _destinoTmp!);
    final distRed = (metros / 100).round() / 10.0; // 0.1 km

    int montoCad;
    if (distRed <= 3) {
      montoCad = 75;
    } else if (distRed <= 4.5) {
      montoCad = 95;
    } else if (distRed <= 6) {
      montoCad = 145;
    } else {
      montoCad = 195;
    }

    const ganAdmin = 5;
    setState(() {
      _distKm = distRed;
      _montoTotal = montoCad + ganAdmin;
    });
  }

  /* ───────── Guardado Firestore ───────── */
  Future<void> _guardarPedido() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _destinoTmp == null) return;

    final cliente = _clienteCtl.text.trim();
    final telefono = _telefonoCtl.text.trim();
    if (cliente.isEmpty || telefono.isEmpty || _montoTotal == null || _distKm == null) return;

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

    const ganAdmin = 5;
    final montoCad = _montoTotal! - ganAdmin;

    await FirebaseFirestore.instance.collection('pedidosEnCurso').add({
      'idLocal': uid,
      'cliente': cliente,
      'telefonoCliente': telefono,
      'estado': 'pendiente',
      'tipo': 'normal',
      'fechaCreado': Timestamp.now(),
      'ubicacionOrigen': {
        'lat': _localPos!.latitude,
        'lng': _localPos!.longitude,
      },
      'ubicacionDestino': {
        'lat': _destinoTmp!.latitude,
        'lng': _destinoTmp!.longitude,
      },
      'distancia_km': _distKm,
      'montoCadete': montoCad,
      'montoGananciaAdmin': ganAdmin,
      'montoTotal': _montoTotal,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pedido generado con éxito.')),
    );

    // reset UI, pero los markers del stream permanecerán
    setState(() {
      _destinoTmp = null;
      _clienteCtl.clear();
      _telefonoCtl.clear();
      _seleccionando = false;
      _distKm = null;
      _montoTotal = null;
    });
  }

  /* ───────── UI ───────── */
  @override
  Widget build(BuildContext context) {
    if (_localPos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Generar pedido')),
      body: Stack(
        children: [
          /* ---------- MAPA ---------- */
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _localPos!,
              initialZoom: 14,
              onLongPress: (_, p) {
                setState(() {
                  _destinoTmp = p;
                  _seleccionando = true;
                });
                _actualizarMontos();
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                userAgentPackageName: 'com.yendo.yendoo_app',
              ),

              /* --- marcador LOCAL (icono o emoji) --- */
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

              /* --- marcadores de todos los PEDIDOS actuales --- */
              MarkerLayer(
                markers: _pedidos.map((doc) {
                  final d = doc.data();
                  final LatLng pos = LatLng(
                    d['ubicacionDestino']['lat'],
                    d['ubicacionDestino']['lng'],
                  );
                  final estado = d['estado']; // pendiente | aceptado
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

              /* --- marcador TEMPORAL mientras selecciono --- */
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

          /* ---------- PANEL inferior de creación ---------- */
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
                        hintText: 'Ej: 59898123456',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_montoTotal != null && _distKm != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Distancia: ${_distKm!.toStringAsFixed(1)} km  –  '
                          'Monto total: \$$_montoTotal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _guardarPedido,
                          icon: const Icon(Icons.check),
                          label: const Text('Confirmar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _destinoTmp = null;
                              _seleccionando = false;
                              _distKm = null;
                              _montoTotal = null;
                            });
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
