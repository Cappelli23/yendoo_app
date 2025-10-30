import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminLocalesScreen extends StatefulWidget {
  const AdminLocalesScreen({super.key});

  @override
  State<AdminLocalesScreen> createState() => _AdminLocalesScreenState();
}

class _AdminLocalesScreenState extends State<AdminLocalesScreen> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _localesF;

  @override
  void initState() {
    super.initState();
    _localesF = FirebaseFirestore.instance
        .collection('usuarios')
        .where('rol', isEqualTo: 'local')
        .get()
        .then((s) => s.docs);
  }

  Future<void> _mostrarHistorial(String localId, String nombre) async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(localId)
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
                (suma, d) => suma + (d['montoTotal'] ?? 0).toDouble(),
              );

              return ExpansionTile(
                title: Text('$dia – ${pedidos.length} pedidos'),
                subtitle: Text('Total: \$${totalDia.toStringAsFixed(0)}'),
                children: pedidos.map((d) {
                  final cliente = d['cliente'] ?? '';
                  final fecha = (d['fecha'] as Timestamp?)?.toDate();
                  final distancia =
                      d['distancia_km']?.toStringAsFixed(1) ?? '?';
                  final monto = (d['montoTotal'] ?? 0).toDouble();
                  final cadete = d['cadeteNombre'] ?? 'Cadete';

                  return ListTile(
                    dense: true,
                    title: Text('$cliente – \$${monto.toStringAsFixed(0)}'),
                    subtitle: Text(
                      'Distancia: $distancia km – $cadete\n${fecha != null ? DateFormat('HH:mm').format(fecha) : ''}',
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
        title: const Text('Locales registrados'),
        backgroundColor: Colors.lightBlue,
        centerTitle: true,
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _localesF,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final locales = snapshot.data ?? [];
          if (locales.isEmpty) {
            return const Center(child: Text('No hay locales cargados.'));
          }

          return ListView.separated(
            itemCount: locales.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final data = locales[i].data();
              final nombre = data['nombre'] ?? 'Sin nombre';
              final telefono = data['telefono'] ?? '';

              return ListTile(
                leading: const Icon(Icons.store, color: Colors.teal),
                title: Text(nombre),
                subtitle: Text('Tel: $telefono'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _mostrarHistorial(locales[i].id, nombre),
              );
            },
          );
        },
      ),
    );
  }
}
