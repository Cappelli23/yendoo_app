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
  
 // ======================================================
 // YENDO - ACTIVAR CADETES SEGÚN HORARIO DE TRABAJO
 // ======================================================

exports.actualizarDisponibilidadCadetes = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("America/Montevideo")
  .onRun(async () => {
    const db = admin.firestore();

    const ahora = new Date();

    const partes = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Montevideo",
      weekday: "long",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(ahora);

    const obtener = (tipo) =>
      partes.find((p) => p.type === tipo)?.value;

    const diaActual = obtener("weekday");
    const horaActual = Number(obtener("hour"));
    const minutoActual = Number(obtener("minute"));

    const dias = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
    ];

    const diasFirestore = [
      "Domingo",
      "Lunes",
      "Martes",
      "Miércoles",
      "Jueves",
      "Viernes",
      "Sábado",
    ];

    const indiceDia = dias.indexOf(diaActual);

    if (indiceDia === -1) {
      console.error("No se pudo identificar el día:", diaActual);
      return null;
    }

    const minutosActuales = horaActual * 60 + minutoActual;

    function convertirMinutos(hora) {
      if (typeof hora !== "string") return null;

      const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(hora);
      if (!match) return null;

      return Number(match[1]) * 60 + Number(match[2]);
    }

    function estaEnHorario(horarios) {
      if (!horarios || typeof horarios !== "object") {
        return false;
      }

      const dia = diasFirestore[indiceDia];
      const diaAnterior =
        diasFirestore[(indiceDia + 6) % 7];

      const horarioHoy = horarios[dia];

      if (horarioHoy?.activo === true) {
        const inicio = convertirMinutos(horarioHoy.desde);
        const fin = convertirMinutos(horarioHoy.hasta);

        if (inicio !== null && fin !== null) {
          if (inicio < fin &&
              minutosActuales >= inicio &&
              minutosActuales < fin) {
            return true;
          }

          if (inicio > fin &&
              minutosActuales >= inicio) {
            return true;
          }
        }
      }

      // Horarios del día anterior que cruzan medianoche.
      const horarioAyer = horarios[diaAnterior];

      if (horarioAyer?.activo === true) {
        const inicio = convertirMinutos(horarioAyer.desde);
        const fin = convertirMinutos(horarioAyer.hasta);

        if (inicio !== null &&
            fin !== null &&
            inicio > fin &&
            minutosActuales < fin) {
          return true;
        }
      }

      return false;
    }

    const snapshot = await db
      .collection("usuarios")
      .where("rol", "==", "cadete")
      .get();

    let actualizados = 0;
    let batch = db.batch();
    let operaciones = 0;

    for (const doc of snapshot.docs) {
      const datos = doc.data();

      const debeEstarActivo =
        estaEnHorario(datos.horariosTrabajo);

      // Evita escrituras innecesarias.
      if (datos.activo === debeEstarActivo) {
        continue;
      }

      batch.update(doc.ref, {
        activo: debeEstarActivo,
      });

      actualizados++;
      operaciones++;

      if (operaciones === 400) {
        await batch.commit();
        batch = db.batch();
        operaciones = 0;
      }
    }

    if (operaciones > 0) {
      await batch.commit();
    }

    console.log(
      `Cadetes revisados: ${snapshot.size}. ` +
      `Disponibilidades actualizadas: ${actualizados}.`
    );

    return null;
  });
