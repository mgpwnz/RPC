#!/usr/bin/env bash
set -euo pipefail

# Sepolia Sync Monitor Script (v6)
# Pipeable: curl ... | bash -s -- RPC_URL [TEKU_URL] [INTERVAL]
# Usage:
#   curl -sL <url>/sepolia_sync_monitor.sh | bash -s -- RPC_URL [TEKU_URL] [INTERVAL]
# Examples:
#   ... | bash -s -- http://localhost:8545
#   ... | bash -s -- http://localhost:8545 5
#   ... | bash -s -- http://localhost:8545 http://localhost:5051 5

# Defaults
default_rpc="http://localhost:8545"
default_teku="http://localhost:5051"
default_interval=10

# Parse arguments
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

# Strip trailing slashes
RPC_URL=${RPC_URL%/}
TEKU_URL=${TEKU_URL%/}

enabled_geth="true"

echo "🔍 Monitoring Sepolia nodes:"
echo "   Geth RPC:    $RPC_URL"
echo "   Teku REST:   $TEKU_URL"
echo "   Interval(s): $INTERVAL"
echo

# Check Geth sync status
enable_formatter=false
check_geth() {
  resp=$(curl -s "$RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

  if jq -e '.result == false' <<<"$resp" >/dev/null 2>&1; then
    echo "$(date '+%F %T')  🚀 Geth: fully synced"
    enabled_geth="false"
    return
  fi

  cur_hex=$(jq -r '.result.currentBlock // "0x0"' <<<"$resp" 2>/dev/null)
  max_hex=$(jq -r '.result.highestBlock  // "0x0"' <<<"$resp" 2>/dev/null)

  if [[ "$max_hex" == "0x0" ]]; then
    echo "$(date '+%F %T')  ⏳ Geth: no sync data available"
    return
  fi

  cur=$((cur_hex))
  max=$((max_hex))
  rem=$(( max - cur ))

  pct=$(awk "BEGIN{printf \"%.2f\", ( ($max>0)? $cur/$max*100 : 0 ) }")
  echo "$(date '+%F %T')  ⏳ Geth: $pct% synced ($cur/$max), remaining blocks: $rem"
}

# Check Teku sync status
check_teku() {
  raw=$(curl -s -H "Host: localhost" "$TEKU_URL/eth/v1/node/syncing" 2>/dev/null)
  if ! jq -e . >/dev/null <<<"$raw" 2>&1; then
    echo "$(date '+%F %T')  ❌ Teku: invalid JSON response"
    return
  fi

  head_slot=$(jq -r '.data.head_slot // empty' <<<"$raw")
  sync_dist=$(jq -r '.data.sync_distance // empty' <<<"$raw")

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
