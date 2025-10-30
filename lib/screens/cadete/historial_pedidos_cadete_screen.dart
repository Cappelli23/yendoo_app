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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

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
    if (_uid == null) {
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
            return const Center(child: Text('Aún no se registran entregas.'));
          }

          final docs = snapshot.data!.docs;

          // Agrupar por día
          final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
              entregasPorDia = {};
          for (var doc in docs) {
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
                final cliente = data['cliente'] ?? 'Cliente';
                final localNombre = data['localNombre'] ?? 'Local';
                final distancia = (data['distancia'] ?? 0).toDouble();
                final monto = (data['montoCadete'] ?? 0).toDouble();
                totalDia += monto;

                return ListTile(
                  leading: const Icon(Icons.receipt),
                  title: Text('Cliente: $cliente'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local: $localNombre'),
                      Text('Distancia: ${distancia.toStringAsFixed(1)} km'),
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
                  '📅 $fechaFormateada – Total: \$${totalDia.toStringAsFixed(0)} – Entregas: ${entregas.length}',
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
