#!/usr/bin/env bash
set -e

BASE_URL="${BASE_URL:-http://localhost:3001}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok()   { printf "\033[1;32m✔ %s\033[0m\n" "$1"; }
fail() { printf "\033[1;31m✘ %s\033[0m\n" "$1"; }
info() { printf "\033[1;34m▶ %s\033[0m\n" "$1"; }

declare -i PASADOS=0
declare -i FALLADOS=0

check_status() {
  local esperado="$1"
  local obtenido="$2"
  local nombre="$3"
  if [ "$esperado" = "$obtenido" ]; then
    ok "$nombre (HTTP $obtenido)"
    PASADOS+=1
  else
    fail "$nombre (esperado $esperado, obtuvo $obtenido)"
    FALLADOS+=1
  fi
}

curl_status() {
  curl -s -o /tmp/test_body.json -w "%{http_code}" "$@"
}

info "Servidor: $BASE_URL"
echo

# 1. Verificar servidor arriba
info "[1/8] GET /vehiculos (lista vacia)"
code=$(curl_status "$BASE_URL/vehiculos")
check_status 200 "$code" "Listar vehiculos (inicial)"

# 2. Validacion - body invalido
info "[2/8] POST /vehiculos (body invalido -> 400)"
code=$(curl_status -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"x"}')
check_status 400 "$code" "Validar cuerpo"

# 3. Crear vehiculo
info "[3/8] POST /vehiculos (crear valido -> 201)"
code=$(curl_status -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Toyota","modelo":"Corolla","anio":2022,"placa":"ABC123","color":"Blanco"}')
check_status 201 "$code" "Crear vehiculo"
ID=$(grep -oP '"id":"\K[^"]+' /tmp/test_body.json | head -1)
info "    id generado: $ID"

# 4. Crear segundo vehiculo
info "[4/8] POST /vehiculos (segundo vehiculo -> 201)"
code=$(curl_status -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Mazda","modelo":"CX-5","anio":2024,"placa":"XYZ789"}')
check_status 201 "$code" "Crear segundo vehiculo"

# 5. Listar todos
info "[5/8] GET /vehiculos (lista con items)"
code=$(curl_status "$BASE_URL/vehiculos")
check_status 200 "$code" "Listar vehiculos"
CANT=$(grep -oP '"id":"[^"]+"' /tmp/test_body.json | wc -l)
info "    items en lista: $CANT"

# 6. Obtener uno
info "[6/8] GET /vehiculos/{id}"
code=$(curl_status "$BASE_URL/vehiculos/$ID")
check_status 200 "$code" "Obtener vehiculo existente"
code=$(curl_status "$BASE_URL/vehiculos/no-existe-123")
check_status 404 "$code" "Obtener vehiculo inexistente"

# 7. Actualizar
info "[7/8] PUT /vehiculos/{id}"
code=$(curl_status -X PUT "$BASE_URL/vehiculos/$ID" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Toyota","modelo":"Corolla","anio":2023,"placa":"ABC123","color":"Negro"}')
check_status 200 "$code" "Actualizar vehiculo"
code=$(curl_status -X PUT "$BASE_URL/vehiculos/no-existe-123" \
  -H "Content-Type: application/json" \
  -d '{"marca":"X","modelo":"Y","anio":2020,"placa":"Z"}')
check_status 404 "$code" "Actualizar vehiculo inexistente"

# 8. Eliminar
info "[8/8] DELETE /vehiculos/{id}"
code=$(curl_status -X DELETE "$BASE_URL/vehiculos/$ID")
check_status 200 "$code" "Eliminar vehiculo existente"
code=$(curl_status -X DELETE "$BASE_URL/vehiculos/no-existe-123")
check_status 404 "$code" "Eliminar vehiculo inexistente"

# Limpiar
curl -s -X DELETE "$BASE_URL/vehiculos/$(grep -oP '"id":"\K[^"]+' /tmp/test_body.json | head -1)" >/dev/null 2>&1 || true

echo
echo "────────────────────────────────────"
printf "\033[1mResultado:\033[0m \033[1;32m%d OK\033[0m, " "$PASADOS"
if [ "$FALLADOS" -gt 0 ]; then
  printf "\033[1;31m%d FALLARON\033[0m\n" "$FALLADOS"
  exit 1
else
  printf "\033[1;32m0 fallaron\033[0m\n"
fi
