const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
  ScanCommand,
  UpdateCommand,
  DeleteCommand,
} = require("@aws-sdk/lib-dynamodb");
const { randomUUID } = require("crypto");

const TABLE = process.env.VEHICULOS_TABLE;
const endpoint = process.env.DYNAMO_ENDPOINT;
const db = DynamoDBDocumentClient.from(
  new DynamoDBClient(
    endpoint
      ? {
          region: process.env.AWS_REGION || "us-east-1",
          endpoint,
          credentials: {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID || "local",
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "local",
          },
        }
      : {}
  )
);

const respuesta = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

const leerBody = (event) => {
  try {
    return JSON.parse(event.body || "{}");
  } catch {
    return null;
  }
};

const validar = (data) => {
  if (!data) return "El cuerpo debe ser un JSON valido";
  if (typeof data.marca !== "string" || !data.marca.trim())
    return '"marca" es obligatorio y debe ser texto';
  if (typeof data.modelo !== "string" || !data.modelo.trim())
    return '"modelo" es obligatorio y debe ser texto';
  if (typeof data.anio !== "number" || data.anio < 1900 || data.anio > 2100)
    return '"anio" es obligatorio y debe ser un numero entre 1900 y 2100';
  if (typeof data.placa !== "string" || !data.placa.trim())
    return '"placa" es obligatoria y debe ser texto';
  if (data.color !== undefined && typeof data.color !== "string")
    return '"color" debe ser texto';
  return null;
};

// CREATE - POST /vehiculos
module.exports.crear = async (event) => {
  const data = leerBody(event);
  const error = validar(data);
  if (error) return respuesta(400, { error });

  const item = {
    id: randomUUID(),
    marca: data.marca,
    modelo: data.modelo,
    anio: data.anio,
    placa: data.placa,
    color: data.color ?? null,
    creadoEn: new Date().toISOString(),
  };

  try {
    await db.send(new PutCommand({ TableName: TABLE, Item: item }));
    return respuesta(201, item);
  } catch (err) {
    console.error(err);
    return respuesta(500, { error: "No fue posible crear el vehiculo" });
  }
};

// READ (todos) - GET /vehiculos
module.exports.listar = async () => {
  try {
    const { Items } = await db.send(new ScanCommand({ TableName: TABLE }));
    return respuesta(200, Items);
  } catch (err) {
    console.error(err);
    return respuesta(500, { error: "No fue posible listar los vehiculos" });
  }
};

// READ (uno) - GET /vehiculos/{id}
module.exports.obtener = async (event) => {
  const { id } = event.pathParameters;
  try {
    const { Item } = await db.send(
      new GetCommand({ TableName: TABLE, Key: { id } })
    );
    if (!Item) return respuesta(404, { error: "Vehiculo no encontrado" });
    return respuesta(200, Item);
  } catch (err) {
    console.error(err);
    return respuesta(500, { error: "No fue posible consultar el vehiculo" });
  }
};

// UPDATE - PUT /vehiculos/{id}
module.exports.actualizar = async (event) => {
  const { id } = event.pathParameters;
  const data = leerBody(event);
  const error = validar(data);
  if (error) return respuesta(400, { error });

  try {
    const { Attributes } = await db.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { id },
        UpdateExpression:
          "SET marca = :marca, modelo = :modelo, anio = :anio, placa = :placa, color = :color",
        ExpressionAttributeValues: {
          ":marca": data.marca,
          ":modelo": data.modelo,
          ":anio": data.anio,
          ":placa": data.placa,
          ":color": data.color ?? null,
        },
        ConditionExpression: "attribute_exists(id)",
        ReturnValues: "ALL_NEW",
      })
    );
    return respuesta(200, Attributes);
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      return respuesta(404, { error: "Vehiculo no encontrado" });
    }
    console.error(err);
    return respuesta(500, { error: "No fue posible actualizar el vehiculo" });
  }
};

// DELETE - DELETE /vehiculos/{id}
module.exports.eliminar = async (event) => {
  const { id } = event.pathParameters;
  try {
    await db.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { id },
        ConditionExpression: "attribute_exists(id)",
      })
    );
    return respuesta(200, { mensaje: "Vehiculo eliminado", id });
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      return respuesta(404, { error: "Vehiculo no encontrado" });
    }
    console.error(err);
    return respuesta(500, { error: "No fue posible eliminar el vehiculo" });
  }
};