#!/usr/bin/env bash
set -euo pipefail

# === Конфигурация ===
DATA_DIR="${HOME}/hoodi-node"
GETH_DATA_DIR="${DATA_DIR}/geth-data"
TEKU_DATA_DIR="${DATA_DIR}/teku-data"
JWT_DIR="${DATA_DIR}/jwt"
JWT_FILE="${JWT_DIR}/jwtsecret"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo ">>> Устанавливаем Docker..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  else
    echo ">>> Docker установлен."
  fi
}

install_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo ">>> Устанавливаем Docker Compose..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "${DOCKER_CONFIG}/cli-plugins"
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
      -o "${DOCKER_CONFIG}/cli-plugins/docker-compose"
    chmod +x "${DOCKER_CONFIG}/cli-plugins/docker-compose"
  else
    echo ">>> Docker Compose установлен."
  fi
}

setup_dirs() {
  echo ">>> Создаём каталоги: geth, teku, jwt..."
  mkdir -p "${GETH_DATA_DIR}" "${TEKU_DATA_DIR}" "${JWT_DIR}"
}

# --- добавляем ---
echo ">>> Создаём поддиректорию logs для Teku…"
mkdir -p "${TEKU_DATA_DIR}/logs"
chmod 777 "${TEKU_DATA_DIR}/logs"


generate_jwt() {
  if [ ! -f "${JWT_FILE}" ]; then
    echo ">>> Генерируем JWT‑секрет..."
    openssl rand -hex 32 > "${JWT_FILE}"
  else
    echo ">>> JWT‑секрет уже есть."
  fi
}

download_snapshot() {
  echo ">>> Скачиваем снапшот…"
  BLOCK_NUMBER=$(curl -s https://snapshots.ethpandaops.io/hoodi/geth/latest)
  echo "    Последний снапшот: block $BLOCK_NUMBER"
  curl -sL "https://snapshots.ethpandaops.io/hoodi/geth/${BLOCK_NUMBER}/snapshot.tar.zst" \
    | tar -I zstd -xvf - -C "${GETH_DATA_DIR}"
}

create_compose() {
  echo ">>> Пишем docker-compose.yml без Validator API…"
  cat > "${COMPOSE_FILE}" <<EOF
services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth-hoodi
    restart: unless-stopped
    volumes:
      - ${GETH_DATA_DIR}:/root/.ethereum
      - ${JWT_DIR}:/data/jwt:ro
    ports:
      - "8545:8545"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    command: >
      --hoodi
      --syncmode snap
      --http
      --http.addr 0.0.0.0
      --http.port 8545
      --http.api eth,net,web3,txpool
      --http.corsdomain="*"
      --authrpc.addr 0.0.0.0
      --authrpc.port 8551
      --authrpc.jwtsecret=/data/jwt/jwtsecret
      --authrpc.vhosts=*
      --metrics

  teku:
    image: consensys/teku:latest
    container_name: teku-hoodi
    restart: unless-stopped
    depends_on:
      - geth
    volumes:
      - ${TEKU_DATA_DIR}:/opt/teku/data
      - ${JWT_DIR}:/data/jwt:ro
    ports:
      - "8008:8008"   # metrics
    command: >
      --network=hoodi
      --data-path=/opt/teku/data
      --ee-endpoint=http://geth:8551
      --ee-jwt-secret-file=/data/jwt/jwtsecret
      --metrics-enabled
      --metrics-port=8008
EOF
}


start_node() {
  echo ">>> Запускаем ноду…"
  docker compose -f "${COMPOSE_FILE}" up -d
  echo ">>> Логи geth: docker logs -f geth-hoodi"
}

# === Main ===
install_docker
install_docker_compose
setup_dirs
generate_jwt
download_snapshot
create_compose
start_node

echo "🎉 Полная нода Hoodi запущена."
