import 'package:cloud_firestore/cloud_firestore.dart';

class PedidosCadeteRepository {
  PedidosCadeteRepository(this._db);
  final FirebaseFirestore _db;

  /// Pedidos del local en estado LISTO y sin cadete (o asignados a mí).
  Stream<QuerySnapshot<Map<String, dynamic>>> listosParaRetiro({
    required String localId,
    required String cadeteUid,
  }) {
    return _db
        .collection('pedidosEnCurso')
        .where('idLocal', isEqualTo: localId)
        .where('estado', isEqualTo: 'listo')
        .where(Filter.or(
          Filter('cadeteId', isEqualTo: null),
          Filter('cadeteId', isEqualTo: cadeteUid),
        ))
        .orderBy('fechaCreado', descending: true)
        .snapshots();
  }

  /// Tomar y marcar como RETIRADO (transacción para evitar carreras).
  Future<void> tomarYRetirar({
    required DocumentReference<Map<String, dynamic>> ref,
    required String cadeteUid,
  }) async {
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final cur = snap.data();

      if (cur == null) throw 'El pedido ya no existe.';
      final estado = (cur['estado'] ?? '').toString();
      final cadeteId = cur['cadeteId'];

      if (estado != 'listo') {
        throw 'El pedido aún no está listo para retirar.';
      }
      if (cadeteId != null && cadeteId != cadeteUid) {
        throw 'Otro cadete ya tomó este pedido.';
      }

      tx.update(ref, {
        'cadeteId': cadeteUid,
        'estadoCadete': 'retirado',
        'cadeteAsignadoAt': FieldValue.serverTimestamp(),
        'cadeteRetiradoAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// ENTREGADO AL CLIENTE (solo si el local habilitó cadetePuedeEntregar = true).
  Future<void> marcarEntregadoPorCadete({
    required DocumentReference<Map<String, dynamic>> ref,
  }) async {
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final cur = snap.data();

      if (cur == null) throw 'El pedido ya no existe.';
      final puede = (cur['cadetePuedeEntregar'] == true);

      if (!puede) {
        throw 'Aún no habilitado por el local. Esperá a que el local te entregue el pedido.';
      }

      tx.update(ref, {
        'estadoCadete': 'entregado',
        'cadeteEntregadoAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
