#!/usr/bin/env bash
# setup.sh — Bootstrap the Wazuh single-node Docker stack
#
# What this script does:
#   1. Checks prerequisites (Docker, openssl, and python3-bcrypt or htpasswd).
#   2. Creates the .env file from .env.example if it does not exist.
#   3. Generates bcrypt password hashes for Wazuh Indexer internal users.
#   4. Generates self-signed TLS certificates for all Wazuh components.
#   5. Sets the vm.max_map_count kernel parameter required by OpenSearch.
#   6. Starts the stack with docker compose.
#
set -euo pipefail

###############################################################################
# Helpers
###############################################################################
info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/config/certs"

###############################################################################
# Pre-flight checks
###############################################################################
command -v docker  >/dev/null 2>&1 || error "Docker is not installed."
command -v openssl >/dev/null 2>&1 || error "openssl is not installed."

###############################################################################
# Environment file
###############################################################################
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
  warn ".env file created from .env.example"
  warn "IMPORTANT: Edit .env and change all default passwords before proceeding."
  echo ""
  read -rp "Press [Enter] after editing .env to continue, or Ctrl+C to abort..."
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/.env"

###############################################################################
# Kernel parameter for OpenSearch
###############################################################################
CURRENT_MAP_COUNT="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if (( CURRENT_MAP_COUNT < 262144 )); then
  info "Setting vm.max_map_count=262144 (required by OpenSearch/Wazuh Indexer)..."
  if [[ "${EUID}" -eq 0 ]]; then
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  else
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
  fi
fi

###############################################################################
# Bcrypt hash generation helper
###############################################################################
bcrypt_hash() {
  # Prefer Python3 bcrypt module, then htpasswd
  local password="$1"
  if python3 -c "import bcrypt" 2>/dev/null; then
    python3 -c "
import bcrypt, sys
pw = sys.argv[1].encode()
print(bcrypt.hashpw(pw, bcrypt.gensalt(rounds=12)).decode())
" "${password}"
  elif command -v htpasswd >/dev/null 2>&1; then
    # htpasswd prints "user:hash" — extract just the hash
    htpasswd -nbB _user "${password}" | cut -d: -f2
  else
    error "Cannot generate bcrypt hashes. Install 'apache2-utils' (apt) / 'httpd-tools' (yum), or ensure 'python3-bcrypt' is installed."
  fi
}

###############################################################################
# Indexer internal users — write bcrypt hashes derived from .env passwords
###############################################################################
configure_indexer_users() {
  local internal_users="${SCRIPT_DIR}/config/wazuh-indexer/internal_users.yml"

  if ! grep -q "REPLACE_WITH_BCRYPT_HASH" "${internal_users}"; then
    info "Indexer user hashes already configured — skipping."
    return
  fi

  info "Generating bcrypt hashes for Wazuh Indexer users..."

  local admin_hash dashboard_hash
  admin_hash="$(bcrypt_hash "${INDEXER_PASSWORD}")"
  dashboard_hash="$(bcrypt_hash "${DASHBOARD_PASSWORD}")"

  # Write the file with real hashes
  cat > "${internal_users}" <<EOF
# This file is managed by setup.sh — do not edit manually.

_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "${admin_hash}"
  reserved: true
  backend_roles:
    - "admin"
  description: "Admin user"

kibanaserver:
  hash: "${dashboard_hash}"
  reserved: true
  description: "OpenSearch Dashboards user"

wazuh:
  hash: "${admin_hash}"
  reserved: false
  backend_roles:
    - "wazuh"
  description: "Wazuh user"
EOF

  info "Indexer user hashes written to config/wazuh-indexer/internal_users.yml"
}

###############################################################################
# TLS certificate generation
###############################################################################
generate_certs() {
  info "Generating TLS certificates in ${CERTS_DIR}..."
  mkdir -p "${CERTS_DIR}"

  # ── Root CA ────────────────────────────────────────────────────────────────
  if [[ ! -f "${CERTS_DIR}/root-ca.pem" ]]; then
    openssl genrsa -out "${CERTS_DIR}/root-ca-key.pem" 4096 2>/dev/null
    openssl req -new -x509 -sha256 \
      -key "${CERTS_DIR}/root-ca-key.pem" \
      -out "${CERTS_DIR}/root-ca.pem" \
      -days 3650 \
      -subj "/C=US/ST=California/L=California/O=Wazuh/OU=Wazuh/CN=RootCA"
    cp "${CERTS_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca-manager.pem"
    info "  Root CA created."
  else
    info "  Root CA already exists — skipping."
  fi

  # ── Helper: issue a signed cert ────────────────────────────────────────────
  issue_cert() {
    local name="$1"
    local cn="$2"
    if [[ -f "${CERTS_DIR}/${name}.pem" ]]; then
      info "  ${name} cert already exists — skipping."
      return
    fi
    openssl genrsa -out "${CERTS_DIR}/${name}-key.pem" 4096 2>/dev/null
    openssl req -new -sha256 \
      -key "${CERTS_DIR}/${name}-key.pem" \
      -out "${CERTS_DIR}/${name}.csr" \
      -subj "/C=US/ST=California/L=California/O=Wazuh/OU=Wazuh/CN=${cn}"
    openssl x509 -req -sha256 \
      -in "${CERTS_DIR}/${name}.csr" \
      -CA "${CERTS_DIR}/root-ca.pem" \
      -CAkey "${CERTS_DIR}/root-ca-key.pem" \
      -CAcreateserial \
      -out "${CERTS_DIR}/${name}.pem" \
      -days 3650 2>/dev/null
    rm -f "${CERTS_DIR}/${name}.csr"
    info "  ${name} cert created."
  }

  issue_cert "wazuh-indexer"   "wazuh-indexer"
  issue_cert "wazuh-manager"   "wazuh-manager"
  issue_cert "wazuh-dashboard" "wazuh-dashboard"
  issue_cert "admin"           "admin"

  # Restrict private key permissions
  chmod 600 "${CERTS_DIR}"/*-key.pem
}

configure_indexer_users
generate_certs

###############################################################################
# Start the stack
###############################################################################
info "Starting Wazuh stack (this may take a few minutes on first run)..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${SCRIPT_DIR}/.env" up -d

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " Wazuh stack is starting up!"
info " Dashboard will be available at:"
info "   https://<your-server-ip>:${DASHBOARD_PORT:-443}"
info " Default credentials (change these!):"
info "   Username: admin"
info "   Password: (value of INDEXER_PASSWORD in .env)"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " Follow logs: docker compose logs -f"
