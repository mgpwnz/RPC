#!/usr/bin/env bash
# sepolia_checker.sh — проверка прогресса синхронизации Sepolia-нод

# URL вашего JSON-RPC
RPC_URL="${1:-http://localhost:8545}"

# Функция, выводящая прогресс
print_progress() {
  # Получаем JSON-ответ от eth_syncing
  resp=$(curl -s "$RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

  # Если вернулось false — нода синхронизирована
  if jq -e '.result == false' <<<"$resp" >/dev/null; then
    echo "✅ Node is fully synced."
    exit 0
  fi

  # Иначе — парсим текущий и целевой блоки
  cur_hex=$(jq -r .result.currentBlock <<<"$resp")
  max_hex=$(jq -r .result.highestBlock  <<<"$resp")

  # Конвертация hex(0x…) → dec (bash умеет это напрямую)
  cur=$((cur_hex))
  max=$((max_hex))

  # Вычисляем процент
  pct=$(awk "BEGIN{ if ($max>0) printf \"%.2f\", $cur/$max*100; else print \"0.00\" }")

  printf "🔄 Sync progress: %6s%% (%d/%d blocks)\n" "$pct" "$cur" "$max"
}

# Если передан параметр interval (интервал в секундах), запускаем в цикле
if [[ -n "$2" ]]; then
  interval=$2
  while true; do
    date '+%F %T'
    print_progress
    sleep "$interval"
    echo
  done
else
  # Однократный вывод
  print_progress
fi
