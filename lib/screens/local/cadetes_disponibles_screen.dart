import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class CadetesDisponiblesScreen extends StatefulWidget {
  final String localId;

  const CadetesDisponiblesScreen({
    super.key,
    required this.localId,
  });

  @override
  State<CadetesDisponiblesScreen> createState() =>
      _CadetesDisponiblesScreenState();
}

class _CadetesDisponiblesScreenState extends State<CadetesDisponiblesScreen> {
  final _db = FirebaseFirestore.instance;
  final _distance = const Distance();
  final Set<String> _guardando = {};

  static const double radioMaximoKm = 8.5;

  LatLng? _leerUbicacion(dynamic raw) {
    if (raw is! Map) return null;

    final lat = raw['lat'];
    final lng = raw['lng'];

    if (lat is! num || lng is! num) return null;

    final latitude = lat.toDouble();
    final longitude = lng.toDouble();

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  Future<void> _alternarFavorito(
    String cadeteId,
    bool esFavorito,
  ) async {
    if (_guardando.contains(cadeteId)) return;

    setState(() => _guardando.add(cadeteId));

    try {
      final ref = _db.collection('usuarios').doc(widget.localId);

      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(ref);

        if (!doc.exists) {
          throw Exception('No se encontró el local');
        }

        final raw = doc.data()?['cadetesFavoritos'];

        final favoritos =
            raw is List ? raw.whereType<String>().toSet() : <String>{};

        if (favoritos.contains(cadeteId)) {
          favoritos.remove(cadeteId);
        } else {
          if (favoritos.length >= 12) {
            throw Exception(
              'Máximo 12 cadetes favoritos alcanzado',
            );
          }
          favoritos.add(cadeteId);
        }

        transaction.update(ref, {
          'cadetesFavoritos': favoritos.toList(),
        });
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando.remove(cadeteId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localRef = _db.collection('usuarios').doc(widget.localId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadetes disponibles'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: localRef.snapshots(),
        builder: (context, localSnapshot) {
          if (localSnapshot.hasError) {
            return const Center(
              child: Text('Error al cargar el local'),
            );
          }

          if (!localSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final datosLocal = localSnapshot.data!.data();

          if (datosLocal == null) {
            return const Center(
              child: Text('No se encontró el local'),
            );
          }

          final ubicacionLocal = _leerUbicacion(datosLocal['ubicacion']);

          if (ubicacionLocal == null) {
            return const Center(
              child: Text('El local no tiene ubicación válida'),
            );
          }

          final rawFavoritos = datosLocal['cadetesFavoritos'];

          final favoritos = rawFavoritos is List
              ? rawFavoritos.whereType<String>().toSet()
              : <String>{};

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('usuarios')
                .where('rol', isEqualTo: 'cadete')
                .snapshots(),
            builder: (context, cadetesSnapshot) {
              if (cadetesSnapshot.hasError) {
                return const Center(
                  child: Text('Error al cargar cadetes'),
                );
              }

              if (!cadetesSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final cadetes = <Map<String, dynamic>>[];

              for (final doc in cadetesSnapshot.data!.docs) {
                final datos = doc.data();

                final esFavorito = favoritos.contains(doc.id);
                final posicion = _leerUbicacion(datos['ubicacion']);

                final double? km = posicion == null
                    ? null
                    : _distance.as(
                        LengthUnit.Kilometer,
                        ubicacionLocal,
                        posicion,
                      );

                // Los favoritos se muestran siempre, aun fuera del radio.
                // Los nuevos solo se muestran dentro de 8,5 km.
                if (!esFavorito && (km == null || km > radioMaximoKm)) {
                  continue;
                }

                final disponible = datos['activo'] == true;

                cadetes.add({
                  'id': doc.id,
                  'nombre': (datos['nombre'] ?? 'Cadete').toString(),
                  'km': km,
                  'favorito': esFavorito,
                  'disponible': disponible,
                });
              }

              cadetes.sort((a, b) {
                final favoritoA = a['favorito'] == true;
                final favoritoB = b['favorito'] == true;

                if (favoritoA != favoritoB) {
                  return favoritoA ? -1 : 1;
                }

                final disponibleA = a['disponible'] == true;
                final disponibleB = b['disponible'] == true;
                if (disponibleA != disponibleB) {
                  return disponibleA ? -1 : 1;
                }

                final kmA = a['km'] as double? ?? double.infinity;
                final kmB = b['km'] as double? ?? double.infinity;
                return kmA.compareTo(kmB);
              });

              final totalDisponibles =
                  cadetes.where((c) => c['disponible'] == true).length;
              final totalFavoritosVisibles =
                  cadetes.where((c) => c['favorito'] == true).length;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          '$totalDisponibles disponibles · ${cadetes.length} en la lista',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Radio: 8,5 km · Favoritos: ${favoritos.length}/12',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: cadetes.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No hay favoritos ni cadetes cercanos para mostrar.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: cadetes.length +
                                (totalFavoritosVisibles > 0 ? 1 : 0) +
                                (cadetes.length > totalFavoritosVisibles
                                    ? 1
                                    : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final hayFavoritos = totalFavoritosVisibles > 0;
                              final hayOtros =
                                  cadetes.length > totalFavoritosVisibles;
                              if (hayFavoritos && index == 0) {
                                return const ListTile(
                                  dense: true,
                                  title: Text('Tus favoritos',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                );
                              }
                              final indiceOtros = totalFavoritosVisibles +
                                  (hayFavoritos ? 1 : 0);
                              if (hayOtros && index == indiceOtros) {
                                return const ListTile(
                                  dense: true,
                                  title: Text(
                                      'Otros cadetes cercanos (hasta 8,5 km)',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                );
                              }
                              final indiceCadete = index -
                                  (hayFavoritos ? 1 : 0) -
                                  (hayOtros && index > indiceOtros ? 1 : 0);
                              final cadete = cadetes[indiceCadete];
                              final id = cadete['id'] as String;
                              final esFavorito = cadete['favorito'] == true;
                              final km = cadete['km'] as double?;
                              final disponible = cadete['disponible'] == true;

                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE3F2FD),
                                  child: Icon(
                                    Icons.delivery_dining,
                                    color: Colors.blue,
                                  ),
                                ),
                                title: Text(
                                  cadete['nombre'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      km == null
                                          ? 'Ubicación no disponible'
                                          : '${km.toStringAsFixed(1)} km del local',
                                    ),
                                    Text(
                                      disponible
                                          ? '● Disponible'
                                          : '● No disponible',
                                      style: TextStyle(
                                        color: disponible
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: _guardando.contains(id)
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : IconButton(
                                        tooltip: esFavorito
                                            ? 'Quitar de favoritos'
                                            : 'Agregar a favoritos',
                                        icon: Icon(
                                          esFavorito
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: esFavorito
                                              ? Colors.amber
                                              : Colors.grey,
                                          size: 30,
                                        ),
                                        onPressed: () => _alternarFavorito(
                                          id,
                                          esFavorito,
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
