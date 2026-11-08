const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
  UpdateCommand,
  ScanCommand,
} = require("@aws-sdk/lib-dynamodb");
const crypto = require("crypto");

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Credentials": true,
  "Access-Control-Allow-Headers": "Content-Type,x-admin-token,X-Admin-Token",
  "Access-Control-Allow-Methods": "OPTIONS,POST,GET,PUT",
};

// 1. POST: Crear un reporte con coordenadas 3D y datos del alumno que reporta
module.exports.crearReporte = async (event) => {
  let data;
  try {
    if (!event.body) throw new Error("Cuerpo vacío");
    data = JSON.parse(event.body);
  } catch (error) {
    return {
      statusCode: 400,
      headers: corsHeaders,
      body: JSON.stringify({ error: "JSON inválido" }),
    };
  }

  const params = {
    TableName: "ReportesTabla",
    Item: {
      reporteId: crypto.randomUUID(),
      tipo: data.tipo,
      descripcion: data.descripcion,
      ubicacion_qr: data.ubicacion_qr,
      coordenadas_ar: data.coordenadas_ar,
      estado: "Pendiente",
      fecha: new Date().toISOString(),
      creado_por_nombre: data.creado_por_nombre || "Estudiante UAQ",
      creado_por_correo: data.creado_por_correo || "alumno@alumnos.uaq.mx",
    },
  };

  try {
    await docClient.send(new PutCommand(params));
    return {
      statusCode: 201,
      headers: corsHeaders,
      body: JSON.stringify({ mensaje: "Pin AR creado", reporte: params.Item }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Error interno" }),
    };
  }
};

// 2. GET: Obtener todos los pines pendientes de un salón o stand específico
module.exports.obtenerPinesAR = async (event) => {
  const ubicacion_qr = event.pathParameters.ubicacion_qr;

  const params = {
    TableName: "ReportesTabla",
    IndexName: "UbicacionIndex",
    KeyConditionExpression: "ubicacion_qr = :qr",
    FilterExpression: "estado = :estado",
    ExpressionAttributeValues: {
      ":qr": ubicacion_qr,
      ":estado": "Pendiente",
    },
  };

  try {
    const result = await docClient.send(new QueryCommand(params));
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ pines_ar: result.Items }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Error al obtener pines" }),
    };
  }
};

// 3. PUT: Marcar como resuelto guardando evidencia, acción y datos del técnico
module.exports.resolverReporte = async (event) => {
  const headers = event.headers || {};
  const token = headers["x-admin-token"] || headers["X-Admin-Token"];

  if (token !== "super-secreto-uaq-2026") {
    return {
      statusCode: 403,
      headers: corsHeaders,
      body: JSON.stringify({
        error:
          "Acceso denegado. Solo el personal de mantenimiento puede resolver reportes.",
      }),
    };
  }

  const reporteId = event.pathParameters.reporteId;
  let bodyData = {};
  try {
    if (event.body) {
      bodyData = JSON.parse(event.body);
    }
  } catch (_) {}

  const params = {
    TableName: "ReportesTabla",
    Key: { reporteId: reporteId },
    UpdateExpression:
      "set estado = :nuevoEstado, resuelto_por_nombre = :tecNombre, resuelto_por_correo = :tecCorreo, accion_realizada = :accion, evidencia_resolucion = :evidencia, fecha_resolucion = :fechaRes",
    ExpressionAttributeValues: {
      ":nuevoEstado": "Resuelto",
      ":tecNombre": bodyData.resuelto_por_nombre || "Personal de Mantenimiento",
      ":tecCorreo": bodyData.resuelto_por_correo || "soporte@mantenimiento.uaq.mx",
      ":accion": bodyData.accion_realizada || "Mantenimiento correctivo completado",
      ":evidencia":
        bodyData.evidencia_resolucion ||
        "Se realizó la inspección física y reparación del elemento reportado.",
      ":fechaRes": new Date().toISOString(),
    },
    ReturnValues: "ALL_NEW",
  };

  try {
    const result = await docClient.send(new UpdateCommand(params));
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        mensaje: "Reparado exitosamente",
        reporte: result.Attributes,
      }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Error al actualizar" }),
    };
  }
};

// 4. GET: Obtener TODOS los reportes globales (Dashboard Web y Centro de Notificaciones)
module.exports.obtenerTodosReportes = async () => {
  const params = {
    TableName: "ReportesTabla",
  };

  try {
    const result = await docClient.send(new ScanCommand(params));
    const items = result.Items || [];
    items.sort((a, b) => (b.fecha || "").localeCompare(a.fecha || ""));

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ reportes: items }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Error al obtener todos los reportes" }),
    };
  }
};