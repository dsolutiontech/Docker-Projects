#!/usr/bin/env bash
# setup.sh — Bootstrap the Traefik reverse-proxy stack
set -euo pipefail

###############################################################################
# Helpers
###############################################################################
info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

###############################################################################
# Pre-flight checks
###############################################################################
command -v docker  >/dev/null 2>&1 || error "Docker is not installed."
command -v htpasswd >/dev/null 2>&1 || error "'htpasswd' is not installed. Install apache2-utils (Debian/Ubuntu) or httpd-tools (RHEL/CentOS)."

###############################################################################
# Environment file
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
  warn ".env file created from .env.example — please edit it before continuing."
  warn "  Required values:"
  warn "    TRAEFIK_DASHBOARD_HOST  — hostname for the Traefik dashboard"
  warn "    ACME_EMAIL              — email address for Let's Encrypt"
  echo ""
  read -rp "Edit .env now and press [Enter] to continue, or Ctrl+C to abort..."
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/.env"

###############################################################################
# Validate required variables
###############################################################################
REQUIRED_VARS=(TRAEFIK_DASHBOARD_HOST ACME_EMAIL)
for var in "${REQUIRED_VARS[@]}"; do
  [[ -n "${!var:-}" ]] || error "Required variable '${var}' is not set in .env"
done

###############################################################################
# Generate dashboard basic-auth credentials
###############################################################################
if [[ "${TRAEFIK_DASHBOARD_AUTH}" == *"placeholder"* ]] || [[ -z "${TRAEFIK_DASHBOARD_AUTH:-}" ]]; then
  info "Generating dashboard credentials..."
  read -rp "  Dashboard username [admin]: " DASH_USER
  DASH_USER="${DASH_USER:-admin}"
  read -rsp "  Dashboard password: " DASH_PASS
  echo ""
  TRAEFIK_DASHBOARD_AUTH="$(htpasswd -nbB "${DASH_USER}" "${DASH_PASS}")"
  # Escape dollar signs for Docker Compose env var interpolation
  TRAEFIK_DASHBOARD_AUTH="${TRAEFIK_DASHBOARD_AUTH//$/\$\$}"
  # Update .env in place
  sed -i "s|^TRAEFIK_DASHBOARD_AUTH=.*|TRAEFIK_DASHBOARD_AUTH=${TRAEFIK_DASHBOARD_AUTH}|" "${SCRIPT_DIR}/.env"
  info "Credentials saved to .env"
fi

###############################################################################
# Start the stack
###############################################################################
info "Starting Traefik..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${SCRIPT_DIR}/.env" up -d

info "Traefik is running!"
info "Dashboard: https://${TRAEFIK_DASHBOARD_HOST}"
