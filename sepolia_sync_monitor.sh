#!/usr/bin/env bash
set -euo pipefail

# Sepolia Sync Monitor Script
# Continuously reports Geth (execution) and Teku (beacon) sync status.
# Usage: ./sepolia_sync_monitor.sh [RPC_URL] [TEKU_URL] [INTERVAL]
# Defaults: RPC_URL=http://localhost:8545, TEKU_URL=http://localhost:5051, INTERVAL=10

RPC_URL="${1:-http://localhost:8545}"
TEKU_URL="${2:-http://localhost:5051}"
INTERVAL="${3:-10}"

# Check Geth sync
check_geth() {
  resp=$(curl -s "$RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

  if jq -e '.result == false' <<<"$resp" >/dev/null; then
    echo "$(date '+%F %T')  🚀 Geth: fully synced"
  else
    cur_hex=$(jq -r .result.currentBlock <<<"$resp")
    max_hex=$(jq -r .result.highestBlock  <<<"$resp")
    cur=$((cur_hex))
    max=$((max_hex))
    rem=$((max - cur))
    pct=$(awk "BEGIN{printf \"%.2f\", cur/max*100}")
    echo "$(date '+%F %T')  ⏳ Geth: $pct% synced ($cur/$max), remaining blocks: $rem"
  fi
}

# Check Teku sync
check_teku() {
  data=$(curl -s "$TEKU_URL/eth/v1/node/syncing")
  head_slot=$(jq -r .data.head_slot <<<"$data")
  sync_dist=$(jq -r .data.sync_distance <<<"$data")

  if [[ "$sync_dist" == "0" ]]; then
    echo "$(date '+%F %T')  🚀 Teku: fully synced (head slot: $head_slot)"
  else
    echo "$(date '+%F %T')  ⏳ Teku: syncing, head slot: $head_slot, remaining slots: $sync_dist"
  fi
}

# Main loop
while true; do
  check_geth
  check_teku
  echo
  sleep "$INTERVAL"
done
