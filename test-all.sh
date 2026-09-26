#!/usr/bin/env bash
# Pruebas del CRUD contra uno o ambos entornos (local + AWS).
# Por defecto prueba los dos. Las URLs se leen de los JSON de Insomnia.
#
# Uso:
#   ./test-all.sh                  # prueba local + AWS
#   ./test-all.sh --local          # solo local (http://localhost:4000)
#   ./test-all.sh --aws            # solo AWS (lee URL de insomnia-aws-collection.json)
#   ./test-all.sh --url URL        # contra una URL personalizada
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_JSON="$SCRIPT_DIR/${INSOMNIA_LOCAL:-tests-insomnia/insomnia-collection.json}"
AWS_JSON="$SCRIPT_DIR/${INSOMNIA_AWS:-tests-insomnia/insomnia-aws-collection.json}"

ok()    { printf "\033[1;32m  ✔ %s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m  ✘ %s\033[0m\n" "$1"; }
info()  { printf "\033[1;34m\n[%s] %s\033[0m\n" "$(date +%H:%M:%S)" "$1"; }
title() { printf "\033[1m── %s ──\033[0m\n" "$1"; }

declare -i GLOBAL_OK=0
declare -i GLOBAL_FAIL=0
declare -a ENTORNO_OK=()
declare -a ENTORNO_FAIL=()

# Lee el base_url del primer environment dentro del JSON de Insomnia.
leer_base_url_desde_json() {
  local json="$1"
  if [ ! -f "$json" ]; then
    return 1
  fi
  node -e "
const d = JSON.parse(require('fs').readFileSync('$json','utf8'));
const env = d.resources.find(r => r._type === 'environment');
if (env && env.data && env.data.base_url) process.stdout.write(env.data.base_url);
" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
# Suite de pruebas: corre contra el BASE_URL exportado.
# Suma a GLOBAL_OK / GLOBAL_FAIL y al entorno pasado como $1.
# ─────────────────────────────────────────────────────────────
correr_suite() {
  local entorno_nombre="$1"
  local base_url="$2"

  if [ -z "$base_url" ]; then
    fail "[$entorno_nombre] BASE_URL vacia, saltando"
    GLOBAL_FAIL+=1
    return
  fi

  info "Entorno: $entorno_nombre"
  info "URL:     $base_url"

  local -i ok=0
  local -i fail_count=0
  local -a LIMPIAR=()

  check_status() {
    local esperado="$1"
    local obtenido="$2"
    local nombre="$3"
    if [ "$esperado" = "$obtenido" ]; then
      ok "$nombre (HTTP $obtenido)"
      ok=$((ok + 1))
    else
      fail "$nombre (esperado $esperado, obtuvo $obtenido)"
      fail_count=$((fail_count + 1))
    fi
  }

  http() { curl -s -o /tmp/test_body.json -w "%{http_code}" --max-time 10 "$@"; }
  extract_id() { grep -oP '"id":"\K[^"]+' /tmp/test_body.json | head -1; }
  count_items() { grep -oP '"id":"[^"]+"' /tmp/test_body.json 2>/dev/null | wc -l; }

  cleanup() {
    for id in "${LIMPIAR[@]}"; do
      curl -s -X DELETE "$base_url/vehiculos/$id" >/dev/null 2>&1 || true
    done
  }
  trap cleanup EXIT

  title "[$entorno_nombre] 1. Listar (200)"
  code=$(http "$base_url/vehiculos")
  check_status 200 "$code" "GET /vehiculos"
  info "    items en tabla: $(count_items)"

  title "[$entorno_nombre] 2. Validacion (400)"
  code=$(http -X POST "$base_url/vehiculos" \
    -H "Content-Type: application/json" \
    -d '{"marca":"x"}')
  check_status 400 "$code" "POST body invalido"

  title "[$entorno_nombre] 3. CRUD happy path"
  code=$(http -X POST "$base_url/vehiculos" \
    -H "Content-Type: application/json" \
    -d '{"marca":"Toyota","modelo":"Corolla","anio":2022,"placa":"ABC123","color":"Blanco"}')
  check_status 201 "$code" "POST crear #1"
  ID1=$(extract_id); LIMPIAR+=("$ID1")
  info "    id: $ID1"

  code=$(http -X POST "$base_url/vehiculos" \
    -H "Content-Type: application/json" \
    -d '{"marca":"Mazda","modelo":"CX-5","anio":2024,"placa":"XYZ789"}')
  check_status 201 "$code" "POST crear #2"
  ID2=$(extract_id); LIMPIAR+=("$ID2")

  code=$(http "$base_url/vehiculos")
  check_status 200 "$code" "GET listar"
  info "    items: $(count_items)"

  code=$(http "$base_url/vehiculos/$ID1")
  check_status 200 "$code" "GET por id"
  info "    marca: $(grep -oP '"marca":"\K[^"]+' /tmp/test_body.json)"

  code=$(http -X PUT "$base_url/vehiculos/$ID1" \
    -H "Content-Type: application/json" \
    -d '{"marca":"Toyota","modelo":"Corolla","anio":2023,"placa":"ABC123","color":"Negro"}')
  check_status 200 "$code" "PUT actualizar"
  info "    color nuevo: $(grep -oP '"color":"\K[^"]+' /tmp/test_body.json)"

  title "[$entorno_nombre] 4. Casos 404"
  code=$(http "$base_url/vehiculos/no-existe-xyz")
  check_status 404 "$code" "GET id inexistente"

  code=$(http -X PUT "$base_url/vehiculos/no-existe-xyz" \
    -H "Content-Type: application/json" \
    -d '{"marca":"X","modelo":"Y","anio":2020,"placa":"Z"}')
  check_status 404 "$code" "PUT id inexistente"

  code=$(http -X DELETE "$base_url/vehiculos/no-existe-xyz")
  check_status 404 "$code" "DELETE id inexistente"

  title "[$entorno_nombre] 5. Limpieza"
  for id in "${LIMPIAR[@]}"; do
    code=$(http -X DELETE "$base_url/vehiculos/$id")
    check_status 200 "$code" "DELETE $id"
  done

  trap - EXIT
  GLOBAL_OK=$((GLOBAL_OK + ok))
  GLOBAL_FAIL=$((GLOBAL_FAIL + fail_count))

  if [ "$fail_count" -gt 0 ]; then
    ENTORNO_FAIL+=("$entorno_nombre ($fail_count fallaron)")
  else
    ENTORNO_OK+=("$entorno_nombre ($ok OK)")
  fi

  echo
  printf "  Entorno %-12s  %d OK  %d fallaron\n" "$entorno_nombre" "$ok" "$fail_count"
  echo
}

# ─────────────────────────────────────────────────────────────
# Parseo de argumentos
# ─────────────────────────────────────────────────────────────
MODO="all"
BASE_URL_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --local)  MODO="local" ;;
    --aws)    MODO="aws" ;;
    --all)    MODO="all" ;;
    --url)    BASE_URL_OVERRIDE="$2"; shift ;;
    --help|-h)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *) echo "Argumento desconocido: $1"; exit 2 ;;
  esac
  shift
done

echo
printf "\033[1m════════════════════════════════════════\033[0m\n"
printf "\033[1m  CRUD Vehiculos - Suite de pruebas\033[0m\n"
printf "\033[1m════════════════════════════════════════\033[0m\n"

# Override tiene prioridad
if [ -n "$BASE_URL_OVERRIDE" ]; then
  MODO="custom"
fi

case "$MODO" in
  local)
    URL="${BASE_URL_OVERRIDE:-$(leer_base_url_desde_json "$LOCAL_JSON")}"
    [ -z "$URL" ] && { echo "No se encontro base_url en $LOCAL_JSON"; exit 1; }
    correr_suite "LOCAL" "$URL"
    ;;
  aws)
    URL="${BASE_URL_OVERRIDE:-$(leer_base_url_desde_json "$AWS_JSON")}"
    [ -z "$URL" ] && { echo "No se encontro base_url en $AWS_JSON"; exit 1; }
    correr_suite "AWS" "$URL"
    ;;
  custom)
    correr_suite "CUSTOM" "$BASE_URL_OVERRIDE"
    ;;
  all)
    LOCAL_URL="${BASE_URL_OVERRIDE:-$(leer_base_url_desde_json "$LOCAL_JSON")}"
    AWS_URL="$(leer_base_url_desde_json "$AWS_JSON")"
    [ -z "$LOCAL_URL" ] && { echo "No se encontro base_url en $LOCAL_JSON"; exit 1; }
    [ -z "$AWS_URL" ]   && { echo "No se encontro base_url en $AWS_JSON"; exit 1; }
    correr_suite "LOCAL" "$LOCAL_URL"
    correr_suite "AWS"   "$AWS_URL"
    ;;
esac

# ─────────────────────────────────────────────────────────────
# Resumen final
# ─────────────────────────────────────────────────────────────
echo "════════════════════════════════════════"
printf "\033[1m  Resultado global:\033[0m  \033[1;32m%d OK\033[0m  " "$GLOBAL_OK"
if [ "$GLOBAL_FAIL" -gt 0 ]; then
  printf "\033[1;31m%d FALLARON\033[0m\n" "$GLOBAL_FAIL"
  echo
  printf "\033[1;31mEntornos con fallos:\033[0m\n"
  for e in "${ENTORNO_FAIL[@]}"; do printf "  - %s\n" "$e"; done
  exit 1
else
  printf "\033[1;32m0 fallaron\033[0m\n"
  echo
  printf "\033[1;32mEntornos OK:\033[0m\n"
  for e in "${ENTORNO_OK[@]}"; do printf "  - %s\n" "$e"; done
fi
echo "════════════════════════════════════════"
