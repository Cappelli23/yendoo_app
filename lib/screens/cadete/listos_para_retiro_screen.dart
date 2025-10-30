// lib/screens/cadete/listos_para_retiro_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class ListosParaRetiroScreen extends StatelessWidget {
  const ListosParaRetiroScreen({super.key});

  // ---------- helpers ----------
  int _asInt(dynamic v, {int def = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return def;
  }

  double _asDouble(dynamic v, {double def = 0}) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return def;
  }

  double _kmEntre(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Kilometer, a, b);

  Color _estadoColor(ColorScheme scheme, String e) {
    switch (e) {
      case 'pendiente':
        return Colors.orange;
      case 'aceptado':
        return Colors.blue;
      case 'listo':
        return Colors.teal;
      case 'entregado_al_cadete':
        return Colors.teal; // mismo color que "listo"
      case 'entregado':
        return Colors.green;
      case 'rechazado':
        return Colors.red;
      default:
        return scheme.secondary;
    }
  }

  Map<String, double> _calcularPrecios(double km) {
    if (km <= 3.0) return {'local': 80, 'cadete': 75};
    if (km <= 4.5) return {'local': 100, 'cadete': 95};
    if (km <= 6.0) return {'local': 150, 'cadete': 145};
    if (km <= 8.5) return {'local': 200, 'cadete': 195};
    return {'local': 0, 'cadete': 0};
  }

  // Mueve a historial + borra de pedidosEnCurso (igual que en la pantalla del mapa)
  Future<void> _entregarPedido(
    BuildContext context, {
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final cadete = FirebaseAuth.instance.currentUser;
    if (cadete == null) return;

    // ✅ Revalidar estado en servidor por si quedó desactualizado
    final refEnCurso =
        FirebaseFirestore.instance.collection('pedidosEnCurso').doc(docId);
    final snapLatest = await refEnCurso.get();
    final estadoActual = (snapLatest.data()?['estado'] ?? '').toString();
    if (estadoActual != 'entregado_al_cadete') {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('El local aún no te entregó el pedido. Espera la entrega.'),
        ),
      );
      return;
    }

    final idLocal =
        (data['idLocal'] ?? data['localId'] ?? '').toString(); // fallback

    // destino (cliente)
    final uDest = data['ubicacionDestino'];
    final double? dLat =
        (uDest is Map ? (uDest['lat'] as num?)?.toDouble() : null);
    final double? dLng =
        (uDest is Map ? (uDest['lng'] as num?)?.toDouble() : null);
    if (dLat == null || dLng == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se encontró destino del pedido.')),
      );
      return;
    }
    final destino = LatLng(dLat, dLng);

    // origen (local)
    final locDoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idLocal)
        .get();
    final uLoc = locDoc.data()?['ubicacion'];
    final double? oLat =
        (uLoc is Map ? (uLoc['lat'] as num?)?.toDouble() : null);
    final double? oLng =
        (uLoc is Map ? (uLoc['lng'] as num?)?.toDouble() : null);
    if (oLat == null || oLng == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se encontró ubicación del local.')),
      );
      return;
    }
    final origen = LatLng(oLat, oLng);

    final km = _kmEntre(origen, destino);
    final precios = _calcularPrecios(km);
    final precioLocal = precios['local'];
    final precioCadete = precios['cadete'];
    final now = Timestamp.now();

    final batch = FirebaseFirestore.instance.batch();

    final refHistGeneral =
        FirebaseFirestore.instance.collection('pedidos').doc(docId);

    // Copiar a historial general
    batch.set(refHistGeneral, {
      ...data,
      'estado': 'entregado',
      'fechaEntregado': now,
      'distancia_km': km,
      'montoTotal': precioLocal,
      'montoCadete': precioCadete,
    });

    // Borrar del mapa
    batch.delete(refEnCurso);

    // Historial por usuario (local y cadete)
    final localData = locDoc.data() ?? {};
    final cadeteDoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(cadete.uid)
        .get();

    final nombreLocal = (localData['nombre'] ?? 'Local').toString();
    final nombreCadete = (cadeteDoc.data()?['nombre'] ?? 'Cadete').toString();
    final idCadete = (cadeteDoc.data()?['id'] ?? cadete.uid).toString();

    final histLocalRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idLocal)
        .collection('historial')
        .doc();
    batch.set(histLocalRef, {
      'cliente':
          (data['clienteNombre'] ?? data['cliente'] ?? 'Cliente').toString(),
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
      'cliente':
          (data['clienteNombre'] ?? data['cliente'] ?? 'Cliente').toString(),
      'distancia': km,
      'montoCadete': precioCadete,
      'fecha': now,
      'estado': 'entregado',
      'localNombre': nombreLocal,
    });

    await batch.commit();

    messenger.showSnackBar(
      const SnackBar(content: Text('Pedido entregado ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Listos para retirar')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Inicia sesión para ver tus pedidos listos.'),
          ),
        ),
      );
    }

    // Se muestran aceptados, listo y entregado_al_cadete; pero solo se puede ENTREGAR cuando esté entregado_al_cadete
    final stream = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('estado', whereIn: ['aceptado', 'listo', 'entregado_al_cadete'])
        .where('idCadete', isEqualTo: uid)
        .orderBy('fechaCreado', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Listos para retirar')),
      body: Column(
        children: [
          // Banner aclaratorio
          Material(
            color: Colors.teal.withValues(alpha: 0.08),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se muestran pedidos ACEPTADOS (ir al local y anunciar), '
                      'LISTO (el local lo tiene preparado) y ENTREGADO_AL_CADETE. '
                      'Solo podrás marcar ENTREGADO cuando el estado sea ENTREGADO_AL_CADETE.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No se pudo cargar: ${snap.error}'),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No hay pedidos listos o aceptados.'),
                    ),
                  );
                }

                final scheme = Theme.of(context).colorScheme;

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final data = d.data();

                    final String estado =
                        (data['estado'] ?? 'aceptado').toString();
                    final double total = _asDouble(data['total'], def: 0);
                    final List items = (data['items'] as List?) ?? const [];
                    final Timestamp? t = (data['fechaCreado'] ??
                        data['createdAt']) as Timestamp?;
                    final DateTime? createdAt = t?.toDate();

                    final String cliNombre =
                        (data['clienteNombre'] ?? data['cliente'] ?? '')
                            .toString();
                    final String cliTel = (data['telefonoCliente'] ??
                            data['clienteTelefono'] ??
                            '')
                        .toString();
                    final String direccion =
                        (data['clienteDireccion'] ?? '').toString();
                    final String nota = (data['nota'] ?? '').toString();

                    // destino para validar entrega
                    final uDest = data['ubicacionDestino'];
                    final double? dLat = (uDest is Map
                        ? (uDest['lat'] as num?)?.toDouble()
                        : null);
                    final double? dLng = (uDest is Map
                        ? (uDest['lng'] as num?)?.toDouble()
                        : null);

                    final puedeEntregar = estado == 'entregado_al_cadete';

                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Estado + total
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _estadoColor(scheme, estado)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    estado.toUpperCase(),
                                    style: TextStyle(
                                      color: _estadoColor(scheme, estado),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '\$ ${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Fecha
                            if (createdAt != null) ...[
                              Text(
                                'Creado: ${createdAt.day.toString().padLeft(2, '0')}/'
                                '${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} '
                                '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(color: scheme.secondary),
                              ),
                              const SizedBox(height: 6),
                            ],

                            // Cliente
                            if (cliNombre.isNotEmpty ||
                                cliTel.isNotEmpty ||
                                direccion.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Cliente',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    if (cliNombre.isNotEmpty)
                                      Text('Nombre: $cliNombre'),
                                    if (cliTel.isNotEmpty)
                                      Text('Teléfono: $cliTel'),
                                    if (direccion.isNotEmpty)
                                      Text('Dirección: $direccion'),
                                  ],
                                ),
                              ),

                            // Nota
                            if (nota.isNotEmpty) ...[
                              const Text(
                                'Nota del cliente',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(nota),
                            ],

                            // Items
                            if (items.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: -6,
                                children: items.map<Widget>((it) {
                                  final Map<String, dynamic> m = (it is Map)
                                      ? it.cast<String, dynamic>()
                                      : <String, dynamic>{};
                                  final String nombre =
                                      (m['nombre'] ?? '').toString();
                                  final String emoji =
                                      (m['emoji'] ?? '🛒').toString();
                                  final int cant =
                                      _asInt(m['cantidad'], def: 1);
                                  return Chip(
                                      label: Text('$emoji $nombre x$cant'));
                                }).toList(),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Acciones
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                // ✅ Entregar SOLO si el local ya lo marcó como ENTREGADO_AL_CADETE
                                FilledButton.icon(
                                  onPressed: (!puedeEntregar ||
                                          dLat == null ||
                                          dLng == null)
                                      ? null
                                      : () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title:
                                                  const Text('Entregar pedido'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (cliTel.isNotEmpty) ...[
                                                    const Text(
                                                        'Teléfono del cliente:'),
                                                    SelectableText(
                                                      cliTel,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                    const SizedBox(height: 10),
                                                  ],
                                                  const Text(
                                                      '¿Confirmás que entregaste el pedido al cliente?'),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: const Text('Cancelar'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child:
                                                      const Text('✔ Entregar'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (!context.mounted) return;
                                          if (ok == true) {
                                            await _entregarPedido(
                                              context,
                                              docId: d.id,
                                              data: data,
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.done_all),
                                  label: const Text('Entregar'),
                                ),

                                // Llamar al cliente
                                if (cliTel.isNotEmpty)
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      final tel =
                                          cliTel.replaceAll(RegExp(r'\D'), '');
                                      final uri = Uri.parse('tel:$tel');
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri,
                                            mode:
                                                LaunchMode.externalApplication);
                                      }
                                    },
                                    icon: const Icon(Icons.phone),
                                    label: const Text('Llamar al cliente'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
