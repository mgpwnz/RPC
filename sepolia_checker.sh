#!/usr/bin/env bash
# sync-progress.sh

RPC_URL="http://localhost:8545"

# Получаем JSON
resp=$(curl -s "$RPC_URL" \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

# Парсим поля currentBlock и highestBlock (они с 0x-префиксом)
cur_hex=$(jq -r .result.currentBlock <<<"$resp")
max_hex=$(jq -r .result.highestBlock  <<<"$resp")

# Конвертируем hex(0x…) → dec
# Bash умеет парсить 0x… внутри $((…))
cur=$((cur_hex))
max=$((max_hex))

# Считаем процент через awk (или bc)
pct=$(awk "BEGIN{ if ($max>0) printf \"%.2f\", $cur/$max*100; else print \"0.00\" }")

printf "Sync progress: %6s%% (%d/%d blocks)\n" "$pct" "$cur" "$max"
