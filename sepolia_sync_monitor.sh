#!/usr/bin/env bash
set -euo pipefail

# Sepolia Sync Monitor Script (v3)
# Continuously reports Geth (execution) and Teku (beacon) sync status.
# Usage: ./sepolia_sync_monitor.sh [RPC_URL] [TEKU_URL] [INTERVAL]
# Defaults: RPC_URL=http://localhost:8545, TEKU_URL=http://localhost:5051, INTERVAL=10

RPC_URL="${1:-http://localhost:8545}"
TEKU_URL="${2:-http://localhost:5051}"
INTERVAL="${3:-10}"

enabled_geth="true"

# Function to check Geth sync status
check_geth() {
  resp=$(curl -s "$RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

  # If result is boolean false, node is fully synced
  if jq -e '.result == false' <<<"$resp" >/dev/null 2>&1; then
    echo "$(date '+%F %T')  🚀 Geth: fully synced"
    enabled_geth="false"
    return
  fi

  # Extract hex fields, defaulting to 0x0 if missing
  cur_hex=$(jq -r '.result.currentBlock // "0x0"' <<<"$resp" 2>/dev/null)
  max_hex=$(jq -r '.result.highestBlock  // "0x0"' <<<"$resp" 2>/dev/null)

  # If highestBlock is zero, skipping calculation
  if [[ "$max_hex" == "0x0" ]]; then
    echo "$(date '+%F %T')  ⏳ Geth: no sync data available"
    return
  fi

  # Convert hex (0x...) to decimal
  cur=$((cur_hex))
  max=$((max_hex))
  rem=$((max - cur))

  # Calculate percentage
  pct=$(awk "BEGIN{printf \"%.2f\", ($max>0 ? $cur/$max*100 : 0)}")
  echo "$(date '+%F %T')  ⏳ Geth: $pct% synced ($cur/$max), remaining blocks: $rem"
}

# Function to check Teku sync status
check_teku() {
  data=$(curl -s "$TEKU_URL/eth/v1/node/syncing")
  head_slot=$(jq -r '.data.head_slot // empty' <<<"$data")
  sync_dist=$(jq -r '.data.sync_distance // empty' <<<"$data")

  if [[ -z "$sync_dist" ]]; then
    echo "$(date '+%F %T')  ❌ Teku: no sync data available"
  elif [[ "$sync_dist" == "0" ]]; then
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

