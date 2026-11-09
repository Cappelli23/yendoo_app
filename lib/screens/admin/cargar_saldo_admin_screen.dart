import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CargarSaldoAdminScreen extends StatefulWidget {
  const CargarSaldoAdminScreen({super.key});

  @override
  State<CargarSaldoAdminScreen> createState() => _CargarSaldoAdminScreenState();
}

class _CargarSaldoAdminScreenState extends State<CargarSaldoAdminScreen> {
  final TextEditingController _buscarController = TextEditingController();

  String _busqueda = '';
  bool _guardando = false;

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargarSaldo(
    String uidLocal,
    String nombreLocal,
    num saldoActual,
  ) async {
    String importeIngresado = '';
    final monto = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cargar saldo a $nombreLocal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo actual: \$${saldoActual.toStringAsFixed(0)}'),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (valor) {
                importeIngresado = valor;
              },
              decoration: const InputDecoration(
                labelText: 'Importe a cargar',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = int.tryParse(importeIngresado.trim());
              if (valor == null || valor <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresá un importe válido'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext, valor);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (monto == null || !mounted || _guardando) return;

    setState(() => _guardando = true);

    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;

      if (adminUid == null) {
        throw Exception('No hay administrador autenticado');
      }

      final db = FirebaseFirestore.instance;
      final localRef = db.collection('usuarios').doc(uidLocal);
      final movimientoRef = localRef.collection('movimientosSaldo').doc();

      await db.runTransaction((transaction) async {
        final localDoc = await transaction.get(localRef);

        if (!localDoc.exists) {
          throw Exception('El local ya no existe');
        }

        final data = localDoc.data()!;
        if (data['rol'] != 'local') {
          throw Exception('El usuario no es un local');
        }

        final saldoAnterior = data['saldo'];

        if (saldoAnterior != null &&
            (saldoAnterior is! num ||
                !saldoAnterior.isFinite ||
                saldoAnterior < 0 ||
                saldoAnterior % 1 != 0)) {
          throw Exception('El saldo actual no es válido');
        }

        final anterior = (saldoAnterior as num?)?.toInt() ?? 0;
        final nuevoSaldo = anterior + monto;

        transaction.update(localRef, {
          'saldo': nuevoSaldo,
        });

        transaction.set(movimientoRef, {
          'tipo': 'recarga',
          'monto': monto,
          'saldoAnterior': anterior,
          'saldoNuevo': nuevoSaldo,
          'adminUid': adminUid,
          'fecha': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se cargaron \$$monto a $nombreLocal',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar el saldo: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      appBar: AppBar(
        title: const Text('Cargar saldo'),
        backgroundColor: Colors.lightBlue,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _buscarController,
              onChanged: (valor) {
                setState(() {
                  _busqueda = valor.toLowerCase().trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Buscar local...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .where('rol', isEqualTo: 'local')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar locales: ${snapshot.error}',
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final locales = snapshot.data!.docs.where((doc) {
                  final nombre = (doc.data()['nombre'] ?? '').toString();
                  return nombre.toLowerCase().contains(_busqueda);
                }).toList();

                locales.sort((a, b) {
                  final nombreA = (a.data()['nombre'] ?? '').toString();
                  final nombreB = (b.data()['nombre'] ?? '').toString();

                  return nombreA.compareTo(nombreB);
                });

                if (locales.isEmpty) {
                  return const Center(
                    child: Text('No se encontraron locales'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: locales.length,
                  itemBuilder: (context, index) {
                    final doc = locales[index];
                    final data = doc.data();

                    final nombre = (data['nombre'] ?? 'Sin nombre').toString();

                    final saldo = data['saldo'];

                    final saldoValido = saldo is num &&
                        saldo.isFinite &&
                        saldo >= 0 &&
                        saldo % 1 == 0;

                    final saldoActual = saldoValido ? saldo : 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              saldo == null
                                  ? 'Saldo no configurado'
                                  : saldoValido
                                      ? 'Saldo disponible: \$${saldoActual.toStringAsFixed(0)}'
                                      : 'Saldo inválido en Firebase',
                              style: TextStyle(
                                fontSize: 16,
                                color: saldoValido
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed:
                                  _guardando || (saldo != null && !saldoValido)
                                      ? null
                                      : () => _cargarSaldo(
                                            doc.id,
                                            nombre,
                                            saldoActual,
                                          ),
                              icon: const Icon(Icons.add),
                              label: const Text('Cargar saldo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
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
