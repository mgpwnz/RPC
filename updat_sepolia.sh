#!/usr/bin/env bash
set -euo pipefail

# === Script to update existing Sepolia-node stack ===
# - Remove obsolete "version:" line in docker-compose.yml
# - Ensure Teku allows REST API from any host
# - Restart Teku container

DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Error: docker-compose.yml not found at $COMPOSE_FILE"
  exit 1
fi

echo "🔧 Updating $COMPOSE_FILE..."

# 1) Remove 'version:' line if present
sed -i.bak '/^[[:space:]]*version:/d' "$COMPOSE_FILE"

echo "✔ Removed obsolete version attribute."

# 2) Add rest-api-host-allowlist for Teku if missing
if ! grep -q 'rest-api-host-allowlist' "$COMPOSE_FILE"; then
  # Insert after rest-api-port line
  sed -i '/--rest-api-port[[:space:]]*/a\
          --rest-api-host-allowlist="*"' "$COMPOSE_FILE"
  echo "✔ Added --rest-api-host-allowlist='*' to Teku entrypoint."
else
  echo "ℹ Teku rest-api-host-allowlist already configured."
fi

# 3) Restart Teku container
echo "🚀 Restarting Teku container..."
cd "$DATA_DIR"
docker compose stop sepolia-teku
# pull latest image in case there's an update
docker compose pull teku
docker compose up -d sepolia-teku

echo "✅ Teku container restarted successfully."

echo "Now you can query the Teku REST API externally without Host header restrictions."
