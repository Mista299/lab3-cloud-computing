# crud-vehiculos

API REST serverless para CRUD de vehiculos con AWS Lambda, API Gateway y DynamoDB.

## Atributos del vehiculo

- `id` (string, generado automaticamente con UUID)
- `marca` (string, obligatorio)
- `modelo` (string, obligatorio)
- `anio` (numero, obligatorio, entre 1900 y 2100)
- `placa` (string, obligatorio)
- `color` (string, opcional)

## Endpoints

| Metodo | Ruta              | Funcion     | Descripcion                |
|--------|-------------------|-------------|----------------------------|
| POST   | /vehiculos        | crear       | Crea un vehiculo (201)     |
| GET    | /vehiculos        | listar      | Lista todos (200)          |
| GET    | /vehiculos/{id}   | obtener     | Obtiene uno (200 / 404)    |
| PUT    | /vehiculos/{id}   | actualizar  | Actualiza uno (200 / 404)  |
| DELETE | /vehiculos/{id}   | eliminar    | Elimina uno (200 / 404)    |

## Despliegue

```bash
npm install
serverless deploy
```

Al finalizar copia la URL del API Gateway que aparece en la terminal.

## Pruebas locales

Requiere haber desplegado primero (la tabla debe existir en AWS):

```bash
serverless offline
```

Pruebas desde Postman / Insomnia en `http://localhost:3000/vehiculos`.

## Ejemplo de creacion

```json
POST /vehiculos
{
  "marca": "Toyota",
  "modelo": "Corolla",
  "anio": 2022,
  "placa": "ABC123",
  "color": "Blanco"
}
```

## Limpieza

```bash
serverless remove
```# lab3-cloud-computing
