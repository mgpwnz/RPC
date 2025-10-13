#!/usr/bin/env bash
set -euo pipefail

# === Параметры ===
DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"

# Папки для bind‑mount’ов
GETH_DATA="$DATA_DIR/geth-data"
BEACON_DATA="$DATA_DIR/beacon-data"
SECRETS_DIR="$DATA_DIR/secrets"
JWT_FILE="$SECRETS_DIR/jwt.hex"

# 1) Создаём структуру
mkdir -p "$GETH_DATA" "$BEACON_DATA" "$SECRETS_DIR"

# 2) Генерируем JWT, если его нет
if [[ ! -f "$JWT_FILE" ]]; then
  openssl rand -hex 32 > "$JWT_FILE"
  chmod 644 "$JWT_FILE"
  echo "✅ JWT secret создан: $JWT_FILE"
fi

# 3) Пишем docker-compose.yml (точно из вашего файла) :contentReference[oaicite:3]{index=3}
cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

networks:
  sepolia-net:

services:
  geth:
    image: ethereum/client-go:stable
    networks:
      sepolia-net:
        aliases:
          - geth
    volumes:
      - ${PWD}/geth-data:/data
      - ${PWD}/secrets/jwt.hex:/var/lib/secrets/jwt.hex:ro
    command:
      - --sepolia
      - --http
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.api=eth,net,engine,admin
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --http.vhosts=*
      - --authrpc.vhosts=*
      - --http.corsdomain=*
      - --authrpc.jwtsecret=/var/lib/secrets/jwt.hex
      - --datadir=/data
    ports:
      - "8545:8545"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    restart: unless-stopped

  beacon:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:v6.1.2
    depends_on:
      - geth
    networks:
      - sepolia-net
    volumes:
      - ${PWD}/beacon-data:/data
      - ${PWD}/secrets/jwt.hex:/jwt.hex:ro
    command:
      - --sepolia
      - --http-modules=beacon,config,node,validator
      - --rpc-host=0.0.0.0
      - --rpc-port=4000
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --datadir=/data
      - --execution-endpoint=http://geth:8551
      - --jwt-secret=/jwt.hex
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io/
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io/
      - --accept-terms-of-use
      - --subscribe-all-data-subnets
    ports:
      - "4000:4000"
      - "3500:3500"
    restart: unless-stopped

# убрали секцию volumes из оригинала
EOF

echo "✅ Записан $COMPOSE_FILE"

# 4) Запускаем стек
cd "$DATA_DIR"
docker compose up -d

echo -e "\n🚀 Sepolia full‑нода (Geth) + Beacon подняты!"
echo "  • Geth data   → $GETH_DATA"
echo "  • Beacon data → $BEACON_DATA"
echo "  • JWT secret  → $JWT_FILE"
echo "  • Compose     → $COMPOSE_FILE"
