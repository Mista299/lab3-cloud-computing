#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${PORT:-4000}"
DYNAMO_PORT="${DYNAMO_PORT:-8000}"
DYNAMO_ENDPOINT="${DYNAMO_ENDPOINT:-http://localhost:${DYNAMO_PORT}}"
TABLE_NAME="crud-vehiculos-vehiculos-dev"
AWS_REGION="${AWS_REGION:-us-east-1}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-local}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-local}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export DYNAMO_ENDPOINT

step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$1"; }

step "1. Verificando Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker no esta instalado. Abortando." >&2
  exit 1
fi

step "2. Levantando DynamoDB Local (puerto ${DYNAMO_PORT})..."
if docker ps -a --format '{{.Names}}' | grep -q '^dynamodb-local$'; then
  docker start dynamodb-local >/dev/null
  echo "Contenedor dynamodb-local reiniciado."
else
  docker run -d --name dynamodb-local -p "${DYNAMO_PORT}:8000" amazon/dynamodb-local >/dev/null
  echo "Contenedor dynamodb-local creado."
fi

step "3. Esperando a que DynamoDB Local responda..."
for i in $(seq 1 20); do
  if curl -sf "http://localhost:${DYNAMO_PORT}" -o /dev/null; then
    echo "DynamoDB Local listo."
    break
  fi
  sleep 0.5
done

step "4. Verificando tabla ${TABLE_NAME}..."
if AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local \
   AWS_REGION="$AWS_REGION" \
   aws --endpoint-url "http://localhost:${DYNAMO_PORT}" dynamodb describe-table \
   --table-name "$TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "La tabla ya existe."
else
  AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local \
  AWS_REGION="$AWS_REGION" \
  aws --endpoint-url "http://localhost:${DYNAMO_PORT}" dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" --no-cli-pager >/dev/null
  echo "Tabla creada."
fi

step "5. Iniciando serverless-offline en puerto ${PORT}..."
exec ./node_modules/.bin/serverless offline --stage dev --httpPort "$PORT"
