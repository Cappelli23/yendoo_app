// lib/screens/cadete/pedidos_personalizados_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:url_launcher/url_launcher.dart';

class PedidosPersonalizadosScreen extends StatefulWidget {
  const PedidosPersonalizadosScreen({super.key});

  @override
  State<PedidosPersonalizadosScreen> createState() =>
      _PedidosPersonalizadosScreenState();
}

class _PedidosPersonalizadosScreenState
    extends State<PedidosPersonalizadosScreen> {
  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapStyleLoaded = false;

  final Map<maplibre.Circle, QueryDocumentSnapshot<Map<String, dynamic>>>
      _circlePedidos = {};
  final List<maplibre.Circle> _circles = [];
  final List<maplibre.Symbol> _symbols = [];

  final Map<String, LatLng> _ubicacionesLocales = {};
  LatLng? _miPos;

  // ✅ Tipar snapshots
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];

  // Selección
  String? _selId;
  LatLng? _selDestino;
  String? _selCliente;
  String? _selLocalId;
  String? _selEstado;
  int? _selMontoCadete;
  String? _selDireccionLocal;
  String? _selTelefonoCliente;
  String? _selTelefonoLocal;
  String? _selNombreLocal;

  String? _uid;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  final AudioPlayer _player = AudioPlayer();
  String? _ultimoIdVisto;

  // ✅ para amarillo: local activo
  String? _miLocalActivoId;

  // ✅ anti doble tap entrega
  bool _entregando = false;

  // Estados útiles
  static const _estadoPendiente = 'pendiente';
  static const _estadoAceptado = 'aceptado';
  static const _estadoEntregadoAlCadete = 'entregado_al_cadete';
  static const _estadoListo = 'listo';
  static const _estadoEntregadoLegacy = 'entregado';

  // ✅ Regla única: total = cadete + 5
  static const int _gananciaYendo = 5;

  static const String _mapStyle =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=jKh3fbz0oFEuYjlFsboz';

  Future<void> _irAZoom(double zoom) async {
    await _mapLibreController?.animateCamera(
      maplibre.CameraUpdate.zoomTo(zoom),
    );
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ✅ fuerza distancia mostrable a 1 decimal: 1.27 -> 1.3, 1 -> 1.0
  double _to1Decimal(double km) => double.parse(km.toStringAsFixed(1));

  double? _to1DecimalNullable(dynamic v) {
    final d = _toDouble(v);
    if (d == null) return null;
    return _to1Decimal(d);
  }

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
    _player.dispose();
    super.dispose();
  }

  Future<void> _cargarPosCadete() async {
    final uid = _uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final data = doc.data();

    final u = data?['ubicacion'];
    if (u is Map && u['lat'] != null && u['lng'] != null && mounted) {
      setState(() {
        _miPos = LatLng(
          (u['lat'] as num).toDouble(),
          (u['lng'] as num).toDouble(),
        );
      });
      unawaited(_dibujarMarkersMapLibre());
    }
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
      if (!mounted) return;

      // ✅ Determinar "mi local activo" para amarillo
      String? miLocal;
      for (final doc in snap.docs) {
        final data = doc.data();
        final estado = (data['estado'] ?? '').toString();
        final idCadete = (data['idCadete'] ?? '').toString();
        if (idCadete == uid &&
            (estado == _estadoAceptado ||
                estado == _estadoListo ||
                estado == _estadoEntregadoAlCadete)) {
          final idLocal = (data['idLocal'] ?? '').toString();
          if (idLocal.isNotEmpty) {
            miLocal = idLocal;
            break;
          }
        }
      }

      // Visibilidad:
      // - pendiente -> solo si está libre (sin idCadete)
      // - aceptado/entregado_al_cadete/listo/(legacy entregado) -> solo si es mío
      final docs = snap.docs.where((d) {
        final data = d.data();
        final estado = (data['estado'] ?? '').toString();
        final idCadete = (data['idCadete'] ?? '').toString();

        if (estado == _estadoPendiente) {
          return idCadete.isEmpty;
        }

        if (estado == _estadoAceptado ||
            estado == _estadoEntregadoAlCadete ||
            estado == _estadoListo ||
            estado == _estadoEntregadoLegacy) {
          return idCadete == uid;
        }

        return false;
      }).toList();

      // Sonido solo para nuevos pendientes libres
      final hayNuevoLibre = docs.any((d) {
        final isNew = d.id != _ultimoIdVisto;
        final data = d.data();
        final estado = (data['estado'] ?? '').toString();
        final idCadete = (data['idCadete'] ?? '').toString();
        return isNew && estado == _estadoPendiente && idCadete.isEmpty;
      });

      if (hayNuevoLibre && docs.isNotEmpty) {
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
        final u = ldata?['ubicacion'];
        if (u is Map && u['lat'] != null && u['lng'] != null) {
          _ubicacionesLocales[id] = LatLng(
            (u['lat'] as num).toDouble(),
            (u['lng'] as num).toDouble(),
          );
        }
      }

      setState(() {
        _pedidos = docs;
        _miLocalActivoId = miLocal;

        // si el seleccionado ya no está visible, limpiamos panel
        if (_selId != null && !_pedidos.any((p) => p.id == _selId)) {
          _limpiarSel();
        }
      });

      unawaited(_dibujarMarkersMapLibre());
    });
  }

  Future<void> _aceptar() async {
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null || _selId == null) {
      return;
    }

    // ✅ nombre real cadete desde Firestore
    String nombreCadete = 'Cadete';
    try {
      final cadeteDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(cadete.uid)
          .get();
      final n = (cadeteDoc.data()?['nombre'] ?? '').toString().trim();
      if (n.isNotEmpty) {
        nombreCadete = n;
      }
    } catch (_) {}

    // Limitar activos del cadete (aceptado o entregado_al_cadete)
    final activos = await FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idCadete', isEqualTo: cadete.uid)
        .where('estado',
            whereIn: [_estadoAceptado, _estadoEntregadoAlCadete]).get();

    final mismos = activos.docs
        .where((d) => d.data()['idLocal']?.toString() == _selLocalId)
        .length;

    final otrosLocales =
        activos.docs.map((d) => d.data()['idLocal']?.toString() ?? '').toSet();

    if (otrosLocales.isNotEmpty &&
        _selLocalId != null &&
        !otrosLocales.contains(_selLocalId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No puedes aceptar pedidos de otro local hasta terminar los actuales.'),
      ));
      return;
    }

    // ✅ hasta 4 del mismo local
    if (mismos >= 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ya aceptaste 4.')));
      return;
    }

    final ref =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc(_selId!);

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) {
          throw Exception('El pedido ya no existe.');
        }

        final data = snap.data() as Map<String, dynamic>;
        final estado = (data['estado'] ?? '').toString();
        final idCadeteActual = (data['idCadete'] ?? '').toString();

        if (estado != _estadoPendiente || idCadeteActual.isNotEmpty) {
          throw Exception('El pedido ya fue aceptado por otro cadete.');
        }

        // ✅ EXACTITUD: usar lo guardado por el Local (NO recalcular)
        final kmMost = _to1DecimalNullable(data['distanciaKmMostrable']);
        final kmReal = _toDouble(data['distanciaKmReal']) ??
            _toDouble(data['distancia_km']);

        int? montoCad = _toInt(data['montoCadete']);
        int? montoTot = _toInt(data['montoTotal']);

        // ✅ Deducción por regla fija +/-5
        if (montoCad == null && montoTot != null) {
          montoCad = montoTot - _gananciaYendo;
        }
        if (montoTot == null && montoCad != null) {
          montoTot = montoCad + _gananciaYendo;
        }

        // ✅ Si falta distanciaMostrable o montos => pedido viejo mal generado, NO aceptar
        if (kmMost == null || montoCad == null || montoTot == null) {
          throw Exception(
            'Este pedido no tiene distancia/montos guardados (versión vieja). Eliminá y generá uno nuevo.',
          );
        }

        final telefonoCliente = (data['telefonoCliente'] ?? '').toString();

        txn.update(ref, {
          'estado': _estadoAceptado,
          'idCadete': cadete.uid,
          'fechaAceptado': FieldValue.serverTimestamp(),

          'cadeteNombre': nombreCadete,
          'asignado': {
            'cadeteId': cadete.uid,
            'cadeteNombre': nombreCadete,
          },

          // ✅ blindaje final exacto
          'distanciaKmMostrable': kmMost,
          if (kmReal != null) 'distanciaKmReal': kmReal,
          'montoCadete': montoCad,
          'montoTotal': montoTot,
          'montoGananciaAdmin': _gananciaYendo,

          // compat
          if (kmReal != null) 'distancia_km': kmReal,

          if (telefonoCliente.isNotEmpty) 'telefonoCliente': telefonoCliente,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pedido aceptado')));
      _limpiarSel();
      unawaited(_dibujarMarkersMapLibre());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _entregar() async {
    if (_selId == null || _selLocalId == null) {
      return;
    }

    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) {
      return;
    }

    // ✅ anti doble toque en el botón
    if (_entregando) return;
    if (mounted) setState(() => _entregando = true);

    final db = FirebaseFirestore.instance;
    final idPedido = _selId!;
    final uidLocal = _selLocalId!;

    final pedidoEnCursoRef = db.collection('pedidosEnCurso').doc(idPedido);
    final pedidoRef = db.collection('pedidos').doc(idPedido);

    // ✅ usar el MISMO id del pedido evita historiales duplicados
    final histLocalRef = db
        .collection('usuarios')
        .doc(uidLocal)
        .collection('historial')
        .doc(idPedido);

    final histCadeteRef = db
        .collection('usuarios')
        .doc(cadete.uid)
        .collection('historial')
        .doc(idPedido);

    try {
      await db.runTransaction((txn) async {
        final snap = await txn.get(pedidoEnCursoRef);
        if (!snap.exists) return;

        final pedidoData = snap.data() ?? <String, dynamic>{};

        // ✅ bloqueo fuerte anti duplicado: si ya pasó a historial, no repite nada
        if (pedidoData['pasadoAHistorial'] == true) return;

        final estado = (pedidoData['estado'] ?? '').toString();
        final idCadetePedido = (pedidoData['idCadete'] ?? '').toString();

        if (idCadetePedido != cadete.uid) {
          throw Exception('Este pedido no está asignado a este cadete.');
        }

        final puedeEntregar = estado == _estadoEntregadoAlCadete ||
            estado == _estadoListo ||
            estado == _estadoEntregadoLegacy;

        if (!puedeEntregar) {
          throw Exception('El pedido todavía no está listo para entregar.');
        }

        // ✅ NO recalcular: usar guardado, pero forzar mostrable a 1 decimal
        final kmMost = _to1DecimalNullable(
          pedidoData['distanciaKmMostrable'] ?? pedidoData['distancia_km'],
        );
        final kmReal = _toDouble(pedidoData['distanciaKmReal']) ??
            _toDouble(pedidoData['distancia_km']);

        int? montoCad = _toInt(pedidoData['montoCadete']);
        int? montoTot = _toInt(pedidoData['montoTotal']);

        // ✅ Deducción por regla fija +/-5
        if (montoCad == null && montoTot != null) {
          montoCad = montoTot - _gananciaYendo;
        }
        if (montoTot == null && montoCad != null) {
          montoTot = montoCad + _gananciaYendo;
        }

        if (kmMost == null || montoCad == null || montoTot == null) {
          throw Exception('Pedido sin montos/distancia guardados.');
        }

        final now = Timestamp.now();
        final clientePedido =
            (pedidoData['cliente'] ?? _selCliente ?? 'Cliente').toString();

        String nombreLocal = 'Local';
        String nombreCadete = 'Cadete';
        dynamic idCadete = cadete.uid;

        try {
          final localSnap =
              await txn.get(db.collection('usuarios').doc(uidLocal));
          final cadeteSnap =
              await txn.get(db.collection('usuarios').doc(cadete.uid));

          nombreLocal = (localSnap.data()?['nombre'] ?? 'Local').toString();
          nombreCadete = (cadeteSnap.data()?['nombre'] ?? 'Cadete').toString();
          idCadete = cadeteSnap.data()?['id'] ?? cadete.uid;
        } catch (_) {}

        txn.update(pedidoEnCursoRef, <String, dynamic>{
          'pasadoAHistorial': true,
          'estado': _estadoEntregadoLegacy,
          'fechaEntregado': now,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          pedidoRef,
          <String, dynamic>{
            ...pedidoData,
            'pasadoAHistorial': true,
            'estado': _estadoEntregadoLegacy,
            'fechaEntregado': now,

            // ✅ exactitud guardada: mostrable siempre 1 decimal
            'distanciaKmMostrable': kmMost,
            if (kmReal != null) 'distanciaKmReal': kmReal,

            'montoTotal': montoTot,
            'montoCadete': montoCad,
            'montoGananciaAdmin': _gananciaYendo,

            // compat
            'distancia_km': kmReal ?? kmMost,
          },
          SetOptions(merge: true),
        );

        txn.set(
          histLocalRef,
          <String, dynamic>{
            'cliente': clientePedido,
            'distancia': kmMost,
            'distanciaKmMostrable': kmMost,
            if (kmReal != null) 'distanciaKmReal': kmReal,
            'montoTotal': montoTot,
            'montoGananciaAdmin': _gananciaYendo,
            'fecha': now,
            'estado': _estadoEntregadoLegacy,
            'cadeteNombre': nombreCadete,
            'idCadete': idCadete,
          },
          SetOptions(merge: true),
        );

        txn.set(
          histCadeteRef,
          <String, dynamic>{
            'cliente': clientePedido,
            'distancia': kmMost,
            'distanciaKmMostrable': kmMost,
            if (kmReal != null) 'distanciaKmReal': kmReal,
            'montoCadete': montoCad,
            'fecha': now,
            'estado': _estadoEntregadoLegacy,
            'localNombre': nombreLocal,
          },
          SetOptions(merge: true),
        );

        txn.delete(pedidoEnCursoRef);
      });

      if (!mounted) return;

      setState(() {
        _pedidos.removeWhere((p) => p.id == idPedido);
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pedido entregado')));
      _limpiarSel();
      unawaited(_dibujarMarkersMapLibre());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al entregar: $e')),
      );
    } finally {
      if (mounted) setState(() => _entregando = false);
    }
  }

  // ✅ Botón "Comenzar" -> abre Google Maps normal (solo Android)
  Future<void> _comenzarGoogleMaps(LatLng destino) async {
    if (!Platform.isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navegación disponible solo en Android')),
      );
      return;
    }

    final lat = destino.latitude;
    final lng = destino.longitude;

    final native = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    try {
      final ok = await launchUrl(native, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _comenzarGoogleMapsAlLocal(String idLocal) async {
    LatLng? localPos = _ubicacionesLocales[idLocal];

    if (localPos == null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(idLocal)
          .get();

      final u = doc.data()?['ubicacion'];
      if (u is Map && u['lat'] != null && u['lng'] != null) {
        localPos = LatLng(
          (u['lat'] as num).toDouble(),
          (u['lng'] as num).toDouble(),
        );
        _ubicacionesLocales[idLocal] = localPos;
      }
    }

    if (localPos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró la ubicación del local')),
      );
      return;
    }

    await _comenzarGoogleMaps(localPos);
  }

  Future<void> _llamarTelefono(String telefono) async {
    final telFmt = telefono.replaceAll(RegExp(r'\D'), '');
    if (telFmt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró el teléfono')),
      );
      return;
    }

    final uri = Uri.parse('tel:$telFmt');

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo iniciar la llamada')),
      );
    }
  }

  void _limpiarSel() {
    if (!mounted) return;
    setState(() {
      _selId = _selCliente = _selLocalId = _selEstado = null;
      _selDestino = null;
      _selMontoCadete = null;
      _selDireccionLocal = null;
      _selTelefonoCliente = null;
      _selTelefonoLocal = null;
      _selNombreLocal = null;
    });
  }

  String _colorToHex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2)}';
  }

  Future<void> _limpiarMarkersMapLibre() async {
    final map = _mapLibreController;
    if (map == null) return;

    for (final c in List<maplibre.Circle>.from(_circles)) {
      try {
        await map.removeCircle(c);
      } catch (_) {}
    }

    for (final s in List<maplibre.Symbol>.from(_symbols)) {
      try {
        await map.removeSymbol(s);
      } catch (_) {}
    }

    _circles.clear();
    _symbols.clear();
    _circlePedidos.clear();
  }

  Future<void> _dibujarMarkersMapLibre() async {
    final map = _mapLibreController;
    if (!_mapStyleLoaded || map == null || _miPos == null) return;

    await _limpiarMarkersMapLibre();

    // 🛵 cadete
    final moto = await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(_miPos!.latitude, _miPos!.longitude),
        textField: '🛵',
        textSize: 28,
        textAnchor: 'center',
      ),
    );
    _symbols.add(moto);

    // ⚫ locales: punto negro redondo (estable, sin emojis ni assets)
    for (final pos in _ubicacionesLocales.values) {
      final local = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(pos.latitude, pos.longitude),
          circleColor: '#000000',
          circleRadius: 7,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
      _circles.add(local);
    }

    // puntos de pedidos/clientes personalizados
    for (final p in _pedidos) {
      final data = p.data();
      final u = data['ubicacionDestino'];

      if (u is! Map || u['lat'] == null || u['lng'] == null) {
        continue;
      }

      final destino = LatLng(
        (u['lat'] as num).toDouble(),
        (u['lng'] as num).toDouble(),
      );

      final estado = (data['estado'] ?? '').toString();
      final idLocalPedido = (data['idLocal'] ?? '').toString();
      final idCadetePedido = (data['idCadete'] ?? '').toString();

      final esMio = idCadetePedido == (_uid ?? '');
      final esPendienteLibre =
          estado == _estadoPendiente && idCadetePedido.isEmpty;

      final esDelMismoLocal = _miLocalActivoId != null &&
          _miLocalActivoId!.isNotEmpty &&
          idLocalPedido == _miLocalActivoId;

      final color = esMio
          ? Colors.green
          : (esPendienteLibre && esDelMismoLocal)
              ? Colors.amber
              : (estado == _estadoPendiente)
                  ? Colors.orange
                  : Colors.grey;

      final circle = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(destino.latitude, destino.longitude),
          circleColor: _colorToHex(color),
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );

      _circles.add(circle);
      _circlePedidos[circle] = p;
    }
  }

  Future<void> _seleccionarPedidoDesdeCircle(maplibre.Circle circle) async {
    final p = _circlePedidos[circle];
    if (p == null) return;

    final data = p.data();
    final u = data['ubicacionDestino'];

    if (u is! Map || u['lat'] == null || u['lng'] == null) {
      return;
    }

    final destino = LatLng(
      (u['lat'] as num).toDouble(),
      (u['lng'] as num).toDouble(),
    );

    final estado = (data['estado'] ?? '').toString();
    final idLocalPedido = (data['idLocal'] ?? '').toString();

    final docLoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idLocalPedido)
        .get();

    final direccionLoc = (docLoc.data()?['direccion'] ?? '').toString();
    final nombreLoc = (docLoc.data()?['nombre'] ?? '').toString();
    final telefonoCliente = (data['telefonoCliente'] ?? '').toString();
    final telefonoLocal = (docLoc.data()?['telefono'] ?? '').toString();

    // ✅ mostrar pago guardado (o deducido total-5)
    int? montoCad = _toInt(data['montoCadete']);
    final montoTot = _toInt(data['montoTotal']);
    if (montoCad == null && montoTot != null) {
      montoCad = montoTot - _gananciaYendo;
    }

    if (!mounted) return;
    setState(() {
      _selId = p.id;
      _selDestino = destino;
      _selCliente = (data['cliente'] ?? '').toString();
      _selMontoCadete = montoCad;
      _selLocalId = idLocalPedido;
      _selEstado = estado;
      _selDireccionLocal = direccionLoc;
      _selNombreLocal = nombreLoc;
      _selTelefonoCliente = telefonoCliente;
      _selTelefonoLocal = telefonoLocal;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_miPos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos personalizados')),
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: maplibre.CameraPosition(
              target: maplibre.LatLng(
                _miPos!.latitude,
                _miPos!.longitude,
              ),
              zoom: 11,
            ),
            minMaxZoomPreference: const maplibre.MinMaxZoomPreference(11, 17),
            myLocationEnabled: true,
            onMapCreated: (controller) {
              _mapLibreController = controller;
              _mapLibreController!.onCircleTapped
                  .add(_seleccionarPedidoDesdeCircle);
            },
            onStyleLoadedCallback: () async {
              _mapStyleLoaded = true;
              await _dibujarMarkersMapLibre();
            },
            onMapClick: (_, __) => _limpiarSel(),
          ),

          Positioned(
            top: 16,
            right: 12,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [17, 15, 13, 11].map((z) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FloatingActionButton.small(
                      heroTag: 'zoom_personalizado_$z',
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 4,
                      onPressed: () => _irAZoom(z.toDouble()),
                      child: Text(
                        '$z',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // panel
          if (_selId != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Builder(
                  builder: (context) {
                    final pedidoSel =
                        _pedidos.firstWhereOrNull((p) => p.id == _selId);
                    final idCadetePedido =
                        (pedidoSel?.data()['idCadete'] ?? '').toString();
                    final esMio = _uid != null && idCadetePedido == _uid;

                    final puedeComenzar = esMio &&
                        _selDestino != null &&
                        (_selEstado == _estadoAceptado ||
                            _selEstado == _estadoEntregadoAlCadete ||
                            _selEstado == _estadoListo ||
                            _selEstado == _estadoEntregadoLegacy);

                    final puedeEntregar = esMio &&
                        (_selEstado == _estadoEntregadoAlCadete ||
                            _selEstado == _estadoListo ||
                            _selEstado == _estadoEntregadoLegacy);

                    final puedeIrAlLocal = esMio &&
                        _selLocalId != null &&
                        _selEstado == _estadoAceptado;

                    final puedeLlamarLocal =
                        esMio && (_selTelefonoLocal ?? '').trim().isNotEmpty;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selNombreLocal != null &&
                            _selNombreLocal!.isNotEmpty)
                          Text('Local: $_selNombreLocal'),
                        if (_selCliente != null && _selCliente!.isNotEmpty)
                          Text('Cliente: $_selCliente'),
                        if (_selDireccionLocal != null &&
                            _selDireccionLocal!.isNotEmpty)
                          Text('Dirección: $_selDireccionLocal'),
                        if (_selMontoCadete != null)
                          Text(
                              'Pago al cadete: \$${_selMontoCadete.toString()}')
                        else
                          const Text('Pago al cadete: (sin monto guardado)'),
                        if (esMio &&
                            (_selEstado == _estadoAceptado ||
                                _selEstado == _estadoEntregadoAlCadete ||
                                _selEstado == _estadoListo) &&
                            _selTelefonoCliente != null &&
                            _selTelefonoCliente!.isNotEmpty)
                          SelectableText(
                              'Teléfono cliente: $_selTelefonoCliente'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            if (_selEstado == _estadoPendiente)
                              ElevatedButton.icon(
                                onPressed: _aceptar,
                                icon: const Icon(Icons.check),
                                label: const Text('Aceptar'),
                              ),
                            if (puedeIrAlLocal)
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _comenzarGoogleMapsAlLocal(_selLocalId!),
                                icon: const Icon(Icons.store),
                                label: const Text('Ir al local'),
                              ),
                            if (puedeComenzar)
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _comenzarGoogleMaps(_selDestino!),
                                icon: const Icon(Icons.navigation),
                                label: const Text('Comenzar'),
                              ),
                            if (puedeEntregar)
                              ElevatedButton.icon(
                                onPressed: _entregando ? null : _entregar,
                                icon: const Icon(Icons.local_shipping),
                                label: Text(
                                  _entregando ? 'Entregando...' : 'Entregar',
                                ),
                              ),
                            if (puedeLlamarLocal)
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _llamarTelefono(_selTelefonoLocal!),
                                icon: const Icon(Icons.phone),
                                label: const Text('Llamar al local'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: _limpiarSel,
                              icon: const Icon(Icons.close),
                              label: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
