#!/usr/bin/env bash
# Pruebas del CRUD de vehiculos.
# Por defecto apunta a http://localhost:4000 (serverless-offline).
# Para apuntar a AWS: BASE_URL=https://xxx.execute-api.us-east-1.amazonaws.com ./test.sh
set -e

BASE_URL="${BASE_URL:-http://localhost:4000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok()    { printf "\033[1;32m  \xE2\x9C\x94 %s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m  \xE2\x9C\x98 %s\033[0m\n" "$1"; }
info()  { printf "\033[1;34m\n%s %s\033[0m\n" "[$(date +%H:%M:%S)]" "$1"; }
title() { printf "\033[1m%-50s\033[0m\n" "── $1 ──"; }

declare -i PASADOS=0
declare -i FALLADOS=0
declare -a LIMPIAR=()

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

# Devuelve solo el codigo HTTP y guarda el body en /tmp/test_body.json
http() {
  curl -s -o /tmp/test_body.json -w "%{http_code}" "$@"
}

# Extrae el primer "id":"..." del body
extract_id() {
  grep -oP '"id":"\K[^"]+' /tmp/test_body.json | head -1
}

# Cuenta IDs en el body (para el listado)
count_items() {
  grep -oP '"id":"[^"]+"' /tmp/test_body.json 2>/dev/null | wc -l
}

cleanup() {
  if [ "${#LIMPIAR[@]}" -gt 0 ]; then
    info "Limpiando ${#LIMPIAR[@]} item(s) de prueba..."
    for id in "${LIMPIAR[@]}"; do
      curl -s -X DELETE "$BASE_URL/vehiculos/$id" >/dev/null 2>&1 || true
    done
  fi
}
trap cleanup EXIT

info "Servidor bajo prueba: $BASE_URL"
echo

# ────────────────────────────────────────────────
title "1. Estado inicial"
# ────────────────────────────────────────────────
info "[1/4] GET /vehiculos (lista vacia o previa)"
code=$(http "$BASE_URL/vehiculos")
check_status 200 "$code" "GET /vehiculos responde"
CANT_INICIAL=$(count_items)
info "    items actuales en la tabla: $CANT_INICIAL"

# ────────────────────────────────────────────────
title "2. Validacion (caso 400)"
# ────────────────────────────────────────────────
info "[2/4] POST /vehiculos con body invalido"
code=$(http -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"SoloMarca"}')
check_status 400 "$code" "POST sin campos obligatorios -> 400"
info "    mensaje: $(cat /tmp/test_body.json)"

# ────────────────────────────────────────────────
title "3. Operaciones CRUD (caso 200/201)"
# ────────────────────────────────────────────────
info "[3/4] POST /vehiculos (crear #1)"
code=$(http -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Toyota","modelo":"Corolla","anio":2022,"placa":"ABC123","color":"Blanco"}')
check_status 201 "$code" "Crear vehiculo Toyota"
ID1=$(extract_id)
LIMPIAR+=("$ID1")
info "    id generado: $ID1"

info "[3/4] POST /vehiculos (crear #2)"
code=$(http -X POST "$BASE_URL/vehiculos" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Mazda","modelo":"CX-5","anio":2024,"placa":"XYZ789"}')
check_status 201 "$code" "Crear vehiculo Mazda"
ID2=$(extract_id)
LIMPIAR+=("$ID2")
info "    id generado: $ID2"

info "[3/4] GET /vehiculos (listar todos)"
code=$(http "$BASE_URL/vehiculos")
check_status 200 "$code" "GET /vehiculos responde 200"
CANT_FINAL=$(count_items)
info "    items en lista: $CANT_FINAL (antes: $CANT_INICIAL)"

info "[3/4] GET /vehiculos/$ID1 (obtener uno)"
code=$(http "$BASE_URL/vehiculos/$ID1")
check_status 200 "$code" "GET por id existente -> 200"
info "    devuelve: marca=$(grep -oP '"marca":"\K[^"]+' /tmp/test_body.json)"

info "[3/4] PUT /vehiculos/$ID1 (actualizar)"
code=$(http -X PUT "$BASE_URL/vehiculos/$ID1" \
  -H "Content-Type: application/json" \
  -d '{"marca":"Toyota","modelo":"Corolla","anio":2023,"placa":"ABC123","color":"Negro"}')
check_status 200 "$code" "PUT actualizar -> 200"
info "    nuevo color: $(grep -oP '"color":"\K[^"]+' /tmp/test_body.json)"

# ────────────────────────────────────────────────
title "4. Casos de error (404)"
# ────────────────────────────────────────────────
info "[4/4] GET /vehiculos/no-existe-xyz"
code=$(http "$BASE_URL/vehiculos/no-existe-xyz")
check_status 404 "$code" "GET id inexistente -> 404"

info "[4/4] PUT /vehiculos/no-existe-xyz"
code=$(http -X PUT "$BASE_URL/vehiculos/no-existe-xyz" \
  -H "Content-Type: application/json" \
  -d '{"marca":"X","modelo":"Y","anio":2020,"placa":"Z"}')
check_status 404 "$code" "PUT id inexistente -> 404"

info "[4/4] DELETE /vehiculos/no-existe-xyz"
code=$(http -X DELETE "$BASE_URL/vehiculos/no-existe-xyz")
check_status 404 "$code" "DELETE id inexistente -> 404"

# ────────────────────────────────────────────────
title "5. Limpieza final (DELETE)"
# ────────────────────────────────────────────────
for id in "${LIMPIAR[@]}"; do
  info "DELETE /vehiculos/$id"
  code=$(http -X DELETE "$BASE_URL/vehiculos/$id")
  check_status 200 "$code" "Eliminar $id"
done

# ────────────────────────────────────────────────
echo
printf "\033[1m%-30s\033[0m\n" "──────────────────────────────"
printf "\033[1m  Resultado:\033[0m  \033[1;32m%d OK\033[0m  " "$PASADOS"
if [ "$FALLADOS" -gt 0 ]; then
  printf "\033[1;31m%d FALLARON\033[0m\n" "$FALLADOS"
  exit 1
else
  printf "\033[1;32m0 fallaron\033[0m\n"
fi
