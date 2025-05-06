#!/usr/bin/env bash
set -euo pipefail

# Sepolia Sync Monitor Script (v5)
# Allows piping via curl | bash -s -- RPC_URL [TEKU_URL] [INTERVAL]
# Usage:
#   curl -sL https://.../sepolia_sync_monitor.sh | bash -s -- RPC_URL [TEKU_URL] [INTERVAL]
# Examples:
#   | bash -s -- http://localhost:8545
#   | bash -s -- http://localhost:8545 5
#   | bash -s -- http://localhost:8545 http://localhost:5051 5

# Default values
default_rpc="http://localhost:8545"
default_teku="http://localhost:5051"
default_interval=10

# Parse args
total_args=$#
RPC_URL="$default_rpc"
TEKU_URL="$default_teku"
INTERVAL=$default_interval

if (( total_args == 1 )); then
  RPC_URL="$1"
elif (( total_args == 2 )); then
  if [[ "$2" =~ ^[0-9]+$ ]]; then
    RPC_URL="$1"
    INTERVAL=$2
  else
    RPC_URL="$1"
    TEKU_URL="$2"
  fi
elif (( total_args >= 3 )); then
  RPC_URL="$1"
  TEKU_URL="$2"
  INTERVAL=$3
fi

enabled_geth="true"

echo "🔍 Monitoring Sepolia nodes:"
echo "   Geth RPC:    $RPC_URL"
echo "   Teku REST:   $TEKU_URL"
echo "   Interval(s): $INTERVAL"
echo

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

  # Skip if no sync data
  if [[ "$max_hex" == "0x0" ]]; then
    echo "$(date '+%F %T')  ⏳ Geth: no sync data available"
    return
  fi

  # Convert hex (0x...) to decimal
  cur=$((cur_hex))
  max=$((max_hex))
  rem=$(( max - cur ))

  # Calculate percentage using shell variables
  if (( max > 0 )); then
    pct=$(awk "BEGIN{printf \"%.2f\", ${cur}/${max}*100}")
  else
    pct="0.00"
  fi

  echo "$(date '+%F %T')  ⏳ Geth: $pct% synced ($cur/$max), remaining blocks: $rem"
}

# Function to check Teku sync status
check_teku() {
  data=$(curl -s "$TEKU_URL/eth/v1/node/syncing" 2>/dev/null)
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