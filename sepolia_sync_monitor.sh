#!/usr/bin/env bash
set -euo pipefail

# Sepolia Sync Monitor Script (updated to avoid division by zero)
# Continuously reports Geth (execution) and Teku (beacon) sync status.
# Usage: ./sepolia_sync_monitor.sh [RPC_URL] [TEKU_URL] [INTERVAL]
# Defaults: RPC_URL=http://localhost:8545, TEKU_URL=http://localhost:5051, INTERVAL=10

RPC_URL="${1:-http://localhost:8545}"
TEKU_URL="${2:-http://localhost:5051}"
INTERVAL="${3:-10}"

# Function to check Geth sync status
enabled_geth="true"
check_geth() {
  resp=$(curl -s "$RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

  # If result == false, node is synced\ if jq -e '.result == false' <<<"$resp" >/dev/null; then
    echo "$(date '+%F %T')  🚀 Geth: fully synced"
    enabled_geth="false"
  else
    # parse hex values
    cur_hex=$(jq -r .result.currentBlock <<<"$resp" 2>/dev/null)
    max_hex=$(jq -r .result.highestBlock  <<<"$resp" 2>/dev/null)

    # convert hex to dec
    cur=$((cur_hex))
    max=$((max_hex))
    rem=$(( max > cur ? max - cur : 0 ))

    if (( max > 0 )); then
      pct=$(awk "BEGIN{printf \"%.2f\", cur/max*100}")
      echo "$(date '+%F %T')  ⏳ Geth: $pct% synced ($cur/$max), remaining blocks: $rem"
    else
      echo "$(date '+%F %T')  ⏳ Geth: querying syncing status..."
    fi
  fi
}

# Function to check Teku sync status
check_teku() {
  data=$(curl -s "$TEKU_URL/eth/v1/node/syncing")
  head_slot=$(jq -r .data.head_slot <<<"$data" 2>/dev/null)
  sync_dist=$(jq -r .data.sync_distance <<<"$data" 2>/dev/null)

  if [[ "$sync_dist" == "0" ]]; then
    echo "$(date '+%F %T')  🚀 Teku: fully synced (head slot: $head_slot)"
  else
    echo "$(date '+%F %T')  ⏳ Teku: syncing, head slot: $head_slot, remaining slots: $sync_dist"
  fi
}

# Main loop
while true; do
  if [[ "$enabled_geth" == "true" ]]; then
    check_geth
  fi
  check_teku
  echo
  sleep "$INTERVAL"
done
