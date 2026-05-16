#!/usr/bin/env bash
# Si se invoca con `sh gaia.sh`, re-ejecutar con bash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
# gaia.sh — gestión de iAgents Hub con Docker
# Uso: ./gaia.sh <comando>
#
#   start    Arranca los servicios (crea .env si no existe)
#   stop     Detiene los servicios
#   logs     Muestra los logs en tiempo real
#   update   Reconstruye con la última versión del código
#   status   Estado de los contenedores

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parseo de flags globales ───────────────────────────────────────────────────
DEV=false
ARGS=()
for arg in "$@"; do
  [[ "$arg" == "--dev" ]] && DEV=true || ARGS+=("$arg")
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if $DEV; then
  COMPOSE="docker compose -f docker-compose.yml -f docker-compose.dev.yml"
else
  COMPOSE="docker compose"
fi

# ── colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[gaia]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[gaia]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[gaia]${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}[gaia]${RESET} $*" >&2; exit 1; }

_show_admin_info() {
  # Wait up to 30 s for the backend container to accept exec
  local i=0
  while [ $i -lt 30 ]; do
    $COMPOSE exec -T backend sh -c 'exit 0' &>/dev/null && break
    sleep 1; i=$((i+1))
  done

  local admin_email
  admin_email=$($COMPOSE exec -T backend sh -c 'printf "%s" "$GAIA_ADMIN_EMAIL"' 2>/dev/null | tr -d '\r\n') || true
  [ -z "$admin_email" ] && return

  # Read persisted password from .admin_pass (written by the backend on every reset/create)
  local admin_pass
  admin_pass=$($COMPOSE exec -T backend sh -c 'cat "$GAIA_DATA_DIR/.admin_pass" 2>/dev/null' 2>/dev/null | tr -d '\r\n') || true

  echo
  echo -e "${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}  ║       Acceso de administrador            ║${RESET}"
  echo -e "${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
  echo -e "${BOLD}  ║${RESET}  Email      › ${CYAN}${admin_email}${RESET}"
  if [ -n "$admin_pass" ]; then
    echo -e "${BOLD}  ║${RESET}  Contraseña › ${GREEN}${admin_pass}${RESET}"
  else
    echo -e "${BOLD}  ║${RESET}  Contraseña › (sin cambios)"
  fi
  echo -e "${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
  echo
}

# ── helpers ───────────────────────────────────────────────────────────────────
check_docker() {
  command -v docker &>/dev/null || error "Docker no está instalado. Descárgalo en https://docs.docker.com/get-docker/"
  docker info &>/dev/null       || error "Docker no está en ejecución. Árrancalo e inténtalo de nuevo."
}

ensure_env() {
  cd "$SCRIPT_DIR"
  if [ ! -f .env ]; then
    cp .env.example .env
    warn "Se ha creado .env a partir de .env.example."
    warn "Edita el fichero .env y cambia las contraseñas antes de continuar."
    echo
    read -rp "¿Has editado .env y quieres continuar? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || { info "Operación cancelada."; exit 0; }
  fi
}

get_port() {
  # Lee PORT del .env, con fallback a 80
  grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "80"
}

inject_github_token() {
  # Lee GITHUB_TOKEN del .env si no viene ya del entorno
  local token="${GITHUB_TOKEN:-$(grep -E '^GITHUB_TOKEN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)}"
  [[ -z "$token" ]] && return

  local backend_repo frontend_repo skills_repo agents_repo
  backend_repo="$(grep -E '^BACKEND_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  frontend_repo="$(grep -E '^FRONTEND_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  skills_repo="$(grep -E '^SKILLS_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  agents_repo="$(grep -E '^AGENTS_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"

  # Inserta el token en las URLs https:// → https://<token>@
  export BACKEND_REPO="${backend_repo/https:\/\//https://${token}@}"
  export FRONTEND_REPO="${frontend_repo/https:\/\//https://${token}@}"
  export SKILLS_REPO="${skills_repo/https:\/\//https://${token}@}"
  if [[ -n "$agents_repo" ]]; then export AGENTS_REPO="${agents_repo/https:\/\//https://${token}@}"; fi
}

# ── comandos ──────────────────────────────────────────────────────────────────
cmd_start() {
  check_docker
  ensure_env
  cd "$SCRIPT_DIR"
  inject_github_token
  if $DEV; then info "Modo desarrollo — usando repos locales"; fi
  info "Construyendo e iniciando servicios..."
  $COMPOSE rm -f data-init 2>/dev/null || true
  $COMPOSE up -d --build
  PORT=$(get_port)
  echo
  success "iAgents Hub en marcha → http://localhost:${PORT}"
  _show_admin_info
}

cmd_stop() {
  check_docker
  cd "$SCRIPT_DIR"
  info "Deteniendo servicios..."
  $COMPOSE down
  success "Servicios detenidos."
}

cmd_logs() {
  check_docker
  cd "$SCRIPT_DIR"
  info "Mostrando logs (Ctrl+C para salir)..."
  $COMPOSE logs -f --tail=100
}

cmd_update() {
  check_docker
  ensure_env
  cd "$SCRIPT_DIR"
  inject_github_token
  if $DEV; then info "Modo desarrollo — usando repos locales"; fi
  info "Actualizando a la última versión..."
  $COMPOSE rm -f data-init 2>/dev/null || true
  $COMPOSE down
  $COMPOSE up -d --build
  PORT=$(get_port)
  echo
  success "Actualización completada → http://localhost:${PORT}"
  _show_admin_info
}

cmd_status() {
  check_docker
  cd "$SCRIPT_DIR"
  $COMPOSE ps
}

# ── main ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
  start)  cmd_start  ;;
  stop)   cmd_stop   ;;
  logs)   cmd_logs   ;;
  update) cmd_update ;;
  status) cmd_status ;;
  *)
    echo -e "${BOLD}Uso:${RESET} ./gaia.sh <comando> [--dev]"
    echo
    echo "  start    Arranca los servicios"
    echo "  stop     Detiene los servicios"
    echo "  logs     Muestra los logs en tiempo real"
    echo "  update   Actualiza a la última versión y reinicia"
    echo "  status   Estado de los contenedores"
    echo
    echo -e "${BOLD}Flags:${RESET}"
    echo "  --dev    Usa repos locales (../backend, ../frontend, ../skills) en lugar de GitHub"
    echo
    exit 1
    ;;
esac
