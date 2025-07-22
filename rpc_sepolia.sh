#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
GETH_DATA="$DATA_DIR/geth-data"
TEKU_DATA="$DATA_DIR/teku-data"
SECRETS_DIR="$DATA_DIR/secrets"
JWT_FILE="$SECRETS_DIR/jwt.hex"

# Default ports (можно править здесь или экспортить перед запуском)
HTTP_PORT="${HTTP_PORT:-8545}"
WS_PORT="${WS_PORT:-8546}"
AUTHRPC_PORT="${AUTHRPC_PORT:-8551}"
P2P_PORT="${P2P_PORT:-30303}"
TEKU_REST_PORT="${TEKU_REST_PORT:-5051}"

# 1) Создаём директории
mkdir -p \
  "$GETH_DATA" \
  "$TEKU_DATA" \
  "$SECRETS_DIR"

# 2) Генерируем JWT, если ещё нет
if [[ ! -f "$JWT_FILE" ]]; then
  openssl rand -hex 32 | tr -d '\n' > "$JWT_FILE"
  chmod 640 "$JWT_FILE"
fi

# 3) Пишем docker-compose.yml «вшитый» тут же
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
networks:
  sepolia-net:
    driver: bridge

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
      - --http.corsdomain=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=${WS_PORT}
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=${AUTHRPC_PORT}
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
      - --port=${P2P_PORT}
    ports:
      - "${HTTP_PORT}:${HTTP_PORT}"
      - "${WS_PORT}:${WS_PORT}"
      - "${AUTHRPC_PORT}:${AUTHRPC_PORT}"
      - "${P2P_PORT}:${P2P_PORT}"
      - "${P2P_PORT}:${P2P_PORT}/udp"
    volumes:
      - ./geth-data:/root/.ethereum
      - ./secrets/jwt.hex:/root/.ethereum/jwtsecret:ro
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
      - ./secrets/jwt.hex:/data/jwtsecret:ro
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
          --rest-api-host-allowlist="*" \
          --metrics-enabled \
          --metrics-interface=0.0.0.0 \
          --ignore-weak-subjectivity-period-enabled
    ports:
      - "${TEKU_REST_PORT}:${TEKU_REST_PORT}"
    networks:
      - sepolia-net
EOF

# 4) Запускаем стек
cd "$DATA_DIR"
docker compose up -d

echo -e "\n✅ Полная установка завершена!"
echo "  • Данные Geth   → $GETH_DATA"
echo "  • Данные Teku   → $TEKU_DATA"
echo "  • JWT secret    → $JWT_FILE"
echo "  • Compose файл  → $COMPOSE_FILE"
