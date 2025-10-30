import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MisPedidosScreen extends StatefulWidget {
  const MisPedidosScreen({super.key});

  @override
  State<MisPedidosScreen> createState() => _MisPedidosScreenState();
}

class _MisPedidosScreenState extends State<MisPedidosScreen> {
  String? _localId;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      setState(() => _localId = uid);
    }
  }

  Future<void> _updateEstado(
    String docId,
    String nuevoEstado, {
    Map<String, dynamic>? extra,
  }) async {
    final patch = <String, dynamic>{
      'estado': nuevoEstado,
      'updatedAt': FieldValue.serverTimestamp(),
      ...?extra,
    };
    await FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .doc(docId)
        .update(patch);
  }

  Future<void> _aceptar(String docId) =>
      _updateEstado(docId, 'aceptado', extra: {
        'fechaAceptado': FieldValue.serverTimestamp(),
      });

  Future<void> _marcarListo(String docId) =>
      _updateEstado(docId, 'listo', extra: {
        'fechaListo': FieldValue.serverTimestamp(),
      });

  Future<void> _entregarAlCadete(String docId) =>
      _updateEstado(docId, 'entregado_al_cadete', extra: {
        'fechaEntregadoAlCadete': FieldValue.serverTimestamp(),
      });

  // -------- Helpers de pago --------
  String _labelMetodo(String v) {
    switch (v) {
      case 'debito':
        return 'débito';
      case 'efectivo':
        return 'efectivo';
      case 'transferencia':
        return 'transferencia';
      case 'credito':
        return 'crédito';
      case 'qr':
        return 'QR';
      default:
        return v;
    }
  }

  String _labelVia(String? v) {
    switch (v) {
      case 'pos':
        return 'POS';
      case 'link':
        return 'link';
      default:
        return '';
    }
  }

  Widget _pagoChip(Map<String, dynamic> data) {
    // Prioridad: campos planos -> objeto pago -> string resumen
    String? metodo = data['pagoMetodo'] as String?;
    num? monto = data['pagoMonto'] as num?;
    String? via = data['pagoVia'] as String?;

    final pago = (data['pago'] as Map?)?.cast<String, dynamic>();
    metodo ??= pago?['metodo'] as String?;
    monto ??= pago?['monto'] as num?;
    via ??= pago?['via'] as String?;

    final resumen = data['pagoResumen'];

    final cs = Theme.of(context).colorScheme;
    final chipColor = cs.primaryContainer.withValues(alpha: 0.30);

    if (metodo == null || monto == null) {
      if (resumen is String && resumen.trim().isNotEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            resumen,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final f = NumberFormat.currency(locale: 'es_UY', symbol: r'$');
    final viaTxt = _labelVia(via);
    final metodoTxt = _labelMetodo(metodo);
    final texto = viaTxt.isNotEmpty
        ? '${f.format(monto)} ($metodoTxt · $viaTxt)'
        : '${f.format(monto)} ($metodoTxt)';

    IconData icono() {
      if (metodo == 'debito') {
        if (via == 'pos') return Icons.point_of_sale;
        if (via == 'link') return Icons.link;
        return Icons.credit_card;
      }
      switch (metodo) {
        case 'efectivo':
          return Icons.attach_money;
        case 'transferencia':
          return Icons.swap_horiz;
        case 'credito':
          return Icons.credit_card;
        case 'qr':
          return Icons.qr_code_scanner;
        default:
          return Icons.payments_outlined;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono(), size: 18),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    if (_localId == null) {
      return const Scaffold(
        body: Center(child: Text('Usuario no autenticado.')),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('pedidosEnCurso')
        .where('idLocal', isEqualTo: _localId)
        .where('estado', whereIn: ['pendiente', 'aceptado', 'listo'])
        .orderBy('fechaCreado', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos en curso')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay pedidos en curso.'));
          }

          final pedidos = snapshot.data!.docs;
          return ListView.builder(
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              final doc = pedidos[index];
              final data = doc.data();

              final estado = (data['estado'] ?? 'pendiente').toString();

              final fechaTimestamp = estado == 'aceptado'
                  ? data['fechaAceptado']
                  : data['fechaCreado'];

              final fechaTexto = fechaTimestamp is Timestamp
                  ? DateFormat('dd/MM – HH:mm').format(fechaTimestamp.toDate())
                  : 'Fecha no disponible';

              final cliente = (data['cliente'] ?? 'Cliente').toString();

              // Fallback: algunos docs usan 'total' en lugar de 'montoTotal'
              double montoTotal = 0.0;
              if (data['montoTotal'] is num) {
                montoTotal = (data['montoTotal'] as num).toDouble();
              } else if (data['total'] is num) {
                montoTotal = (data['total'] as num).toDouble();
              }

              final destino = data['ubicacionDestino'];
              final asignado = (data['asignado'] as Map?) ?? {};
              final cadeteNombre = (asignado['cadeteNombre'] ?? '').toString();

              final estadoTexto = () {
                switch (estado) {
                  case 'pendiente':
                    return 'Pendiente (sin cadete)';
                  case 'aceptado':
                    return cadeteNombre.trim().isNotEmpty
                        ? 'Aceptado por $cadeteNombre'
                        : 'Aceptado';
                  case 'listo':
                    return 'Listo para entregar al cadete';
                  default:
                    return estado;
                }
              }();

              final colorEstado = switch (estado) {
                'aceptado' => Colors.blue,
                'listo' => Colors.teal,
                'pendiente' => Colors.orange,
                _ => Colors.grey,
              };

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.local_shipping, color: colorEstado),
                        title: Text('Cliente: $cliente'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Estado: $estadoTexto'),
                            Text('Fecha: $fechaTexto'),
                            Text('Total: \$${montoTotal.toStringAsFixed(0)}'),

                            // 🔹 CHIP de PAGO: "$X (método)" ej. "$200,00 (débito)"
                            const SizedBox(height: 6),
                            _pagoChip(data),

                            if (destino is Map &&
                                destino['lat'] != null &&
                                destino['lng'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Destino: (${(destino['lat'] as num).toStringAsFixed(4)}, ${(destino['lng'] as num).toStringAsFixed(4)})',
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Acciones según estado
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (estado == 'pendiente')
                            FilledButton(
                              onPressed: () async {
                                await _aceptar(doc.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pedido aceptado.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Text('Aceptar'),
                            ),

                          if (estado == 'pendiente')
                            FilledButton.tonal(
                              onPressed: () async {
                                final confirmar = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('¿Eliminar pedido?'),
                                    content: const Text(
                                        '¿Querés eliminar este pedido pendiente?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Eliminar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmar == true) {
                                  await FirebaseFirestore.instance
                                      .collection('pedidosEnCurso')
                                      .doc(doc.id)
                                      .delete();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Pedido eliminado.'),
                                      duration: Duration(seconds: 2),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Eliminar'),
                            ),

                          if (estado == 'aceptado')
                            FilledButton.tonal(
                              onPressed: () async {
                                await _marcarListo(doc.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pedido marcado como LISTO.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Text('Marcar listo'),
                            ),

                          // ENTREGAR AL CADETE (cuando está LISTO)
                          if (estado == 'listo')
                            FilledButton.tonal(
                              onPressed: () async {
                                await _entregarAlCadete(doc.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Entregado al cadete. ¡Listo!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Text('Entregar al cadete'),
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
    );
  }
}
