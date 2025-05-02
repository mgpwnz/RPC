#!/usr/bin/env bash
set -euo pipefail

# === Sepolia Full-Node + Beacon Setup Script (v5) ===
# Adds customizable HTTP, WS, authRPC, P2P (transport), and Teku REST API ports

DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
GETH_DATA_DIR="$DATA_DIR/geth-data"
TEKU_DATA_DIR="$DATA_DIR/teku-data"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"

# === Prompt for custom ports ===
read -rp "🛠️  Enter Geth HTTP RPC port (default: 8545): " HTTP_PORT
HTTP_PORT="${HTTP_PORT:-8545}"
read -rp "🛠️  Enter Geth WS RPC port (default: 8546): " WS_PORT
WS_PORT="${WS_PORT:-8546}"
read -rp "🛠️  Enter Geth authRPC port (default: 8551): " AUTHRPC_PORT
AUTHRPC_PORT="${AUTHRPC_PORT:-8551}"
read -rp "🛠️  Enter Geth P2P (transport) port (default: 30303): " P2P_PORT
P2P_PORT="${P2P_PORT:-30303}"
read -rp "🛠️  Enter Teku REST API port (default: 5051): " TEKU_REST_PORT
TEKU_REST_PORT="${TEKU_REST_PORT:-5051}"

echo "Using Geth HTTP RPC port: $HTTP_PORT"
echo "Using Geth WS RPC port: $WS_PORT"
echo "Using Geth authRPC port: $AUTHRPC_PORT"
echo "Using Geth P2P (transport) port: $P2P_PORT"
echo "Using Teku REST API port: $TEKU_REST_PORT"

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker & Compose..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "✅ Docker & Compose installed."
  else
    echo "ℹ️ Docker already installed."
  fi
}

prompt_wipe_geth() {
  if [[ -d "$GETH_DATA_DIR/geth/chaindata" ]]; then
    read -rp "🗑️ Wipe old Geth data? [Y/n]: " ans
    [[ ! "$ans" =~ ^[Nn] ]] && rm -rf "$GETH_DATA_DIR"
  fi
}

prompt_wipe_teku() {
  if [[ -d "$TEKU_DATA_DIR/beacon/db" ]]; then
    read -rp "🗑️ Wipe old Teku data? [Y/n]: " ans
    [[ ! "$ans" =~ ^[Nn] ]] && rm -rf "$TEKU_DATA_DIR"
  fi
}

generate_jwt() {
  mkdir -p "$JWT_DIR"
  [[ -f "$JWT_FILE" ]] || openssl rand -hex 32 > "$JWT_FILE"
}

write_compose() {
  mkdir -p "$DATA_DIR"
  cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  geth:
    image: ethereum/client-go:stable
    container_name: sepolia-geth
    restart: unless-stopped
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    command:
      - --sepolia
      - --datadir=/root/.ethereum
      - --syncmode=full
      - --gcmode=full
      - --cache=4096
      - --maxpeers=50
      - --http
      - --http.addr=0.0.0.0
      - --http.port=${HTTP_PORT}
      - --http.api=eth,net,web3,engine
      - --http.vhosts=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=${WS_PORT}
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=${AUTHRPC_PORT}
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
      - --authrpc.vhosts=*
      - --port=${P2P_PORT}
    ports:
      - "${HTTP_PORT}:${HTTP_PORT}"
      - "${WS_PORT}:${WS_PORT}"
      - "${AUTHRPC_PORT}:${AUTHRPC_PORT}"
      - "${P2P_PORT}:${P2P_PORT}"
      - "${P2P_PORT}:${P2P_PORT}/udp"
    volumes:
      - ./geth-data:/root/.ethereum
      - ./jwtsecret/jwtsecret:/root/.ethereum/jwtsecret:ro
    networks:
      - sepolia-net

  teku:
    image: consensys/teku:latest
    container_name: sepolia-teku
    restart: unless-stopped
    depends_on:
      - geth
    user: root
    volumes:
      - ./teku-data:/data
      - ./jwtsecret/jwtsecret:/data/jwtsecret:ro
    entrypoint:
      - /bin/sh
      - -c
      - |
        mkdir -p /data/logs && \
        exec teku \
          --network=sepolia \
          --checkpoint-sync-url=https://sepolia.checkpoint-sync.ethpandaops.io \
          --data-path=/data \
          --logging=INFO \
          --ee-jwt-secret-file=/data/jwtsecret \
          --ee-endpoint=http://geth:${AUTHRPC_PORT} \
          --p2p-peer-lower-bound=20 \
          --rest-api-enabled \
          --rest-api-interface=0.0.0.0 \
          --rest-api-port=${TEKU_REST_PORT} \
          --metrics-enabled \
          --metrics-interface=0.0.0.0 \
          --ignore-weak-subjectivity-period-enabled
    ports:
      - "${TEKU_REST_PORT}:${TEKU_REST_PORT}"
    networks:
      - sepolia-net

networks:
  sepolia-net:
    driver: bridge
EOF
}

start_stack() {
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Containers started."
}

# --- Main ---
echo -e "\n📣 Не забудьте перед перезапуском удалить старые базы:\n  rm -rf $DATA_DIR/teku-data/beacon/db\n  rm -rf $DATA_DIR/geth-data"
read
install_docker
prompt_wipe_geth
prompt_wipe_teku
generate_jwt
write_compose
start_stack


