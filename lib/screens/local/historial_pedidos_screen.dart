import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistorialPedidosScreen extends StatefulWidget {
  final String localId;

  const HistorialPedidosScreen({super.key, required this.localId});

  @override
  State<HistorialPedidosScreen> createState() => _HistorialPedidosScreenState();
}

class _HistorialPedidosScreenState extends State<HistorialPedidosScreen> {
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.localId)
        .collection('historial')
        .orderBy('fecha', descending: true)
        .limit(200)
        .snapshots();
  }

  // ===== helpers robustos =====
  double _asDouble(dynamic v, {double def = 0}) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? def;
    return def;
  }

  /// ✅ 0.1 km EXACTO (ceil a 0.1 para no “bajar” nunca)
  double _kmUp01(double km) {
    if (km <= 0) return 0;
    return ((km * 10).ceil()) / 10.0;
  }
  // ===========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de pedidos')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay pedidos entregados aún.'));
          }

          final docs = snapshot.data!.docs;

          // Agrupar por día
          final Map<String, List<QueryDocumentSnapshot>> pedidosPorDia = {};

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final fecha = (data['fecha'] as Timestamp?)?.toDate();
            if (fecha == null) continue;

            final dia = DateFormat('yyyy-MM-dd').format(fecha);
            pedidosPorDia.putIfAbsent(dia, () => []).add(doc);
          }

          return ListView(
            children: pedidosPorDia.entries.map((entry) {
              final fechaKey = entry.key;
              final pedidos = entry.value;

              final fechaBonita =
                  DateFormat('dd/MM/yyyy').format(DateTime.parse(fechaKey));

              double totalDia = 0;

              final widgetsPedidos = pedidos.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final fecha = (data['fecha'] as Timestamp?)?.toDate();

                // ✅ DISTANCIA MOSTRABLE (preferencia: distanciaKmMostrable)
                final distanciaMost =
                    _asDouble(data['distanciaKmMostrable'], def: 0);
                final distanciaLegacy = _asDouble(data['distancia'], def: 0);

                final distanciaParaMostrar =
                    distanciaMost > 0 ? distanciaMost : distanciaLegacy;

                // ✅ TARIFA EXACTA (0.1 km), sin 0.5
                // 1) Si está guardada en historial: kmTarifaLocal
                // 2) Si no está: usar la distancia mostrable
                double kmTarifaLocal = _asDouble(data['kmTarifaLocal'], def: 0);

                if (kmTarifaLocal <= 0) {
                  kmTarifaLocal = distanciaParaMostrar;
                }

                // ✅ Evitar “bajar”: subimos a 0.1 con ceil
                if (kmTarifaLocal > 0) {
                  kmTarifaLocal = _kmUp01(kmTarifaLocal);
                }

                // ✅ MONTO (preferencia: montoTotal guardado)
                double montoTotal = _asDouble(data['montoTotal'], def: 0);

                totalDia += montoTotal;

                final cliente = (data['cliente'] ?? 'Cliente').toString();
                final cadete = (data['cadeteNombre'] ?? 'Cadete').toString();

                return ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Cliente: $cliente'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entregado por: $cadete'),
                      Text(
                        'Distancia: ${distanciaParaMostrar.toStringAsFixed(1)} km',
                      ),
                      Text(
                        'Tarifa: ${kmTarifaLocal.toStringAsFixed(1)} km',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (fecha != null)
                        Text('Hora: ${DateFormat('HH:mm').format(fecha)}'),
                    ],
                  ),
                  trailing: Text(
                    '\$${montoTotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList();

              return ExpansionTile(
                title: Text(
                  '📅 $fechaBonita - Total: \$${totalDia.toStringAsFixed(0)} - Pedidos: ${pedidos.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: widgetsPedidos,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
