const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const crypto = require("crypto");

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

module.exports.crearReporte = async (event) => {
  let data;
  
  try {
    if (!event.body) throw new Error("Cuerpo de petición vacío");
    data = JSON.parse(event.body);
  } catch (error) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: "El cuerpo de la petición no es un JSON válido o está vacío." }),
    };
  }
  
  const params = {
    TableName: "ReportesTabla",
    Item: {
      reporteId: crypto.randomUUID(),
      tipo: data.tipo,
      descripcion: data.descripcion,
      ubicacion: data.ubicacion,
      estado: "Pendiente",
      fecha: new Date().toISOString(),
    },
  };

  try {
    await docClient.send(new PutCommand(params));
    return {
      statusCode: 201,
      body: JSON.stringify({ mensaje: "Reporte creado exitosamente", reporte: params.Item }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "No se pudo crear el reporte" }),
    };
  }
};