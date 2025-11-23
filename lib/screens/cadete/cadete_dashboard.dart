import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:yendoo_app/services/ubicacion_cadete.dart';

// ✅ Importar las pantallas del cadete
import 'package:yendoo_app/screens/cadete/perfil_screen.dart';
import 'package:yendoo_app/screens/cadete/pedidos_pendientes_screen.dart';
import 'package:yendoo_app/screens/cadete/pedidos_personalizados_screen.dart';
import 'package:yendoo_app/screens/cadete/historial_pedidos_cadete_screen.dart';

// ✅ NUEVA pantalla
import 'package:yendoo_app/screens/cadete/listos_para_retiro_screen.dart';

class CadeteDashboardScreen extends StatefulWidget {
  const CadeteDashboardScreen({super.key});

  @override
  State<CadeteDashboardScreen> createState() => _CadeteDashboardScreenState();
}

class _CadeteDashboardScreenState extends State<CadeteDashboardScreen> {
  LatLng? _miUbicacion;
  bool _locationError = false;
  final MapController _mapController = MapController();
  final _ubicacionService = UbicacionCadeteService();

  @override
  void initState() {
    super.initState();
    _obtenerUbicacionCadete();
    _ubicacionService.start(); // 👈 acá adentro seguro usás Geolocator
  }

  Future<void> _obtenerUbicacionCadete() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (!doc.exists) {
        setState(() => _locationError = true);
        return;
      }

      final data = doc.data();
      if (data == null || !data.containsKey('ubicacion')) {
        setState(() => _locationError = true);
        return;
      }

      final geo = data['ubicacion'];

      // Puede venir como Map o GeoPoint, lo manejamos defensivo
      double? lat;
      double? lng;

      if (geo is Map<String, dynamic>) {
        lat = (geo['lat'] as num?)?.toDouble();
        lng = (geo['lng'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) {
        setState(() => _locationError = true);
        return;
      }

      if (!mounted) return;
      setState(() {
        _miUbicacion = LatLng(lat!, lng!);
      });
    } catch (e) {
      // Cualquier error al leer ubicacion del cadete
      if (mounted) {
        setState(() => _locationError = true);
      }
    }
  }

  void _cerrarSesion(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({'activo': false});
    }

    _ubicacionService.stop();
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión cerrada con éxito')),
      );
    }
  }

  // 🔢 Stream del contador de “listos para retirar” para este cadete
  Stream<int> _listosCountStream(String uidCadete) {
    return FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('estado', isEqualTo: 'entregado_al_cadete')
        .where('idCadete', isEqualTo: uidCadete)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Widget _botonFlotante(
    IconData icon,
    String texto,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(texto),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ubicacionService.stop();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cadete = FirebaseAuth.instance.currentUser;

    // ❗ Si hubo problema con la ubicación desde Firestore
    if (_locationError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.location_off, size: 48, color: Colors.redAccent),
              SizedBox(height: 12),
              Text(
                'No se pudo obtener la ubicación del cadete.\nVerifica tu perfil y vuelve a intentar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // ❗ Mientras todavía no cargamos la ubicación inicial
    if (_miUbicacion == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 🌍 Mapa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _miUbicacion!,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                userAgentPackageName: 'com.yendo.yendoo_app',
              ),
            ],
          ),

          // 🧭 Botones
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _botonFlotante(Icons.account_circle, 'Perfil', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PerfilScreen()),
                      );
                    }),
                    const SizedBox(height: 16),

                    // ✅ Botón: Listos para retirar con contador (N)
                    if (cadete != null)
                      StreamBuilder<int>(
                        stream: _listosCountStream(cadete.uid),
                        builder: (context, snap) {
                          final n = snap.data ?? 0;
                          final label = n > 0
                              ? 'Listos para retirar ($n)'
                              : 'Listos para retirar';
                          return _botonFlotante(
                            Icons.shopping_bag,
                            label,
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ListosParaRetiroScreen(),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    if (cadete != null) const SizedBox(height: 16),

                    _botonFlotante(Icons.list, 'Pedidos pendientes', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PedidosPendientesScreen()),
                      );
                    }),
                    const SizedBox(height: 16),
                    _botonFlotante(Icons.star, 'Pedidos personalizados', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const PedidosPersonalizadosScreen()),
                      );
                    }),
                    const SizedBox(height: 16),
                    _botonFlotante(Icons.history, 'Historial', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const HistorialPedidosCadeteScreen()),
                      );
                    }),
                    const SizedBox(height: 32),
                    _botonFlotante(Icons.logout, 'Cerrar sesión', () {
                      _cerrarSesion(context);
                    }, color: Colors.red),
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
