import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistorialPedidosCadeteScreen extends StatefulWidget {
  final String? cadeteUid;

  const HistorialPedidosCadeteScreen({super.key, this.cadeteUid});

  @override
  State<HistorialPedidosCadeteScreen> createState() =>
      _HistorialPedidosCadeteScreenState();
}

class _HistorialPedidosCadeteScreenState
    extends State<HistorialPedidosCadeteScreen> {
  String? _uid;

  // ✅ Mejor: nullable para no depender de late final
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    _uid = widget.cadeteUid ?? FirebaseAuth.instance.currentUser?.uid;

    if (_uid != null) {
      _stream = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_uid)
          .collection('historial')
          .orderBy('fecha', descending: true)
          .limit(200)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null || _stream == null) {
      return const Scaffold(
        body: Center(child: Text('Error: usuario no autenticado')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de entregas')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No se registran entregas.'));
          }

          final docs = snapshot.data!.docs;

          // Agrupar por día
          final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
              entregasPorDia = {};

          for (final doc in docs) {
            final data = doc.data();
            final fecha = (data['fecha'] as Timestamp?)?.toDate();
            if (fecha == null) continue;

            final dia = DateFormat('yyyy-MM-dd').format(fecha);
            entregasPorDia.putIfAbsent(dia, () => []).add(doc);
          }

          return ListView(
            children: entregasPorDia.entries.map((entry) {
              final fechaKey = entry.key;
              final entregas = entry.value;

              final fechaFormateada =
                  DateFormat('dd/MM/yyyy').format(DateTime.parse(fechaKey));

              double totalDia = 0;

              final widgetsPedidos = entregas.map((doc) {
                final data = doc.data();
                final fecha = (data['fecha'] as Timestamp?)?.toDate();

                final cliente = (data['cliente'] ?? 'Cliente').toString();
                final localNombre = (data['localNombre'] ?? 'Local').toString();

                // ✅ SOLO MOSTRAR LO GUARDADO (NO recalcular)
                final distanciaMostrable =
                    _toDouble(data['distanciaKmMostrable']);
                final distanciaVieja = _toDouble(data['distancia']);

                final distanciaParaMostrar = distanciaMostrable > 0
                    ? distanciaMostrable
                    : distanciaVieja;

                // ✅ “Tarifa” SOLO si existe guardada (si no existe, NO inventar)
                final kmTarifaGuardada = _toDouble(data['kmTarifaCadete']);

                // ✅ monto guardado (esto es lo que el cadete ganó)
                final monto = _toDouble(data['montoCadete']);
                totalDia += monto;

                return ListTile(
                  leading: const Icon(Icons.receipt),
                  title: Text('Cliente: $cliente'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local: $localNombre'),
                      Text(
                        'Distancia: ${distanciaParaMostrar.toStringAsFixed(1)} km',
                      ),
                      if (kmTarifaGuardada > 0)
                        Text(
                          'Tarifa: ${kmTarifaGuardada.toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (fecha != null)
                        Text('Hora: ${DateFormat('HH:mm').format(fecha)}'),
                    ],
                  ),
                  trailing: Text(
                    '\$${monto.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList();

              return ExpansionTile(
                title: Text(
                  '📅 $fechaFormateada - Total: \$${totalDia.toStringAsFixed(0)} - Entregas: ${entregas.length}',
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
