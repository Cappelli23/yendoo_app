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
                final distancia = (data['distancia'] ?? 0).toDouble();
                final montoTotal = (data['montoTotal'] ?? 0).toDouble();
                totalDia += montoTotal;

                final cliente = data['cliente'] ?? 'Cliente';
                final cadete = data['cadeteNombre'] ?? 'Cadete';

                return ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Cliente: $cliente'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entregado por: $cadete'),
                      Text('Distancia: ${distancia.toStringAsFixed(1)} km'),
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
                  '📅 $fechaBonita – Total: \$${totalDia.toStringAsFixed(0)} – Pedidos: ${pedidos.length}',
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
