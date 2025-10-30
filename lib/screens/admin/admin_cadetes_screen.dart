import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminCadetesScreen extends StatefulWidget {
  const AdminCadetesScreen({super.key});

  @override
  State<AdminCadetesScreen> createState() => _AdminCadetesScreenState();
}

class _AdminCadetesScreenState extends State<AdminCadetesScreen> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cadetesF;

  @override
  void initState() {
    super.initState();
    _cadetesF = FirebaseFirestore.instance
        .collection('usuarios')
        .where('rol', isEqualTo: 'cadete')
        .get()
        .then((s) => s.docs);
  }

  Future<void> _mostrarHistorial(String cadeteId, String nombre) async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(cadeteId)
        .collection('historial')
        .orderBy('fecha', descending: true)
        .limit(200)
        .get();

    final docs = snap.docs;
    if (!mounted) return;

    // Agrupar por día
    final Map<String, List<Map<String, dynamic>>> agrupado = {};
    for (var doc in docs) {
      final data = doc.data();
      final fecha = (data['fecha'] as Timestamp?)?.toDate();
      if (fecha == null) continue;

      final dia = DateFormat('dd/MM/yyyy').format(fecha);
      agrupado[dia] = [...agrupado[dia] ?? [], data];
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Historial de $nombre'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: agrupado.entries.map((entry) {
              final dia = entry.key;
              final pedidos = entry.value;

              final totalDia = pedidos.fold<double>(
                0,
                (suma, d) => suma + (d['montoCadete'] ?? 0).toDouble(),
              );

              return ExpansionTile(
                title: Text('$dia – ${pedidos.length} entregas'),
                subtitle: Text('Total: \$${totalDia.toStringAsFixed(0)}'),
                children: pedidos.map((d) {
                  final cliente = d['cliente'] ?? '';
                  final local = d['nombreLocal'] ?? '';
                  final fecha = (d['fecha'] as Timestamp).toDate();
                  final distancia =
                      d['distancia_km']?.toStringAsFixed(1) ?? '?';
                  final monto = (d['montoCadete'] ?? 0).toDouble();

                  return ListTile(
                    dense: true,
                    title: Text('$cliente – \$${monto.toStringAsFixed(0)}'),
                    subtitle: Text(
                      '$local • $distancia km\n${DateFormat('HH:mm').format(fecha)}',
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadetes registrados'),
        backgroundColor: Colors.lightBlue,
        centerTitle: true,
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _cadetesF,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final cadetes = snap.data ?? [];
          if (cadetes.isEmpty) {
            return const Center(child: Text('No hay cadetes cargados.'));
          }

          return ListView.separated(
            itemCount: cadetes.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final data = cadetes[i].data();
              final nombre = data['nombre'] ?? 'Sin nombre';
              final tel = data['telefono'] ?? '';

              return ListTile(
                leading: const Icon(Icons.delivery_dining, color: Colors.teal),
                title: Text(nombre),
                subtitle: Text('Tel: $tel'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _mostrarHistorial(cadetes[i].id, nombre),
              );
            },
          );
        },
      ),
    );
  }
}
