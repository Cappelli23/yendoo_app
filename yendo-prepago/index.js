
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

const db = getFirestore();

const TARIFAS = [
  80, 100, 120, 140, 160, 180, 200, 220, 240,
];

function calcularTarifa(distanciaKm) {
  if (
    typeof distanciaKm !== "number" ||
    !Number.isFinite(distanciaKm) ||
    distanciaKm < 0 ||
    distanciaKm > 8.5
  ) {
    throw new HttpsError(
      "invalid-argument",
      "La distancia debe estar entre 0 y 8.5 km."
    );
  }

  const tramo = Math.max(1, Math.ceil(distanciaKm));
  return TARIFAS[tramo - 1];
}


function calcularDistanciaKm(origen, destino) {
  const validar = (punto) =>
    punto &&
    typeof punto.lat === "number" &&
    typeof punto.lng === "number" &&
    Number.isFinite(punto.lat) &&
    Number.isFinite(punto.lng) &&
    Math.abs(punto.lat) <= 90 &&
    Math.abs(punto.lng) <= 180;

  if (!validar(origen) || !validar(destino)) {
    throw new HttpsError(
      "invalid-argument",
      "Las coordenadas del envío no son válidas."
    );
  }

  const rad = (grados) => grados * Math.PI / 180;
  const dLat = rad(destino.lat - origen.lat);
  const dLng = rad(destino.lng - origen.lng);

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(origen.lat)) *
      Math.cos(rad(destino.lat)) *
      Math.sin(dLng / 2) ** 2;

  const distanciaMetros =
    6371000 * 2 * Math.atan2(
      Math.sqrt(a),
      Math.sqrt(Math.max(0, 1 - a))
    );

  // Misma presentación de distancia en tramos de 100 metros.
  return Math.ceil(distanciaMetros / 100) / 10;
}

exports.consultarPrepagoYendo = onCall(
  {
    region: "southamerica-east1",
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Debés iniciar sesión."
      );
    }

    const uid = request.auth.uid;
    const localSnap = await db.collection("usuarios").doc(uid).get();

    if (!localSnap.exists || localSnap.get("rol") !== "local") {
      throw new HttpsError(
        "permission-denied",
        "Esta operación es exclusiva para locales."
      );
    }

    const local = localSnap.data();
    const prepagoActivo = local.saldoPrepagoActivo === true;

    return {
      prepagoActivo,
      saldo: prepagoActivo ? local.saldo ?? 0 : null,
    };
  }
);
exports.crearPedidoYendo = onCall(
  {
    region: "southamerica-east1",
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Debés iniciar sesión."
      );
    }

    const uid = request.auth.uid;
    const datos = request.data || {};

    const {
      orderId,
      tipo,
      cliente,
      telefonoCliente,
      ubicacionDestino,
      cadetesAsignados,
      tiempoPreparacion,
    } = datos;

    if (
      typeof orderId !== "string" ||
      !/^[a-zA-Z0-9_-]{10,100}$/.test(orderId)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Identificador de pedido inválido."
      );
    }

    if (tipo !== "normal" && tipo !== "personalizado") {
      throw new HttpsError(
        "invalid-argument",
        "Tipo de pedido inválido."
      );
    }

    if (
      typeof cliente !== "string" ||
      !cliente.trim() ||
      cliente.length > 150 ||
      typeof telefonoCliente !== "string" ||
      !telefonoCliente.trim() ||
      telefonoCliente.length > 40
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Datos del cliente inválidos."
      );
    }

    const validarCoordenadas = (punto) =>
      punto &&
      typeof punto.lat === "number" &&
      typeof punto.lng === "number" &&
      Number.isFinite(punto.lat) &&
      Number.isFinite(punto.lng) &&
      Math.abs(punto.lat) <= 90 &&
      Math.abs(punto.lng) <= 180;

    if (!validarCoordenadas(ubicacionDestino)) {
      throw new HttpsError(
        "invalid-argument",
        "Ubicación de destino inválida."
      );
    }

    if (tipo === "personalizado") {
      if (
        !Array.isArray(cadetesAsignados) ||
        cadetesAsignados.length < 1 ||
        cadetesAsignados.length > 12 ||
        !cadetesAsignados.every(
          (id) => typeof id === "string" && id.length > 0
        ) ||
        new Set(cadetesAsignados).size !== cadetesAsignados.length
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Seleccioná entre 1 y 12 cadetes diferentes."
        );
      }

      if (
        !Number.isInteger(tiempoPreparacion) ||
        tiempoPreparacion < 5 ||
        tiempoPreparacion > 30
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Tiempo de preparación inválido."
        );
      }
    }

    const localRef = db.collection("usuarios").doc(uid);
    const pedidoRef = db.collection("pedidosEnCurso").doc(orderId);

    return await db.runTransaction(async (txn) => {
      const pedidoExistente = await txn.get(pedidoRef);

      if (pedidoExistente.exists) {
        if (pedidoExistente.get("idLocal") !== uid) {
          throw new HttpsError(
            "permission-denied",
            "El identificador pertenece a otro local."
          );
        }

        return {
          creado: false,
          pedidoId: orderId,
          mensaje: "Este pedido ya fue confirmado.",
        };
      }

      const localSnap = await txn.get(localRef);

      if (
        !localSnap.exists ||
        localSnap.get("rol") !== "local"
      ) {
        throw new HttpsError(
          "permission-denied",
          "Solo los locales pueden generar pedidos."
        );
      }

      const local = localSnap.data();
      const origen = local.ubicacion;

      if (!validarCoordenadas(origen)) {
        throw new HttpsError(
          "failed-precondition",
          "El local no tiene una ubicación válida."
        );
      }

      const distanciaKm = calcularDistanciaKm(
        origen,
        ubicacionDestino
      );

      const costoEnvio = calcularTarifa(distanciaKm);
      const gananciaAdmin = 15;
      const montoCadete = costoEnvio - gananciaAdmin;

      const pedidoData = {
        clientOrderId: orderId,
        idLocal: uid,
        cliente: cliente.trim(),
        telefonoCliente: telefonoCliente.trim(),
        estado: "pendiente",
        tipo,
        fechaCreado: new Date(),
        ubicacionOrigen: {
          lat: origen.lat,
          lng: origen.lng,
        },
        ubicacionDestino: {
          lat: ubicacionDestino.lat,
          lng: ubicacionDestino.lng,
        },
        distanciaKmMostrable: distanciaKm,
        distanciaKmReal: distanciaKm,
        distancia_km: distanciaKm,
        montoCadete,
        montoGananciaAdmin: gananciaAdmin,
        montoTotal: costoEnvio,
      };

      if (tipo === "personalizado") {
        const favoritos = local.cadetesFavoritos;

        if (
          !Array.isArray(favoritos) ||
          !cadetesAsignados.every((id) => favoritos.includes(id))
        ) {
          throw new HttpsError(
            "permission-denied",
            "Hay cadetes seleccionados que no pertenecen a los favoritos del local."
          );
        }

        Object.assign(pedidoData, {
          tiempoPreparacion,
          descripcion: "Pedido personalizado desde mapa",
          cadetesAsignados,
          localNombre: local.nombre || "Local",
          kmTarifaLocal: distanciaKm,
          kmTarifaCadete: distanciaKm,
          asignado: null,
        });
      }

      if (local.saldoPrepagoActivo !== true) {
  throw new HttpsError(
    "failed-precondition",
    "El sistema prepago no está habilitado para este local. Contactá a Yendo."
  );
}

{
        const saldoActual = local.saldo;

        if (
          typeof saldoActual !== "number" ||
          !Number.isSafeInteger(saldoActual) ||
          saldoActual < 0
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Saldo inválido. Contactá a Yendo."
          );
        }

        if (saldoActual < costoEnvio) {
          throw new HttpsError(
            "failed-precondition",
            `Saldo insuficiente. Tenés $${saldoActual} y el envío cuesta $${costoEnvio}.`
          );
        }

        const saldoNuevo = saldoActual - costoEnvio;

        const movimientoRef = localRef
          .collection("movimientosSaldo")
          .doc(`pedido_${orderId}`);

        txn.update(localRef, {
          saldo: saldoNuevo,
        });

        txn.set(movimientoRef, {
          tipo: "descuento_pedido",
          pedidoId: orderId,
          monto: -costoEnvio,
          saldoAnterior: saldoActual,
          saldoNuevo,
          fecha: new Date(),
        });
      }

      txn.create(pedidoRef, pedidoData);

      return {
        creado: true,
        pedidoId: orderId,
        costoEnvio,
        distanciaKm,
        prepagoActivo: local.saldoPrepagoActivo === true,
      };
    });
  }
);
exports.cancelarPedidoYendo = onCall(
  {
    region: "southamerica-east1",
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debés iniciar sesión.");
    }

    const uid = request.auth.uid;
    const pedidoId = request.data?.pedidoId;

    if (
      typeof pedidoId !== "string" ||
      !/^[a-zA-Z0-9_-]{10,100}$/.test(pedidoId)
    ) {
      throw new HttpsError("invalid-argument", "Pedido inválido.");
    }

    const pedidoRef = db.collection("pedidosEnCurso").doc(pedidoId);
    const localRef = db.collection("usuarios").doc(uid);
    const movimientoRef = localRef
      .collection("movimientosSaldo")
      .doc(`pedido_${pedidoId}`);
    const devolucionRef = localRef
      .collection("movimientosSaldo")
      .doc(`devolucion_${pedidoId}`);

    return await db.runTransaction(async (txn) => {
      const pedidoSnap = await txn.get(pedidoRef);

      if (!pedidoSnap.exists) {
        throw new HttpsError("not-found", "El pedido ya no existe.");
      }

      const pedido = pedidoSnap.data();

      if (pedido.idLocal !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Este pedido no pertenece a tu local."
        );
      }

      if (pedido.estado !== "pendiente" || pedido.asignado) {
        throw new HttpsError(
          "failed-precondition",
          "El pedido ya fue aceptado y no se puede eliminar."
        );
      }

      const movimientoSnap = await txn.get(movimientoRef);
      const devolucionSnap = await txn.get(devolucionRef);

      if (devolucionSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Este pedido ya tiene una devolución registrada."
        );
      }

      let devolucion = 0;

      if (movimientoSnap.exists) {
        const movimiento = movimientoSnap.data();
        const montoDescontado = movimiento.monto;

        if (
          movimiento.tipo !== "descuento_pedido" ||
          !Number.isSafeInteger(montoDescontado) ||
          montoDescontado >= 0
        ) {
          throw new HttpsError(
            "failed-precondition",
            "El descuento original no es válido."
          );
        }

        devolucion = -montoDescontado;

        const localSnap = await txn.get(localRef);

        if (!localSnap.exists) {
          throw new HttpsError(
            "not-found",
            "No se encontró el local."
          );
        }

        const saldoActual = localSnap.get("saldo");

        if (
          !Number.isSafeInteger(saldoActual) ||
          saldoActual < 0 ||
          !Number.isSafeInteger(saldoActual + devolucion)
        ) {
          throw new HttpsError(
            "failed-precondition",
            "El saldo del local no es válido."
          );
        }

        const saldoNuevo = saldoActual + devolucion;

        txn.update(localRef, { saldo: saldoNuevo });

        txn.create(devolucionRef, {
          tipo: "devolucion_pedido",
          pedidoId,
          monto: devolucion,
          saldoAnterior: saldoActual,
          saldoNuevo,
          fecha: new Date(),
        });
      }

      txn.delete(pedidoRef);

      return {
        eliminado: true,
        pedidoId,
        devolucion,
      };
    });
  }
);