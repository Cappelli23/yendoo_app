const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

async function getTokensForUids(uids) {
  const tokens = [];
  const uniq = [...new Set(uids)].filter(Boolean);

  for (let i = 0; i < uniq.length; i += 10) {
    const snap = await admin.firestore()
      .collection("usuarios")
      .where(admin.firestore.FieldPath.documentId(), "in", uniq.slice(i, i + 10))
      .get();

    snap.forEach(doc => {
      const t = doc.data().fcmToken;
      if (t) tokens.push(t);
    });
  }
  return tokens;
}

exports.notificarPedidoNuevo = functions.firestore
  .document("pedidosEnCurso/{pedidoId}")
  .onCreate(async (snap, context) => {
    const pedidoId = context.params.pedidoId;
    const pedido = snap.data();
    if (!pedido) return null;

    if ((pedido.estado || "") !== "pendiente") return null;

    const cliente = pedido.cliente || "Nuevo pedido";
    const tipo = (pedido.tipo || "normal").toString();
    const cadetesAsignados = Array.isArray(pedido.cadetesAsignados)
      ? pedido.cadetesAsignados
      : [];

    const esPersonalizado = tipo === "personalizado" || cadetesAsignados.length > 0;

    if (esPersonalizado) {
      const tokens = await getTokensForUids(cadetesAsignados);
      if (!tokens.length) return null;

      return await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Pedido personalizado",
          body: `Te asignaron un pedido (${cliente})`,
        },
        data: {
          tipo: "personalizado",
          pedidoId: String(pedidoId),
          screen: "pedidos_pendientes",
        },
        android: { priority: "high" },
      });
    }

    return await admin.messaging().send({
      topic: "cadetes_activos",
      notification: {
        title: "Nuevo pedido",
        body: `Cliente: ${cliente}`,
      },
      data: {
        tipo: "normal",
        pedidoId: String(pedidoId),
        screen: "pedidos_pendientes",
      },
      android: { priority: "high" },
    });
  });


// ======================================================
// 🔥 NUEVA FUNCIÓN → NOTIFICAR AL LOCAL
// ======================================================

exports.notificarPedidoPendienteLocal = functions.firestore
  .document("pedidosPendientesLocal/{pedidoId}")
  .onCreate(async (snap, context) => {
    try {
      const pedidoId = context.params.pedidoId;
      const pedido = snap.data();

      if (!pedido) return null;

      const localId =
        pedido.localId ||
        pedido.idLocal ||
        pedido.uidLocal ||
        pedido.localUid ||
        pedido.id_local ||
        null;

      if (!localId) {
        console.log("Pedido sin localId:", pedidoId);
        return null;
      }

      const estado = String(pedido.estado || "pendiente").toLowerCase().trim();

      if (
        estado === "aceptado" ||
        estado === "rechazado" ||
        estado === "cancelado" ||
        estado === "entregado"
      ) {
        console.log("Pedido ignorado por estado:", estado);
        return null;
      }

      const localSnap = await admin
        .firestore()
        .collection("locales_public")
        .doc(localId)
        .get();

      if (!localSnap.exists) {
        console.log("Local no encontrado:", localId);
        return null;
      }

      const localData = localSnap.data() || {};

      const token =
        localData.fcmToken ||
        localData.token ||
        localData.notificationToken ||
        localData.deviceToken ||
        null;

      if (!token) {
        console.log("Local sin token:", localId);
        return null;
      }

      const clienteNombre =
        pedido.clienteNombre ||
        pedido.nombreCliente ||
        pedido.cliente ||
        pedido.nombre ||
        "un cliente";

      await admin.messaging().send({
        token,
        notification: {
          title: "Nuevo pedido",
          body: `${clienteNombre} hizo un pedido`,
        },
        data: {
          tipo: "nuevo_pedido_local",
          pedidoId: String(pedidoId),
          localId: String(localId),
          screen: "pedidosPendientesLocal",
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      console.log("Push enviada al local:", pedidoId);

      return null;
    } catch (error) {
      console.error("Error enviando push al local:", error);
      return null;
    }
  });