#!/usr/bin/env bash
set -euo pipefail

# === Sepolia Full-Node + Beacon Setup Script (v3) ===
# Adds customizable HTTP RPC port (default: 8545)

DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
GETH_DATA_DIR="$DATA_DIR/geth-data"
TEKU_DATA_DIR="$DATA_DIR/teku-data"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"

# === Prompt for custom HTTP RPC port ===
read -rp "🛠️  Enter HTTP RPC port (default: 8545): " HTTP_PORT
HTTP_PORT="${HTTP_PORT:-8545}"

default_ws_port=8546

echo "Using HTTP RPC on port: $HTTP_PORT"

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
      - --http.port=$HTTP_PORT
      - --http.api=eth,net,web3,engine
      - --http.vhosts=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=$default_ws_port
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
      - --authrpc.vhosts=*
    ports:
      - "$HTTP_PORT:$HTTP_PORT"
      - "$default_ws_port:$default_ws_port"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
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
          --ee-endpoint=http://geth:8551 \
          --p2p-peer-lower-bound=20 \
          --rest-api-enabled \
          --rest-api-interface=0.0.0.0 \
          --rest-api-port=5051 \
          --metrics-enabled \
          --metrics-interface=0.0.0.0 \
          --ignore-weak-subjectivity-period-enabled
    ports:
      - "5051:5051"
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
install_docker
prompt_wipe_geth
prompt_wipe_teku
generate_jwt
write_compose
start_stack

echo -e "\n📣 Не забудьте перед перезапуском видалить старые базы:\n  rm -rf $DATA_DIR/teku-data/beacon/db\n  rm -rf $DATA_DIR/geth-data"
