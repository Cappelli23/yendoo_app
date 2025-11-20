import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

class PedidosPendientesScreen extends StatefulWidget {
  const PedidosPendientesScreen({super.key});

  @override
  State<PedidosPendientesScreen> createState() =>
      _PedidosPendientesScreenState();
}

class _PedidosPendientesScreenState extends State<PedidosPendientesScreen> {
  final MapController mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  LatLng? _currentPosition;

  // selección actual
  String? _selectedPedidoId;
  LatLng? _selectedDestino;
  String? _selectedCliente;
  String? _selectedLocalId;
  String? _selectedNombreLocal;
  String? _selectedDireccionLocal;

  // datos en memoria
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];
  final Map<String, LatLng> _ubicacionesLocales = {};
  StreamSubscription<Position>? _positionSubscription;

  // para sonido de nuevos pendientes
  List<String> _ultimosIds = [];

  static const _estadosVisibles = <String>[
    'pendiente',
    'aceptado',
    'listo',
    'entregado', // legacy
    'entregado_al_cadete',
  ];

  double _kmEntre(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Kilometer, a, b);

  Map<String, double> _calcularPrecios(double km) {
    if (km <= 3.0) return {'local': 80, 'cadete': 75};
    if (km <= 4.5) return {'local': 100, 'cadete': 95};
    if (km <= 6.0) return {'local': 150, 'cadete': 145};
    if (km <= 8.5) return {'local': 200, 'cadete': 195};
    return {'local': 0, 'cadete': 0};
  }

  @override
  void initState() {
    super.initState();
    _iniciarUbicacionEnTiempoReal();
    _escucharPedidos();
  }

  Future<void> _iniciarUbicacionEnTiempoReal() async {
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    if (!await Geolocator.isLocationServiceEnabled()) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));

    _positionSubscription = Geolocator.getPositionStream().listen((p) async {
      // actualizar ubicación del cadete en usuarios/{uid}
      try {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(cadete.uid)
            .update({
          'ubicacion': {'lat': p.latitude, 'lng': p.longitude}
        });
      } catch (_) {}
      if (mounted) {
        setState(() => _currentPosition = LatLng(p.latitude, p.longitude));
      }
    });
  }

  void _escucharPedidos() {
    FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('estado', whereIn: _estadosVisibles)
        .where('tipo', isEqualTo: 'normal')
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Sonar solo con nuevos "pendiente" sin cadete
      final nuevosPendientes = snap.docs.where((doc) {
        final isNew = !_ultimosIds.contains(doc.id);
        final d = doc.data();
        final estado = (d['estado'] ?? '').toString();
        final idCadete = (d['idCadete'] ?? '').toString();
        return isNew && estado == 'pendiente' && idCadete.isEmpty;
      }).toList();

      if (nuevosPendientes.isNotEmpty) {
        try {
          await _audioPlayer.stop();
          await _audioPlayer.play(AssetSource('sonidos/notificacion.mp3'));
        } catch (_) {}
      }

      // FILTRO:
      // - Mostrar PENDIENTES sin cadete
      // - Mostrar pedidos ASIGNADOS al cadete actual (aceptado/listo/entregado_al_cadete/entregado)
      final filtrados = snap.docs.where((doc) {
        final d = doc.data();
        final estado = (d['estado'] ?? '').toString();
        final idCadete = (d['idCadete'] ?? '').toString();
        final esMio = idCadete == uid;

        if (estado == 'pendiente') {
          // Unassigned: campo vacío o no seteado
          return idCadete.isEmpty;
        }
        // Resto de estados visibles: solo si son míos
        return esMio;
      }).toList();

      if (!mounted) return;

      setState(() {
        _pedidos = filtrados;
        _ultimosIds = snap.docs.map((e) => e.id).toList();

        // Si el seleccionado ya no está en la lista filtrada, cerramos panel
        if (_selectedPedidoId != null &&
            !_pedidos.any((d) => d.id == _selectedPedidoId)) {
          _selectedPedidoId = null;
          _selectedDestino = null;
          _selectedCliente = null;
          _selectedLocalId = null;
          _selectedNombreLocal = null;
          _selectedDireccionLocal = null;
        }
      });

      // cachear ubicación de locales
      for (final ped in filtrados) {
        final d = ped.data();
        final idLocal = (d['idLocal'] ?? '').toString();
        if (idLocal.isEmpty) continue;
        if (!_ubicacionesLocales.containsKey(idLocal)) {
          final docLoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(idLocal)
              .get();
          final u = docLoc.data()?['ubicacion'];
          if (u is Map && u['lat'] != null && u['lng'] != null) {
            _ubicacionesLocales[idLocal] = LatLng(
                (u['lat'] as num).toDouble(), (u['lng'] as num).toDouble());
          }
        }
      }
    });
  }

  Future<void> _aceptarPedido() async {
    if (_selectedPedidoId == null || _selectedLocalId == null) return;

    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    // origen local para estimaciones
    double? distancia;
    double? montoCadete;
    final origenLocal = _ubicacionesLocales[_selectedLocalId!];
    if (origenLocal != null && _selectedDestino != null) {
      distancia = _kmEntre(origenLocal, _selectedDestino!);
      final precios = _calcularPrecios(distancia);
      montoCadete = precios['cadete'];
    }

    // Distancia máxima cadete-local
    if (_currentPosition != null && origenLocal != null) {
      final distanciaCadeteLocal = _kmEntre(_currentPosition!, origenLocal);
      if (distanciaCadeteLocal > 8.5) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El local está demasiado lejos (más de 8.5 km)')),
        );
        return;
      }
    }

    // Limitar activos del cadete (aceptado o entregado_al_cadete)
    final activos = await FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idCadete', isEqualTo: cadete.uid)
        .where('estado', whereIn: ['aceptado', 'entregado_al_cadete']).get();

    final mismos =
        activos.docs.where((d) => d['idLocal'] == _selectedLocalId).length;
    final otrosLocales = activos.docs.map((d) => d['idLocal']).toSet();

    if (otrosLocales.isNotEmpty && !otrosLocales.contains(_selectedLocalId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No puedes aceptar pedidos de otro local hasta terminar los actuales.'),
      ));
      return;
    }
    if (mismos >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya aceptaste 3 pedidos de este local.')),
      );
      return;
    }

    // Transacción: asignar solo si sigue libre y pendiente
    final ref = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .doc(_selectedPedidoId!);

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) {
          throw Exception('El pedido ya no existe.');
        }
        final data = snap.data() as Map<String, dynamic>;

        final estado = (data['estado'] ?? '').toString();
        final idCadeteActual = (data['idCadete'] ?? '').toString();

        if (estado != 'pendiente' || idCadeteActual.isNotEmpty) {
          // ya lo tomó otro
          throw Exception('El pedido ya fue aceptado por otro cadete.');
        }

        final telefonoCliente = (data['telefonoCliente'] ?? '').toString();

        txn.update(ref, {
          'estado': 'aceptado',
          'idCadete': cadete.uid,
          'fechaAceptado': FieldValue.serverTimestamp(),
          'asignado': {
            'cadeteId': cadete.uid,
            'cadeteNombre': cadete.displayName ?? 'Cadete',
          },
          if (distancia != null) 'distancia_km': distancia,
          if (montoCadete != null) 'montoCadete': montoCadete,
          if (telefonoCliente.isNotEmpty) 'telefonoCliente': telefonoCliente,
        });
      });

      if (!mounted) return;
      setState(() => _selectedPedidoId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido aceptado ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _entregarPedido(
    String idPedido,
    String uidLocal,
    LatLng destino,
  ) async {
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    // origen local
    LatLng? origenLocal = _ubicacionesLocales[uidLocal];
    if (origenLocal == null) {
      final docLoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidLocal)
          .get();
      final u = docLoc.data()?['ubicacion'];
      if (u is Map && u['lat'] != null && u['lng'] != null) {
        origenLocal =
            LatLng((u['lat'] as num).toDouble(), (u['lng'] as num).toDouble());
        _ubicacionesLocales[uidLocal] = origenLocal;
      }
    }
    if (origenLocal == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo obtener la ubicación del local.')),
      );
      return;
    }

    final km = _kmEntre(origenLocal, destino);
    final precios = _calcularPrecios(km);
    final precioLocal = precios['local'];
    final precioCadete = precios['cadete'];
    final now = Timestamp.now();
    final batch = FirebaseFirestore.instance.batch();

    final pedidoEnCursoRef =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc(idPedido);
    final pedidoRef =
        FirebaseFirestore.instance.collection('pedidos').doc(idPedido);

    final pedidoEnCursoSnap = await pedidoEnCursoRef.get();
    final pedidoData = pedidoEnCursoSnap.data() ?? {};

    // historial general
    batch.set(pedidoRef, {
      ...pedidoData,
      'estado': 'entregado',
      'fechaEntregado': now,
      'distancia_km': km,
      'montoTotal': precioLocal,
      'montoCadete': precioCadete,
    });

    // eliminar del mapa
    batch.delete(pedidoEnCursoRef);

    // historiales individuales
    final localData = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uidLocal)
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
        .doc(uidLocal)
        .collection('historial')
        .doc();
    batch.set(histLocalRef, {
      'cliente': _selectedCliente ?? 'Cliente',
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
      'cliente': _selectedCliente ?? 'Cliente',
      'distancia': km,
      'montoCadete': precioCadete,
      'fecha': now,
      'estado': 'entregado',
      'localNombre': nombreLocal,
    });

    await batch.commit();

    if (!mounted) return;
    setState(() => _selectedPedidoId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pedido entregado ✅')),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<String> _nombreLocal(String idLocal) async {
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idLocal)
        .get();
    return (doc.data()?['nombre'] ?? 'Local').toString();
  }

  bool _puedeEntregar(Map<String, dynamic> d, String? uidCadete) {
    final estado = (d['estado'] ?? '').toString();
    final asignado = (d['idCadete'] ?? '').toString();
    final esMio = uidCadete != null && asignado == uidCadete;
    final localEntrego =
        estado == 'entregado_al_cadete' || estado == 'entregado';
    return esMio && localEntrego;
  }

  // Chip de pago para el cadete
  String _labelMetodo(String v) {
    switch (v) {
      case 'debito':
        return 'débito';
      case 'efectivo':
        return 'efectivo';
      case 'transferencia':
        return 'transferencia';
      case 'credito':
        return 'crédito';
      case 'qr':
        return 'QR';
      default:
        return v;
    }
  }

  String _labelVia(String? v) {
    switch (v) {
      case 'pos':
        return 'POS';
      case 'link':
        return 'link';
      default:
        return '';
    }
  }

  Widget _pagoChipParaCadete(BuildContext context, Map<String, dynamic> data,
      {bool soloSiEsDebito = false}) {
    String? metodo = data['pagoMetodo'] as String?;
    num? monto = data['pagoMonto'] as num?;
    String? via = data['pagoVia'] as String?;

    final pago = (data['pago'] as Map?)?.cast<String, dynamic>();
    metodo ??= pago?['metodo'] as String?;
    monto ??= pago?['monto'] as num?;
    via ??= pago?['via'] as String?;

    if (metodo == null || monto == null) {
      final resumen = data['pagoResumen'];
      if (resumen is String && resumen.trim().isNotEmpty) {
        final chipColor = Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(resumen,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      }
      return const SizedBox.shrink();
    }

    if (soloSiEsDebito && metodo != 'debito') return const SizedBox.shrink();

    final f = NumberFormat.currency(locale: 'es_UY', symbol: r'$');
    final metodoTxt = _labelMetodo(metodo);
    final viaTxt = _labelVia(via);
    final texto = viaTxt.isNotEmpty
        ? '${f.format(monto)} ($metodoTxt · $viaTxt)'
        : '${f.format(monto)} ($metodoTxt)';

    IconData icono() {
      if (metodo == 'debito') {
        if (via == 'pos') return Icons.point_of_sale;
        if (via == 'link') return Icons.link;
        return Icons.credit_card;
      }
      switch (metodo) {
        case 'efectivo':
          return Icons.attach_money;
        case 'transferencia':
          return Icons.swap_horiz;
        case 'credito':
          return Icons.credit_card;
        case 'qr':
          return Icons.qr_code_scanner;
        default:
          return Icons.payments_outlined;
      }
    }

    final cs = Theme.of(context).colorScheme;
    final chipColor = cs.primaryContainer.withValues(alpha: 0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono(), size: 18),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cadete = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Mapa
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition!,
                    initialZoom: 14,
                    onTap: (_, __) => setState(() => _selectedPedidoId = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                      userAgentPackageName: 'com.yendo.yendoo_app',
                    ),
                    MarkerLayer(
                      markers: [
                        // pedidos (ya vienen filtrados)
                        ..._pedidos.map((p) {
                          final d = p.data();
                          // ub destino
                          final uDest = d['ubicacionDestino'];
                          double? lat, lng;
                          if (uDest is Map) {
                            lat = (uDest['lat'] as num?)?.toDouble();
                            lng = (uDest['lng'] as num?)?.toDouble();
                          }
                          if (lat == null || lng == null) {
                            // no marker si faltan coords
                            return const Marker(
                              point: LatLng(0, 0),
                              width: 0,
                              height: 0,
                              child: SizedBox.shrink(),
                            );
                          }
                          final pos = LatLng(lat, lng);

                          final esMio =
                              (d['idCadete'] ?? '') == (cadete?.uid ?? '');
                          final color = esMio ? Colors.green : Colors.red;

                          return Marker(
                            point: pos,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () async {
                                final estado = (d['estado'] ?? '').toString();
                                if (_estadosVisibles.contains(estado)) {
                                  final idLocal =
                                      (d['idLocal'] ?? '').toString();
                                  final nomLoc = await _nombreLocal(idLocal);
                                  final docLoc = await FirebaseFirestore
                                      .instance
                                      .collection('usuarios')
                                      .doc(idLocal)
                                      .get();
                                  final direccionLoc =
                                      (docLoc.data()?['direccion'] ?? '')
                                          .toString();
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedPedidoId = p.id;
                                    _selectedDestino = pos;
                                    _selectedCliente =
                                        (d['cliente'] ?? '').toString();
                                    _selectedLocalId = idLocal;
                                    _selectedNombreLocal = nomLoc;
                                    _selectedDireccionLocal = direccionLoc;
                                  });
                                }
                              },
                              child: Icon(Icons.location_on,
                                  color: color, size: 40),
                            ),
                          );
                        }).where((m) => m.width != 0),
                        // locales
                        ..._ubicacionesLocales.values.map(
                          (pos) => Marker(
                            point: pos,
                            width: 30,
                            height: 30,
                            child: Image.asset('assets/icono_local.png'),
                          ),
                        ),
                        // cadete
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.motorcycle,
                                color: Colors.blue),
                          ),
                      ],
                    ),
                  ],
                ),

                // panel inferior (protegido y sin overflows)
                if (_selectedPedidoId != null &&
                    _selectedDestino != null &&
                    _selectedLocalId != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.white,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Builder(
                            builder: (_) {
                              final pedidoSel = _pedidos.firstWhereOrNull(
                                  (doc) => doc.id == _selectedPedidoId);
                              if (pedidoSel == null) {
                                return const SizedBox.shrink();
                              }
                              final d = pedidoSel.data();
                              final estado = (d['estado'] ?? '').toString();
                              final idCadete = (d['idCadete'] ?? '').toString();
                              final telefono =
                                  (d['telefonoCliente'] ?? '').toString();

                              final esMio = idCadete == (cadete?.uid ?? '');
                              final puedeEntregar =
                                  _puedeEntregar(d, cadete?.uid);

                              Widget buildCallBtn() {
                                if (!esMio || telefono.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final telFmt =
                                    telefono.replaceAll(RegExp(r'\D'), '');
                                final uri = Uri.parse('tel:$telFmt');
                                return SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri,
                                            mode:
                                                LaunchMode.externalApplication);
                                      }
                                    },
                                    icon: const Icon(Icons.phone,
                                        color: Colors.blue),
                                    label: const Text('📞 Llamar al cliente'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade50,
                                      foregroundColor: Colors.black87,
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Cliente: ${_selectedCliente ?? ''}'),
                                  Text('Local: ${_selectedNombreLocal ?? ''}'),
                                  if ((_selectedDireccionLocal ?? '')
                                      .isNotEmpty)
                                    Text('Dirección: $_selectedDireccionLocal'),

                                  // Chip pago cliente
                                  const SizedBox(height: 6),
                                  _pagoChipParaCadete(context, d),

                                  Builder(builder: (context) {
                                    final origen =
                                        _ubicacionesLocales[_selectedLocalId!];
                                    if (origen == null ||
                                        _selectedDestino == null) {
                                      return const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text('Calculando pago…'),
                                      );
                                    }
                                    final cadetePago = _calcularPrecios(
                                      _kmEntre(origen, _selectedDestino!),
                                    )['cadete']
                                        ?.toStringAsFixed(0);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child:
                                          Text('Pago al cadete: \$$cadetePago'),
                                    );
                                  }),
                                  const SizedBox(height: 10),

                                  // Acciones
                                  if (estado == 'pendiente' &&
                                      idCadete.isEmpty) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        SizedBox(
                                          height: 44,
                                          child: ElevatedButton.icon(
                                            onPressed: _aceptarPedido,
                                            icon: const Icon(Icons.check),
                                            label: const Text('Aceptar'),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: OutlinedButton.icon(
                                            onPressed: () => setState(
                                                () => _selectedPedidoId = null),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Cancelar'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (puedeEntregar) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        SizedBox(
                                          height: 44,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _entregarPedido(
                                              _selectedPedidoId!,
                                              _selectedLocalId!,
                                              _selectedDestino!,
                                            ),
                                            icon: const Icon(Icons.done_all),
                                            label: const Text('Entregar'),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: OutlinedButton.icon(
                                            onPressed: () => setState(
                                                () => _selectedPedidoId = null),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Cancelar'),
                                          ),
                                        ),
                                        buildCallBtn(),
                                      ],
                                    ),
                                  ] else ...[
                                    if (esMio)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 8),
                                        child: Text(
                                          'Esperando que el local te entregue el pedido…',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        buildCallBtn(),
                                        SizedBox(
                                          height: 44,
                                          child: OutlinedButton.icon(
                                            onPressed: () => setState(
                                                () => _selectedPedidoId = null),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Cerrar'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
