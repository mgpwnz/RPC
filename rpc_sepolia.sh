#!/usr/bin/env bash
set -euo pipefail

# === Sepolia Full-Node + Beacon Setup Script ===

# ---- Configuration ----
DATA_DIR="$HOME/sepolia-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
GETH_DATA_DIR="$DATA_DIR/geth-data"
TEKU_DATA_DIR="$DATA_DIR/teku-data"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"

# По замовчуванню синхронізуємо без снапшоту
USE_SNAPSHOT=0
SNAPSHOT_URL=""  # Якщо знайдете робочий URL, можна вказати тут

# ---- 1) Встановити Docker & Compose, якщо не встановлені ----
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker & Compose..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "✅ Docker & Compose installed. (Можливо, потрібно перелогінитись)"
  else
    echo "ℹ️ Docker вже встановлений."
  fi
}

# ---- 2) (Опціонально) Запитати про використання снапшоту ----
prompt_snapshot() {
  if [[ -n "$SNAPSHOT_URL" ]]; then
    read -rp "⬇️ Використати снапшот для швидкого синку? [Y/n]: " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
      USE_SNAPSHOT=1
      echo "✅ Снапшот буде застосовано."
    else
      echo "⚠️ Синапшот пропущено; буде повний синк."
    fi
  fi
}

# ---- 3) Очистити старі дані Geth, якщо потрібно ----
prompt_wipe() {
  if [[ -d "$GETH_DATA_DIR/geth/chaindata" ]]; then
    read -rp "🗑️ Знайдені старі дані Geth; видалити їх? [Y/n]: " wipe_ans
    if [[ "$wipe_ans" =~ ^[Yy] ]]; then
      echo "🗑️ Видаляємо старі дані..."
      rm -rf "$GETH_DATA_DIR"
    else
      echo "⚠️ Старі дані збережено."
    fi
  fi
}

# ---- 4) Згенерувати JWT secret ----
generate_jwt() {
  mkdir -p "$JWT_DIR"
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Генеруємо JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT записаний у $JWT_FILE"
  else
    echo "ℹ️ JWT secret вже існує."
  fi
}

# ---- 5) Завантажити та розпакувати снапшот (якщо увімкнено) ----
download_snapshot() {
  if (( USE_SNAPSHOT )); then
    echo "⬇️ Завантаження снапшоту..."
    mkdir -p "$GETH_DATA_DIR/geth"
    curl -fsSL --retry 5 --retry-delay 5 -C - "$SNAPSHOT_URL" -o "$DATA_DIR/snapshot.tar.zst"
    echo "🗜️ Розпаковка..."
    tar -I zstd -xvf "$DATA_DIR/snapshot.tar.zst" -C "$GETH_DATA_DIR/geth"
    rm -f "$DATA_DIR/snapshot.tar.zst"
    echo "✅ Снапшот застосовано."
  fi
}

# ---- 6) Створити docker-compose.yml під Sepolia ----
write_compose() {
  echo "📄 Пишемо $COMPOSE_FILE"
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
EOF

  if (( USE_SNAPSHOT )); then
    cat >> "$COMPOSE_FILE" <<EOF
      - --syncmode=snap
EOF
  else
    cat >> "$COMPOSE_FILE" <<EOF
      - --syncmode=full
EOF
  fi

  cat >> "$COMPOSE_FILE" <<EOF
      - --gcmode=full
      - --cache=4096
      - --maxpeers=50
      - --http
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.api=eth,net,web3,engine
      - --http.vhosts=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=8546
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
      - --authrpc.vhosts=*
    ports:
      - "8545:8545"
      - "8546:8546"
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
          --data-path=/data \
          --logging=INFO \
          --ee-jwt-secret-file=/data/jwtsecret \
          --ee-endpoint=http://geth:8551 \
          --p2p-peer-lower-bound=20 \
          --rest-api-enabled \
          --rest-api-interface=0.0.0.0 \
          --rest-api-port=5051 \
          --metrics-enabled \
          --metrics-interface=0.0.0.0
    ports:
      - "5051:5051"
    networks:
      - sepolia-net

networks:
  sepolia-net:
    driver: bridge
EOF

  echo "✅ docker-compose.yml готовий."
}

# ---- 7) Запуск стека ----
start_stack() {
  echo "🚀 Піднімаємо контейнери..."
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Стек запущено. Логи можна дивитися командою:"
  echo "   cd $DATA_DIR && docker compose logs -f sepolia-geth sepolia-teku"
}

# ---- Main ----
install_docker
prompt_snapshot
prompt_wipe
generate_jwt
download_snapshot
write_compose
start_stack
