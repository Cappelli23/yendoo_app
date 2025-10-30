import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:audioplayers/audioplayers.dart';

class PedidosPersonalizadosScreen extends StatefulWidget {
  const PedidosPersonalizadosScreen({super.key});

  @override
  State<PedidosPersonalizadosScreen> createState() =>
      _PedidosPersonalizadosScreenState();
}

class _PedidosPersonalizadosScreenState
    extends State<PedidosPersonalizadosScreen> {
  final MapController _map = MapController();
  final Map<String, LatLng> _ubicacionesLocales = {};
  LatLng? _miPos;

  // ✅ Tipar snapshots para evitar casts innecesarios
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];

  String? _selId;
  LatLng? _selDestino;
  String? _selCliente;
  String? _selLocalId;
  String? _selEstado;
  double? _selMontoCadete;
  String? _selDireccionLocal;
  String? _selTelefonoCliente;
  String? _selNombreLocal;

  String? _uid;

  // ✅ Tipado del stream
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  final AudioPlayer _player = AudioPlayer();
  String? _ultimoIdVisto;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _cargarPosCadete();
    _escucharPedidos();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargarPosCadete() async {
    final uid = _uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final data = doc.data();
    if (data != null && data['ubicacion'] != null && mounted) {
      setState(() =>
          _miPos = LatLng(data['ubicacion']['lat'], data['ubicacion']['lng']));
    }
  }

  double _distKm(LatLng a, LatLng b) =>
      (const Distance().as(LengthUnit.Kilometer, a, b) * 10).round() / 10;

  double _precioDesdeDist(double km) {
    if (km <= 3) return 75;
    if (km <= 4.5) return 95;
    if (km <= 6) return 145;
    return 195;
  }

  double _cobroLocalDesdeDist(double km) {
    if (km <= 3) return 80;
    if (km <= 4.5) return 100;
    if (km <= 6) return 150;
    return 200;
  }

  void _escucharPedidos() {
    final uid = _uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('tipo', isEqualTo: 'personalizado')
        .where('cadetesAsignados', arrayContains: uid)
        .snapshots()
        .listen((snap) async {
      // 🔒 Visibilidad:
      // - pendiente → sólo si está libre (sin idCadete)
      // - aceptado → sólo si es mío (idCadete == uid)
      final docs = snap.docs.where((d) {
        final data = d.data();
        final estado = (data['estado'] ?? '').toString();
        final idCadete = (data['idCadete'] ?? '').toString();

        if (estado == 'pendiente') return idCadete.isEmpty;
        if (estado == 'aceptado') return idCadete == uid;
        return false;
      }).toList();

      // 🔔 Sonido sólo para nuevos pendientes libres
      final hayNuevoLibre = docs.any((d) {
        final isNew = d.id != _ultimoIdVisto;
        final data = d.data();
        final estado = (data['estado'] ?? '').toString();
        final idCadete = (data['idCadete'] ?? '').toString();
        return isNew && estado == 'pendiente' && idCadete.isEmpty;
      });
      if (hayNuevoLibre) {
        _ultimoIdVisto = docs.first.id;
        try {
          await _player.stop();
          await _player.play(AssetSource('sonidos/notificacion.mp3'));
        } catch (_) {}
      }

      // Cachear ubicaciones de locales de lo visible
      final faltan = docs
          .map((d) => d.data()['idLocal']?.toString() ?? '')
          .where((id) => id.isNotEmpty && !_ubicacionesLocales.containsKey(id))
          .toSet();

      for (final id in faltan) {
        final ldoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(id)
            .get();
        final ldata = ldoc.data();
        if (ldata != null && ldata['ubicacion'] != null) {
          _ubicacionesLocales[id] =
              LatLng(ldata['ubicacion']['lat'], ldata['ubicacion']['lng']);
        }
      }

      if (mounted) setState(() => _pedidos = docs);
    });
  }

  Future<void> _aceptar() async {
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null ||
        _selId == null ||
        _selLocalId == null ||
        _selDestino == null) {
      return;
    }

    final localPos = _ubicacionesLocales[_selLocalId]!;
    final distancia = _distKm(localPos, _selDestino!);
    final montoCadete = _precioDesdeDist(distancia);

    if (distancia > 8.5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El local está demasiado lejos (más de 8.5 km)')),
      );
      return;
    }

    // Limitar activos del cadete (aceptado)
    final activos = await FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('estado', isEqualTo: 'aceptado')
        .where('idCadete', isEqualTo: cadete.uid)
        .get();

    final mismos =
        activos.docs.where((d) => d.data()['idLocal'] == _selLocalId).length;
    final otrosLocales = activos.docs.map((d) => d.data()['idLocal']).toSet();

    if (otrosLocales.isNotEmpty && !otrosLocales.contains(_selLocalId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No puedes aceptar pedidos de otro local hasta terminar los actuales.'),
      ));
      return;
    }
    if (mismos >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ya aceptaste 3.')));
      return;
    }

    // ✅ Transacción anticolisión
    final ref =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc(_selId!);

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('El pedido ya no existe.');

        final data = snap.data() as Map<String, dynamic>;
        final estado = (data['estado'] ?? '').toString();
        final idCadeteActual = (data['idCadete'] ?? '').toString();
        if (estado != 'pendiente' || idCadeteActual.isNotEmpty) {
          throw Exception('El pedido ya fue aceptado por otro cadete.');
        }

        final telefonoCliente = (data['telefonoCliente'] ?? '').toString();

        txn.update(ref, {
          'estado': 'aceptado',
          'idCadete': cadete.uid,
          'fechaAceptado': FieldValue.serverTimestamp(),
          'asignado': {
            'cadeteId': cadete.uid,
            'cadeteNombre': cadete.displayName ?? 'Cadete'
          },
          'distancia_km': distancia,
          'montoCadete': montoCadete,
          if (telefonoCliente.isNotEmpty) 'telefonoCliente': telefonoCliente,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pedido aceptado')));
      _limpiarSel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _entregar() async {
    if (_selId == null || _selLocalId == null || _selDestino == null) return;

    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    final km = _distKm(_ubicacionesLocales[_selLocalId]!, _selDestino!);
    final precioLocal = _cobroLocalDesdeDist(km);
    final precioCadete = _precioDesdeDist(km);
    final now = Timestamp.now();
    final batch = FirebaseFirestore.instance.batch();

    final pedidoEnCursoRef =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc(_selId!);
    final pedidoRef =
        FirebaseFirestore.instance.collection('pedidos').doc(_selId!);

    final pedidoEnCursoSnap = await pedidoEnCursoRef.get();
    final pedidoData = pedidoEnCursoSnap.data() ?? {};

    batch.set(pedidoRef, {
      ...pedidoData,
      'estado': 'entregado',
      'fechaEntregado': now,
      'distancia_km': km,
      'montoTotal': precioLocal,
      'montoCadete': precioCadete,
    });

    batch.delete(pedidoEnCursoRef);

    final localData = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(_selLocalId)
        .get();
    final cadeteData = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(cadete.uid)
        .get();

    final nombreLocal = localData.data()?['nombre'] ?? 'Local';
    final nombreCadete = cadeteData.data()?['nombre'] ?? 'Cadete';
    final idCadete = cadeteData.data()?['id'] ?? cadete.uid;

    final histLocalRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(_selLocalId)
        .collection('historial')
        .doc();
    batch.set(histLocalRef, {
      'cliente': _selCliente ?? 'Cliente',
      'distancia': km,
      'montoTotal': precioLocal,
      'fecha': now,
      'estado': 'entregado',
      'cadeteNombre': nombreCadete,
      'idCadete': idCadete,
    });

    final histCadeteRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(cadete.uid)
        .collection('historial')
        .doc();
    batch.set(histCadeteRef, {
      'cliente': _selCliente ?? 'Cliente',
      'distancia': km,
      'montoCadete': precioCadete,
      'fecha': now,
      'estado': 'entregado',
      'localNombre': nombreLocal,
    });

    await batch.commit();

    setState(() {
      _pedidos.removeWhere((p) => p.id == _selId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pedido entregado')));
      _limpiarSel();
    }
  }

  void _limpiarSel() => setState(() {
        _selId = _selCliente = _selLocalId = _selEstado = null;
        _selDestino = null;
        _selMontoCadete = null;
        _selDireccionLocal = null;
        _selTelefonoCliente = null;
        _selNombreLocal = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_miPos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos personalizados')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _miPos!,
              initialZoom: 14,
              onTap: (_, __) => _limpiarSel(),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                userAgentPackageName: 'com.yendo.yendoo_app',
              ),
              MarkerLayer(
                markers: _ubicacionesLocales.entries
                    .map((e) => Marker(
                          point: e.value,
                          width: 36,
                          height: 36,
                          child: Image.asset('assets/icono_local.png',
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.store)),
                        ))
                    .toList(),
              ),
              MarkerLayer(
                markers: _pedidos.map((p) {
                  final data = p.data(); // ✅ sin cast
                  final destino = LatLng(data['ubicacionDestino']['lat'],
                      data['ubicacionDestino']['lng']);
                  final estado = data['estado'];
                  final esMio = data['idCadete'] == _uid;

                  return Marker(
                    point: destino,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () async {
                        final localPos = _ubicacionesLocales[data['idLocal']]!;
                        final dist = _distKm(localPos, destino);
                        final docLoc = await FirebaseFirestore.instance
                            .collection('usuarios')
                            .doc(data['idLocal'])
                            .get();
                        final direccionLoc = docLoc.data()?['direccion'] ?? '';
                        final nombreLoc = docLoc.data()?['nombre'] ?? '';
                        final telefonoCliente = data['telefonoCliente'] ?? '';
                        if (!mounted) return;
                        setState(() {
                          _selId = p.id;
                          _selDestino = destino;
                          _selCliente = data['cliente'] ?? '';
                          _selMontoCadete = _precioDesdeDist(dist);
                          _selLocalId = data['idLocal'];
                          _selEstado = estado;
                          _selDireccionLocal = direccionLoc;
                          _selNombreLocal = nombreLoc;
                          _selTelefonoCliente = telefonoCliente;
                        });
                      },
                      child: Icon(
                        Icons.location_on,
                        color: estado == 'pendiente'
                            ? Colors.orange
                            : esMio
                                ? Colors.green
                                : Colors.grey,
                        size: 40,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          if (_selId != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selNombreLocal != null)
                      Text('Local: $_selNombreLocal'),
                    if (_selCliente != null) Text('Cliente: $_selCliente'),
                    if (_selDireccionLocal != null &&
                        _selDireccionLocal!.isNotEmpty)
                      Text('Dirección: $_selDireccionLocal'),
                    if (_selMontoCadete != null)
                      Text(
                          'Pago al cadete: \$${_selMontoCadete!.toStringAsFixed(0)}'),
                    if (_selEstado == 'aceptado' &&
                        _selTelefonoCliente != null &&
                        _selTelefonoCliente!.isNotEmpty)
                      SelectableText('Teléfono cliente: $_selTelefonoCliente'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (_selEstado == 'pendiente')
                          ElevatedButton.icon(
                            onPressed: _aceptar,
                            icon: const Icon(Icons.check),
                            label: const Text('Aceptar'),
                          ),
                        if (_selEstado == 'aceptado')
                          ElevatedButton.icon(
                            onPressed: _entregar,
                            icon: const Icon(Icons.local_shipping),
                            label: const Text('Entregar'),
                          ),
                        OutlinedButton.icon(
                          onPressed: _limpiarSel,
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
