const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand, QueryCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const crypto = require("crypto");

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

// 1. POST: Crear un reporte con coordenadas 3D
module.exports.crearReporte = async (event) => {
  let data;
  try {
    if (!event.body) throw new Error("Cuerpo vacío");
    data = JSON.parse(event.body);
  } catch (error) {
    return { statusCode: 400, body: JSON.stringify({ error: "JSON inválido" }) };
  }
  
  const params = {
    TableName: "ReportesTabla",
    Item: {
      reporteId: crypto.randomUUID(),
      tipo: data.tipo,
      descripcion: data.descripcion,
      ubicacion_qr: data.ubicacion_qr, // Ej: "qr_salon_3_piso_2"
      coordenadas_ar: data.coordenadas_ar, // Ej: { "x": 1.5, "y": 0.8, "z": -2.3 }
      estado: "Pendiente",
      fecha: new Date().toISOString(),
    },
  };

  try {
    await docClient.send(new PutCommand(params));
    return { statusCode: 201, body: JSON.stringify({ mensaje: "Pin AR creado", reporte: params.Item }) };
  } catch (error) {
    return { statusCode: 500, body: JSON.stringify({ error: "Error interno" }) };
  }
};

// 2. GET: Obtener todos los pines de un salón específico al escanear el QR
module.exports.obtenerPinesAR = async (event) => {
  const ubicacion_qr = event.pathParameters.ubicacion_qr;

  const params = {
    TableName: "ReportesTabla",
    IndexName: "UbicacionIndex",
    KeyConditionExpression: "ubicacion_qr = :qr",
    FilterExpression: "estado = :estado", // Solo traer los que no han sido reparados
    ExpressionAttributeValues: {
      ":qr": ubicacion_qr,
      ":estado": "Pendiente"
    }
  };

  try {
    const result = await docClient.send(new QueryCommand(params));
    return {
      statusCode: 200,
      body: JSON.stringify({ pines_ar: result.Items }),
    };
  } catch (error) {
    return { statusCode: 500, body: JSON.stringify({ error: "Error al obtener pines" }) };
  }
};

// 3. PUT: Marcar como resuelto (Protegido con llave maestra)
module.exports.resolverReporte = async (event) => {
  // 1. Extraemos las cabeceras y buscamos nuestra llave secreta
  const headers = event.headers || {};
  const token = headers['x-admin-token'] || headers['X-Admin-Token'];

  // 2. Si no mandan la llave, o es incorrecta, bloqueamos la petición (Error 403 Forbidden)
  if (token !== 'super-secreto-uaq-2026') {
    return { 
      statusCode: 403, 
      body: JSON.stringify({ error: "Acceso denegado. Solo el personal de mantenimiento puede resolver reportes." }) 
    };
  }

  const reporteId = event.pathParameters.reporteId;

  const params = {
    TableName: "ReportesTabla",
    Key: { reporteId: reporteId },
    UpdateExpression: "set estado = :nuevoEstado",
    ExpressionAttributeValues: {
      ":nuevoEstado": "Resuelto"
    },
    ReturnValues: "ALL_NEW"
  };

  try {
    const result = await docClient.send(new UpdateCommand(params));
    return { statusCode: 200, body: JSON.stringify({ mensaje: "Reparado exitosamente", reporte: result.Attributes }) };
  } catch (error) {
    return { statusCode: 500, body: JSON.stringify({ error: "Error al actualizar" }) };
  }
};