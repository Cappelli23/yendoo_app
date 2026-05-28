// lib/screens/cadete/pedidos_pendientes_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:url_launcher/url_launcher.dart';

class PedidosPendientesScreen extends StatefulWidget {
  const PedidosPendientesScreen({super.key});

  @override
  State<PedidosPendientesScreen> createState() =>
      _PedidosPendientesScreenState();
}

class _PedidosPendientesScreenState extends State<PedidosPendientesScreen> {
  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapStyleLoaded = false;

  final Map<maplibre.Circle, QueryDocumentSnapshot<Map<String, dynamic>>>
      _circlePedidos = {};
  final List<maplibre.Circle> _circles = [];
  final List<maplibre.Symbol> _symbols = [];

  final AudioPlayer _audioPlayer = AudioPlayer();

  LatLng? _currentPosition;

  // selección actual
  String? _selectedPedidoId;
  LatLng? _selectedDestino;
  String? _selectedCliente;
  String? _selectedLocalId;
  String? _selectedNombreLocal;
  String? _selectedDireccionLocal;
  String? _selectedTelefonoLocal;

  // para colorear en amarillo los pedidos pendientes del mismo local que ya tengo activo
  String? _miLocalActivoId;

  // datos en memoria
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidos = [];
  final Map<String, LatLng> _ubicacionesLocales = {};
  final Map<String, String> _telefonosLocales = {};
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pedidosSubscription;

  // ✅ refresca el mapa cada minuto para que los pedidos pasen a violeta aunque Firestore no cambie
  Timer? _timerColores;

  // para sonido de nuevos pendientes
  List<String> _ultimosIds = [];

  // ✅ anti doble tap entrega
  bool _entregando = false;

  static const String _mapStyle =
      'https://api.maptiler.com/maps/openstreetmap/style.json?key=jKh3fbz0oFEuYjlFsboz';

  static const _estadosVisibles = <String>[
    'pendiente',
    'aceptado',
    'listo',
    'entregado', // legacy
    'entregado_al_cadete',
  ];

  // ✅ estados que cuentan como "tengo pedidos activos"
  static const _estadosActivos = <String>[
    'aceptado',
    'listo',
    'entregado_al_cadete',
  ];

  // ✅ Pedido demorado: se usa para pintar en violeta los pendientes con +20 minutos
  DateTime? _fechaPedidoDesdeData(Map<String, dynamic> d) {
    final fecha =
        d['fechaCreado'] ?? d['fechaCreacion'] ?? d['createdAt'] ?? d['fecha'];

    if (fecha is Timestamp) return fecha.toDate();
    if (fecha is DateTime) return fecha;

    return null;
  }

  bool _pedidoPendienteDemorado20Min(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString();
    final idCadete = (d['idCadete'] ?? '').toString();

    if (estado != 'pendiente' || idCadete.isNotEmpty) return false;

    final fechaPedido = _fechaPedidoDesdeData(d);
    if (fechaPedido == null) return false;

    return DateTime.now().difference(fechaPedido).inMinutes >= 15;
  }

  // ✅ Regla única: total = cadete + 5
  static const int _gananciaYendo = 5;

  // ✅ Zooms fijos del mapa: 11, 13, 15 y 17
  Future<void> _irAZoom(double zoom) async {
    await _mapLibreController?.animateCamera(
      maplibre.CameraUpdate.zoomTo(zoom),
    );
  }

  double _kmEntre(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Kilometer, a, b);

  // ✅ EXACTITUD mostrable/guardable: 1 decimal
  double _to1Decimal(double km) => double.parse(km.toStringAsFixed(1));

  // ✅ fuerza 1 decimal y tipo double (evita que te quede int en Firestore)
  double _as1DecimalDouble(dynamic v, {double def = 0}) {
    final d = _toDouble(v);
    if (d == null) return def;
    return _to1Decimal(d);
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

  num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _iniciarUbicacionEnTiempoReal();
    _escucharPedidos();

    // ✅ Importante: Firestore no vuelve a emitir solo porque pasa el tiempo.
    // Esto fuerza a redibujar el mapa cada minuto para recalcular el color violeta.
    _timerColores = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        unawaited(_dibujarMarkersMapLibre());
      }
    });
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
    unawaited(_dibujarMarkersMapLibre());

    _positionSubscription = Geolocator.getPositionStream().listen((p) async {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(cadete.uid)
          .update({
        'ubicacion': {
          'lat': p.latitude,
          'lng': p.longitude,
        }
      });

      if (!mounted) return;

      final nuevaPos = LatLng(
        p.latitude,
        p.longitude,
      );

      setState(() {
        _currentPosition = nuevaPos;
      });

      // ✅ La cámara sigue al cadete para que siempre vea su propia moto.
      await _mapLibreController?.animateCamera(
        maplibre.CameraUpdate.newLatLng(
          maplibre.LatLng(
            p.latitude,
            p.longitude,
          ),
        ),
      );

      // ✅ Redibuja la 🛵 del cadete, locales y pedidos.
      await _dibujarMarkersMapLibre();
    });
  }

  void _escucharPedidos() {
    _pedidosSubscription = FirebaseFirestore.instance
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

      // Determinar "mi local activo" para amarillo:
      String? miLocal;
      for (final doc in snap.docs) {
        final d = doc.data();
        final estado = (d['estado'] ?? '').toString();
        final idCadete = (d['idCadete'] ?? '').toString();
        if (idCadete == uid &&
            (estado == 'aceptado' ||
                estado == 'listo' ||
                estado == 'entregado_al_cadete')) {
          final idLocal = (d['idLocal'] ?? '').toString();
          if (idLocal.isNotEmpty) {
            miLocal = idLocal;
            break;
          }
        }
      }

      // FILTRO:
      // - Mostrar PENDIENTES sin cadete
      // - Mostrar pedidos ASIGNADOS al cadete actual
      final filtrados = snap.docs.where((doc) {
        final d = doc.data();
        final estado = (d['estado'] ?? '').toString();
        final idCadete = (d['idCadete'] ?? '').toString();
        final esMio = idCadete == uid;

        if (estado == 'pendiente') {
          return idCadete.isEmpty;
        }
        return esMio;
      }).toList();

      // cachear ubicaciones de locales (de lo filtrado)
      for (final ped in filtrados) {
        final d = ped.data();
        final idLocal = (d['idLocal'] ?? '').toString();
        if (idLocal.isEmpty) continue;

        if (!_ubicacionesLocales.containsKey(idLocal)) {
          final docLoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(idLocal)
              .get();

          final locData = docLoc.data();
          final u = locData?['ubicacion'];
          if (u is Map && u['lat'] != null && u['lng'] != null) {
            _ubicacionesLocales[idLocal] = LatLng(
              (u['lat'] as num).toDouble(),
              (u['lng'] as num).toDouble(),
            );
          }

          final telLocal = (locData?['telefono'] ?? '').toString();
          if (telLocal.trim().isNotEmpty) {
            _telefonosLocales[idLocal] = telLocal.trim();
          }
        }
      }

      setState(() {
        _pedidos = filtrados;
        _ultimosIds = snap.docs.map((e) => e.id).toList();
        _miLocalActivoId = miLocal;

        // Si el seleccionado ya no está en la lista filtrada, cerramos panel
        if (_selectedPedidoId != null &&
            !_pedidos.any((d) => d.id == _selectedPedidoId)) {
          _selectedPedidoId = null;
          _selectedDestino = null;
          _selectedCliente = null;
          _selectedLocalId = null;
          _selectedNombreLocal = null;
          _selectedDireccionLocal = null;
          _selectedTelefonoLocal = null;
        }
      });

      unawaited(_dibujarMarkersMapLibre());
    });
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

  // Abrir Google Maps normal (solo Android) para navegar al destino del cliente
  Future<void> _comenzarRecorridoGoogleMaps(LatLng destino) async {
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
      final okNative =
          await launchUrl(native, mode: LaunchMode.externalApplication);
      if (!okNative) {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  // ✅ Abre Google Maps hacia la ubicación del local
  Future<void> _comenzarRecorridoAlLocal(String idLocal) async {
    LatLng? localPos = _ubicacionesLocales[idLocal];

    if (localPos == null) {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(idLocal)
          .get();

      final data = doc.data();
      final u = data?['ubicacion'];
      if (u is Map && u['lat'] != null && u['lng'] != null) {
        localPos = LatLng(
          (u['lat'] as num).toDouble(),
          (u['lng'] as num).toDouble(),
        );
        _ubicacionesLocales[idLocal] = localPos;
      }

      final telLocal = (data?['telefono'] ?? '').toString();
      if (telLocal.trim().isNotEmpty) {
        _telefonosLocales[idLocal] = telLocal.trim();
      }
    }

    if (localPos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró la ubicación del local')),
      );
      return;
    }

    await _comenzarRecorridoGoogleMaps(localPos);
  }

  Future<void> _llamarTelefono(String telefono) async {
    final telFmt = telefono.replaceAll(RegExp(r'\D'), '');
    if (telFmt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay teléfono disponible')),
      );
      return;
    }

    final uri = Uri.parse('tel:$telFmt');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ✅ bloqueo por local antes de aceptar (REAL: mira pedidos activos, NO localActivoId)
  Future<String?> _validarBloqueoLocalAntesDeAceptar({
    required String uidCadete,
    required String idLocalSeleccionado,
  }) async {
    final q = await FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idCadete', isEqualTo: uidCadete)
        .where('estado', whereIn: _estadosActivos)
        .get();

    if (q.docs.isEmpty) return null;

    final localesActivos = q.docs
        .map((d) => (d.data()['idLocal'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    if (localesActivos.isNotEmpty &&
        !localesActivos.contains(idLocalSeleccionado)) {
      return 'Ya tenés pedidos activos de otro local. Terminá esos pedidos para aceptar de este local.';
    }
    return null;
  }

  // 2da app: subtotal/envío/total
  num? _leerSubtotal(Map<String, dynamic> pedidoData) {
    final n = _toNum(pedidoData['subtotal']);
    if (n != null && n >= 0) return n;
    return null;
  }

  num? _leerEnvioCosto(Map<String, dynamic> pedidoData) {
    final envio = (pedidoData['envio'] as Map?)?.cast<String, dynamic>();
    final n1 = _toNum(envio?['costo']);
    if (n1 != null && n1 >= 0) return n1;
    final n2 = _toNum(envio?['envioCosto']);
    if (n2 != null && n2 >= 0) return n2;
    final n3 = _toNum(pedidoData['envioCosto']);
    if (n3 != null && n3 >= 0) return n3;
    return null;
  }

  num? _leerTotalPedido(Map<String, dynamic> pedidoData) {
    final n = _toNum(pedidoData['total']);
    if (n != null && n >= 0) return n;

    final sub = _leerSubtotal(pedidoData);
    final env = _leerEnvioCosto(pedidoData);
    if (sub != null && env != null) return sub + env;

    return null;
  }

  Map<String, dynamic> _extraerPagoCampos(Map<String, dynamic> pedidoData) {
    final out = <String, dynamic>{};

    String? metodo = pedidoData['pagoMetodo'] as String?;
    num? monto = pedidoData['pagoMonto'] as num?;
    String? via = pedidoData['pagoVia'] as String?;
    String? resumen = pedidoData['pagoResumen'] as String?;

    final pago = (pedidoData['pago'] as Map?)?.cast<String, dynamic>();
    metodo ??= pago?['metodo'] as String?;
    monto ??= pago?['monto'] as num?;
    via ??= pago?['via'] as String?;
    resumen ??= pago?['resumen'] as String?;

    if (metodo != null) out['pagoMetodo'] = metodo;
    if (monto != null) out['pagoMonto'] = monto;
    if (via != null) out['pagoVia'] = via;
    if (resumen != null && resumen.trim().isNotEmpty) {
      out['pagoResumen'] = resumen;
    }
    if (pago != null && pago.isNotEmpty) out['pago'] = pago;

    return out;
  }

  // ✅ ACEPTAR: BLOQUEA SOLO SI HAY PEDIDOS ACTIVOS DE OTRO LOCAL (NO usa localActivoId)
  Future<void> _aceptarPedido() async {
    if (_selectedPedidoId == null || _selectedLocalId == null) return;

    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    // ✅ bloqueo real antes de aceptar (según pedidosEnCurso activos)
    final bloqueo = await _validarBloqueoLocalAntesDeAceptar(
      uidCadete: cadete.uid,
      idLocalSeleccionado: _selectedLocalId!,
    );
    if (bloqueo != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(bloqueo)));
      return;
    }

    // nombre real cadete
    String nombreCadete = 'Cadete';
    try {
      final cadeteDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(cadete.uid)
          .get();
      final n = (cadeteDoc.data()?['nombre'] ?? '').toString().trim();
      if (n.isNotEmpty) nombreCadete = n;
    } catch (_) {}

    final ref = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .doc(_selectedPedidoId!);

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('El pedido ya no existe.');

        final data = (snap.data() ?? <String, dynamic>{});
        final estado = (data['estado'] ?? '').toString();
        final idCadeteActual = (data['idCadete'] ?? '').toString();

        if (estado != 'pendiente' || idCadeteActual.isNotEmpty) {
          throw Exception('El pedido ya fue aceptado por otro cadete.');
        }

        // ✅ LO COCINADO
        final montoCad = _toInt(data['montoCadete']);
        final montoTot = _toInt(data['montoTotal']);

        // ✅ kmMost: primero distanciaKmMostrable; si no existe, usar distancia_km
        double? kmMost = _toDouble(data['distanciaKmMostrable']);
        kmMost ??= _toDouble(data['distancia_km']);

        // ✅ kmReal: si existe distanciaKmReal usarla; si no existe, copiar
        double? kmReal = _toDouble(data['distanciaKmReal']);
        kmReal ??= _toDouble(data['distancia_km']);
        kmReal ??= kmMost;

        final double? kmMostFinal = kmMost == null ? null : _to1Decimal(kmMost);
        final double? kmRealFinal = kmReal;

        int? montoCadFinal = montoCad;
        int? montoTotFinal = montoTot;

        // fallback LEGACY: pedido viejísimo sin montos/distancia guardados
        if (montoCadFinal == null ||
            montoTotFinal == null ||
            kmMostFinal == null) {
          final uO = data['ubicacionOrigen'];
          final uD = data['ubicacionDestino'];
          if (uO is Map &&
              uD is Map &&
              uO['lat'] != null &&
              uO['lng'] != null &&
              uD['lat'] != null &&
              uD['lng'] != null) {
            final origen = LatLng(
              (uO['lat'] as num).toDouble(),
              (uO['lng'] as num).toDouble(),
            );
            final destino = LatLng(
              (uD['lat'] as num).toDouble(),
              (uD['lng'] as num).toDouble(),
            );

            final kmExact = _kmEntre(origen, destino);
            final kmMostFallback = _to1Decimal(kmExact);
            final kmRealFallback = double.parse(kmExact.toStringAsFixed(3));

            int baseCadete;
            if (kmMostFallback <= 1.0) {
              baseCadete = 65;
            } else if (kmMostFallback <= 2.0) {
              baseCadete = 85;
            } else if (kmMostFallback <= 3.0) {
              baseCadete = 105;
            } else if (kmMostFallback <= 4.0) {
              baseCadete = 125;
            } else if (kmMostFallback <= 5.0) {
              baseCadete = 145;
            } else if (kmMostFallback <= 6.0) {
              baseCadete = 165;
            } else if (kmMostFallback <= 7.0) {
              baseCadete = 185;
            } else if (kmMostFallback <= 8.0) {
              baseCadete = 205;
            } else if (kmMostFallback <= 8.5) {
              baseCadete = 225;
            } else {
              baseCadete = 0;
            }

            montoCadFinal = baseCadete;
            montoTotFinal = baseCadete + _gananciaYendo;

            txn.update(ref, <String, dynamic>{
              'distanciaKmMostrable': kmMostFallback,
              'distanciaKmReal': kmRealFallback,
              'distancia_km': kmRealFallback, // compat
            });
          }
        }

        final telefonoCliente = (data['telefonoCliente'] ?? '').toString();

        txn.update(ref, <String, dynamic>{
          'estado': 'aceptado',
          'idCadete': cadete.uid,
          'fechaAceptado': FieldValue.serverTimestamp(),
          'cadeteNombre': nombreCadete,
          'asignado': <String, dynamic>{
            'cadeteId': cadete.uid,
            'cadeteNombre': nombreCadete,
          },
          if (montoCadFinal != null) 'montoCadete': montoCadFinal,
          if (montoTotFinal != null) 'montoTotal': montoTotFinal,
          'montoGananciaAdmin': _gananciaYendo,
          if (kmMostFinal != null) 'distanciaKmMostrable': kmMostFinal,
          if (kmRealFinal != null) 'distanciaKmReal': kmRealFinal,
          if (kmRealFinal != null) 'distancia_km': kmRealFinal,
          if (telefonoCliente.isNotEmpty) 'telefonoCliente': telefonoCliente,
        });
      });

      if (mounted) {
        setState(() => _selectedPedidoId = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pedido aceptado')));
        unawaited(_dibujarMarkersMapLibre());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// ✅ ENTREGAR (ANTI DUPLICADOS) + guarda subtotal/envío/total+pago para admin
  Future<void> _entregarPedido(
      String idPedido, String uidLocal, LatLng destino) async {
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    if (_entregando) return;
    if (mounted) setState(() => _entregando = true);

    final db = FirebaseFirestore.instance;

    final pedidoEnCursoRef = db.collection('pedidosEnCurso').doc(idPedido);
    final pedidoRef = db.collection('pedidos').doc(idPedido);

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

        // guard anti-duplicado
        if (pedidoData['pasadoAHistorial'] == true) return;

        final clientePedido = (pedidoData['cliente'] ?? 'Cliente').toString();

        final double kmMost = _as1DecimalDouble(
          pedidoData['distanciaKmMostrable'] ?? pedidoData['distancia_km'],
          def: 0,
        );

        final double? kmReal = _toDouble(pedidoData['distanciaKmReal']) ??
            _toDouble(pedidoData['distancia_km']);

        final int? montoCad = _toInt(pedidoData['montoCadete']);
        final int? montoTot = _toInt(pedidoData['montoTotal']);

        if (kmMost <= 0 || montoCad == null || montoTot == null) {
          throw Exception('Pedido sin montos/distancia guardados.');
        }

        final double kmTarifaLocal = _as1DecimalDouble(
          pedidoData['kmTarifaLocal'] ?? kmMost,
          def: kmMost,
        );

        // ✅ datos 2da app
        final num? subtotal = _leerSubtotal(pedidoData);
        final num? envioCosto = _leerEnvioCosto(pedidoData);
        final num? totalPedido = _leerTotalPedido(pedidoData);
        final pagoExtra = _extraerPagoCampos(pedidoData);

        String nombreLocal = 'Local';
        String nombreCadete = 'Cadete';
        dynamic idCadete = cadete.uid;

        try {
          final locSnap =
              await txn.get(db.collection('usuarios').doc(uidLocal));
          final cadSnap =
              await txn.get(db.collection('usuarios').doc(cadete.uid));
          nombreLocal = (locSnap.data()?['nombre'] ?? 'Local').toString();
          nombreCadete = (cadSnap.data()?['nombre'] ?? 'Cadete').toString();
          idCadete = cadSnap.data()?['id'] ?? cadete.uid;
        } catch (_) {}

        final now = Timestamp.now();

        txn.update(pedidoEnCursoRef, <String, dynamic>{
          'pasadoAHistorial': true,
          'estado': 'entregado',
          'fechaEntregado': now,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          pedidoRef,
          <String, dynamic>{
            ...pedidoData,
            'estado': 'entregado',
            'fechaEntregado': now,
            'distanciaKmMostrable': kmMost,
            'kmTarifaLocal': kmTarifaLocal,
            if (kmReal != null) 'distanciaKmReal': kmReal,

            // envío legacy
            'montoTotal': montoTot,
            'montoCadete': montoCad,
            'montoGananciaAdmin': _gananciaYendo,

            // ✅ admin: venta/envío/total (2da app)
            if (subtotal != null) 'subtotal': subtotal,
            if (envioCosto != null) 'envioCosto': envioCosto,
            if (totalPedido != null) 'total': totalPedido,
            ...pagoExtra,

            'distancia_km': kmReal ?? kmMost,
          },
          SetOptions(merge: true),
        );

        // HISTORIAL LOCAL (admin lo ve)
        txn.set(
          histLocalRef,
          <String, dynamic>{
            'cliente': clientePedido,
            'distancia': kmMost,
            'distanciaKmMostrable': kmMost,
            'kmTarifaLocal': kmTarifaLocal,
            if (kmReal != null) 'distanciaKmReal': kmReal,

            // envío legacy
            'montoTotal': montoTot,
            'montoGananciaAdmin': _gananciaYendo,

            // ✅ admin: venta/envío/total (2da app)
            if (subtotal != null) 'subtotal': subtotal,
            if (envioCosto != null) 'envioCosto': envioCosto,
            if (totalPedido != null) 'total': totalPedido,
            ...pagoExtra,

            'fecha': now,
            'estado': 'entregado',
            'cadeteNombre': nombreCadete,
            'idCadete': idCadete,
          },
          SetOptions(merge: true),
        );

        // HISTORIAL CADETE
        txn.set(
          histCadeteRef,
          <String, dynamic>{
            'cliente': clientePedido,
            'distancia': kmMost,
            'distanciaKmMostrable': kmMost,
            if (kmReal != null) 'distanciaKmReal': kmReal,
            'montoCadete': montoCad,
            'fecha': now,
            'estado': 'entregado',
            'localNombre': nombreLocal,
          },
          SetOptions(merge: true),
        );

        txn.delete(pedidoEnCursoRef);
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pedido entregado')));
        setState(() => _selectedPedidoId = null);
        unawaited(_dibujarMarkersMapLibre());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al entregar: $e')),
      );
    } finally {
      if (mounted) setState(() => _entregando = false);
    }
  }

  // ========== Chip de pago para el cadete ==========
  String _labelMetodo(String v) {
    switch (v) {
      case 'débito':
        return 'débito';
      case 'efectivo':
        return 'efectivo';
      case 'transferencia':
        return 'transferencia';
      case 'crédito':
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

  Widget _pagoChipParaCadete(
    BuildContext context,
    Map<String, dynamic> data, {
    bool soloSiEsDebito = false,
  }) {
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
          child: Text(
            resumen,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    if (soloSiEsDebito && metodo != 'debito' && metodo != 'débito') {
      return const SizedBox.shrink();
    }

    final f = NumberFormat.currency(locale: 'es_UY', symbol: r'$');
    final metodoTxt = _labelMetodo(metodo);
    final viaTxt = _labelVia(via);
    final texto = viaTxt.isNotEmpty
        ? '${f.format(monto)} ($metodoTxt · $viaTxt)'
        : '${f.format(monto)} ($metodoTxt)';

    IconData icono() {
      if (metodo == 'debito' || metodo == 'débito') {
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
        case 'crédito':
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
          Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
  // =================================================

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
    final cadete = FirebaseAuth.instance.currentUser;

    if (!_mapStyleLoaded || map == null || _currentPosition == null) return;

    await _limpiarMarkersMapLibre();

    // 🛵 cadete / motito
    final moto = await map.addSymbol(
      maplibre.SymbolOptions(
        geometry: maplibre.LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ),
        textField: '🛵',
        textSize: 28,
        textAnchor: 'center',
      ),
    );
    _symbols.add(moto);

    // ⚫ locales: punto negro redondo (estable, sin emojis ni PNG)
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

    // puntos de pedidos/clientes
    for (final p in _pedidos) {
      final d = p.data();
      final estado = (d['estado'] ?? '').toString();
      final idLocalPedido = (d['idLocal'] ?? '').toString();
      final idCadetePedido = (d['idCadete'] ?? '').toString();

      final uDest = d['ubicacionDestino'];
      if (uDest is! Map || uDest['lat'] == null || uDest['lng'] == null) {
        continue;
      }

      final lat = (uDest['lat'] as num).toDouble();
      final lng = (uDest['lng'] as num).toDouble();

      final esMio = idCadetePedido == (cadete?.uid ?? '');
      final esPendienteLibre = estado == 'pendiente' && idCadetePedido.isEmpty;

      final esDelMismoLocal = _miLocalActivoId != null &&
          _miLocalActivoId!.isNotEmpty &&
          idLocalPedido == _miLocalActivoId;

      final esDemorado20Min = _pedidoPendienteDemorado20Min(d);

      final color = esMio
          ? Colors.green
          : (esPendienteLibre && esDemorado20Min)
              ? Colors.purple
              : (esPendienteLibre && esDelMismoLocal)
                  ? Colors.amber
                  : Colors.red;

      final circle = await map.addCircle(
        maplibre.CircleOptions(
          geometry: maplibre.LatLng(lat, lng),
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

    final d = p.data();
    final estado = (d['estado'] ?? '').toString();
    final idLocalPedido = (d['idLocal'] ?? '').toString();

    if (!_estadosVisibles.contains(estado)) return;

    final uDest = d['ubicacionDestino'];
    if (uDest is! Map || uDest['lat'] == null || uDest['lng'] == null) {
      return;
    }

    final pos = LatLng(
      (uDest['lat'] as num).toDouble(),
      (uDest['lng'] as num).toDouble(),
    );

    final nomLoc = await _nombreLocal(idLocalPedido);

    final docLoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idLocalPedido)
        .get();

    final locData = docLoc.data();
    final direccionLoc = (locData?['direccion'] ?? '').toString();
    final telefonoLocal = (locData?['telefono'] ?? '').toString().trim();

    if (telefonoLocal.isNotEmpty) {
      _telefonosLocales[idLocalPedido] = telefonoLocal;
    }

    if (!mounted) return;

    setState(() {
      _selectedPedidoId = p.id;
      _selectedDestino = pos;
      _selectedCliente = (d['cliente'] ?? '').toString();
      _selectedLocalId = idLocalPedido;
      _selectedNombreLocal = nomLoc;
      _selectedDireccionLocal = direccionLoc;
      _selectedTelefonoLocal = telefonoLocal;
    });
  }

  @override
  void dispose() {
    _timerColores?.cancel();
    _positionSubscription?.cancel();
    _pedidosSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cadete = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                maplibre.MapLibreMap(
                  styleString: _mapStyle,
                  initialCameraPosition: maplibre.CameraPosition(
                    target: maplibre.LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 11,
                  ),
                  minMaxZoomPreference:
                      const maplibre.MinMaxZoomPreference(11, 17),
                  myLocationEnabled: true,
                  myLocationTrackingMode:
                      maplibre.MyLocationTrackingMode.tracking,
                  onMapCreated: (controller) {
                    _mapLibreController = controller;
                    _mapLibreController!.onCircleTapped
                        .add(_seleccionarPedidoDesdeCircle);
                  },
                  onStyleLoadedCallback: () async {
                    _mapStyleLoaded = true;
                    await _dibujarMarkersMapLibre();
                  },
                  onMapClick: (_, __) {
                    setState(() {
                      _selectedPedidoId = null;
                      _selectedTelefonoLocal = null;
                    });
                  },
                ),

                // ✅ Botones de zoom fijo: 17, 15, 13 y 11
                Positioned(
                  top: 50,
                  right: 12,
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [17, 15, 13, 11].map((z) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FloatingActionButton.small(
                            heroTag: 'pedidos_pendientes_zoom_$z',
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

                // panel inferior
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
                                (doc) => doc.id == _selectedPedidoId,
                              );
                              if (pedidoSel == null) {
                                return const SizedBox.shrink();
                              }

                              final d = pedidoSel.data();
                              final estado = (d['estado'] ?? '').toString();
                              final idCadete = (d['idCadete'] ?? '').toString();
                              final telefono =
                                  (d['telefonoCliente'] ?? '').toString();
                              final telefonoLocal = (_selectedTelefonoLocal ??
                                      _telefonosLocales[
                                          _selectedLocalId ?? ''] ??
                                      '')
                                  .toString();

                              final esMio = idCadete == (cadete?.uid ?? '');
                              final puedeEntregar =
                                  _puedeEntregar(d, cadete?.uid);
                              final esDemorado20Min =
                                  _pedidoPendienteDemorado20Min(d);

                              final mostrarIrAlLocal =
                                  esMio && estado == 'aceptado';

                              final mostrarComenzar = esMio &&
                                  (estado == 'entregado_al_cadete' ||
                                      estado == 'entregado' ||
                                      estado == 'listo');

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
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                    icon: const Icon(Icons.phone,
                                        color: Colors.blue),
                                    label: const Text('Llamar al cliente'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                );
                              }

                              Widget buildCallLocalBtn() {
                                if (!esMio || telefonoLocal.trim().isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await _llamarTelefono(telefonoLocal);
                                    },
                                    icon: const Icon(Icons.store),
                                    label: const Text('Llamar al local'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                );
                              }

                              // ✅ MOSTRAR PRECIO GUARDADO
                              Widget buildPagoCadete() {
                                final pagoGuardado = _toInt(d['montoCadete']);
                                if (pagoGuardado != null && pagoGuardado > 0) {
                                  return Text(
                                    'Pago al cadete: \$${pagoGuardado.toString()}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  );
                                }
                                return const Text(
                                  'Pago al cadete: (sin monto guardado)',
                                  style: TextStyle(fontWeight: FontWeight.w700),
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
                                  if (estado == 'pendiente' && esDemorado20Min)
                                    const Padding(
                                      padding:
                                          EdgeInsets.only(top: 4, bottom: 4),
                                      child: Text(
                                        '🟣 Pedido con más de 20 minutos - Prioridad alta',
                                        style: TextStyle(
                                          color: Colors.purple,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  _pagoChipParaCadete(context, d),
                                  const SizedBox(height: 6),
                                  buildPagoCadete(),
                                  const SizedBox(height: 10),
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
                                            onPressed: () {
                                              setState(() =>
                                                  _selectedPedidoId = null);
                                            },
                                            icon: const Icon(Icons.close),
                                            label: const Text('Cancelar'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (mostrarIrAlLocal &&
                                            _selectedLocalId != null)
                                          SizedBox(
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                _comenzarRecorridoAlLocal(
                                                  _selectedLocalId!,
                                                );
                                              },
                                              icon: const Icon(Icons.store),
                                              label: const Text('Ir al local'),
                                            ),
                                          ),
                                        if (puedeEntregar)
                                          SizedBox(
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              onPressed: _entregando
                                                  ? null
                                                  : () {
                                                      _entregarPedido(
                                                        _selectedPedidoId!,
                                                        _selectedLocalId!,
                                                        _selectedDestino!,
                                                      );
                                                    },
                                              icon: const Icon(Icons.done_all),
                                              label: Text(_entregando
                                                  ? 'Entregando...'
                                                  : 'Entregar'),
                                            ),
                                          ),
                                        if (mostrarComenzar)
                                          SizedBox(
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                _comenzarRecorridoGoogleMaps(
                                                  _selectedDestino!,
                                                );
                                              },
                                              icon:
                                                  const Icon(Icons.navigation),
                                              label: const Text('Comenzar'),
                                            ),
                                          ),
                                        buildCallBtn(),
                                        buildCallLocalBtn(),
                                        if (esMio && !puedeEntregar)
                                          const Padding(
                                            padding: EdgeInsets.only(
                                                top: 2, bottom: 2),
                                            child: Text(
                                              'Esperando que el local te entregue el pedido',
                                              style: TextStyle(
                                                  fontStyle: FontStyle.italic),
                                            ),
                                          ),
                                        SizedBox(
                                          height: 44,
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              setState(() =>
                                                  _selectedPedidoId = null);
                                            },
                                            icon: const Icon(Icons.close),
                                            label: Text(puedeEntregar
                                                ? 'Cancelar'
                                                : 'Cerrar'),
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
