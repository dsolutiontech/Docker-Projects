#!/usr/bin/env bash
set -e

echo "[ENTRYPOINT] Loading Wazuh credentials from Docker secrets (if present)..."

# Helper: export VAR from /run/secrets/<name> if the file exists
load_secret() {
  local var_name="$1"
  local secret_file="$2"

  if [ -f "/run/secrets/${secret_file}" ]; then
    export "${var_name}=$(cat "/run/secrets/${secret_file}")"
    echo "  - ${var_name} loaded from /run/secrets/${secret_file}"
  else
    echo "  - ${var_name} not set (no /run/secrets/${secret_file})"
  fi
}

# ---- Manager & Indexer credentials ----
load_secret "INDEXER_USERNAME" "idx_user"
load_secret "INDEXER_PASSWORD" "idx_pass"

# Wazuh API user
load_secret "API_USERNAME" "api_user"
load_secret "API_PASSWORD" "api_pass"

# ---- Dashboard login credentials ----
load_secret "DASHBOARD_USERNAME" "dash_user"
load_secret "DASHBOARD_PASSWORD" "dash_pass"

echo "[ENTRYPOINT] Environment setup complete. Starting Wazuh container..."

# Decide which real entrypoint to call
if [ -x /entrypoint.sh ]; then
  # dashboard / indexer
  echo "[ENTRYPOINT] Detected /entrypoint.sh, chaining to it..."
  exec /entrypoint.sh "$@"
elif [ -x /init ]; then
  # manager
  echo "[ENTRYPOINT] Detected /init, chaining to it..."
  exec /init "$@"
else
  echo "[ENTRYPOINT] No known entrypoint found. Exiting."
  exit 1
fi