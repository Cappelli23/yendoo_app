import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class VerCadetesScreen extends StatefulWidget {
  final String localId;
  const VerCadetesScreen({super.key, required this.localId});

  @override
  State<VerCadetesScreen> createState() => _VerCadetesScreenState();
}

class _VerCadetesScreenState extends State<VerCadetesScreen> {
  final MapController _map = MapController();
  LatLng? _localPos;
  final List<Map<String, dynamic>> _cadetes = [];
  final List<String> _favoritos = [];

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
      setState(() => _localPos = LatLng(geo['lat'], geo['lng']));
    }
  }

  Future<void> _cargarFavoritos() async {
    final d = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.localId)
        .get();

    final raw = d.data()?['cadetesFavoritos'];
    if (raw is List && mounted) {
      setState(() => _favoritos
        ..clear()
        ..addAll(raw.whereType<String>()));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Máximo 8 cadetes favoritos alcanzado'),
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    esFavorito ? favs.remove(idCad) : favs.add(idCad);
    await ref.update({'cadetesFavoritos': favs});

    if (!mounted) return;

    setState(() {
      esFavorito ? _favoritos.remove(idCad) : _favoritos.add(idCad);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(esFavorito
            ? 'Cadete quitado de favoritos'
            : 'Cadete agregado a favoritos'),
        duration: const Duration(seconds: 2),
      ));
    });
  }

  void _escucharCadetes() {
    FirebaseFirestore.instance
        .collection('usuarios')
        .where('rol', isEqualTo: 'cadete')
        .where('ubicacion', isNotEqualTo: null)
        .snapshots()
        .listen((snap) {
      final lista = snap.docs
          .map((d) => {
                'id': d.id,
                'nombre': d['nombre'] ?? 'Cadete',
                'telefono': d['telefono'] ?? '',
                'mostrarTelefono': d['mostrarNumero'] == true,
                'ubicacion': d['ubicacion'],
              })
          .toList();

      if (mounted) {
        setState(() {
          _cadetes
            ..clear()
            ..addAll(lista);
        });
      }
    });
  }

  void _mostrarInfo(Map<String, dynamic> cad) {
    final esFav = _favoritos.contains(cad['id']);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(cad['nombre']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cad['mostrarTelefono']) Text('Teléfono: ${cad['telefono']}'),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _alternarFavorito(cad['id']);
              },
              icon: Icon(esFav ? Icons.favorite : Icons.favorite_border),
              label: Text(esFav
                  ? 'Quitar de favoritos'
                  : 'Agregar a favoritos (${_favoritos.length}/8)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, {
                  'id': cad['id'],
                  'nombre': cad['nombre'],
                });
              },
              icon: const Icon(Icons.check),
              label: const Text('Seleccionar para pedido'),
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
        body: Center(child: Text('Sin ubicación del local')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cadetes disponibles')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: _localPos!, initialZoom: 14.0),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=jKh3fbz0oFEuYjlFsboz',
                userAgentPackageName: 'com.yendo.yendoo_app',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: _localPos!,
                  width: 40,
                  height: 40,
                  child: Image.asset(
                    'assets/icono_local.png',
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.store, size: 38),
                  ),
                ),
              ]),
              MarkerLayer(
                markers: _cadetes.map((cad) {
                  final loc = cad['ubicacion'];
                  final pos = LatLng(loc['lat'], loc['lng']);
                  final esFav = _favoritos.contains(cad['id']);
                  return Marker(
                    point: pos,
                    width: 45,
                    height: 45,
                    child: GestureDetector(
                      onTap: () => _mostrarInfo(cad),
                      child: Icon(
                        Icons.motorcycle,
                        color: esFav ? Colors.red : Colors.green,
                        size: 42,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
