#!/usr/bin/env bash
# Vault Hunters co-op smoke test (Linux, no game needed).
#
# Starts the real server (native + managed) and drives it with the bot harness:
#   1. three bots join -> every bot must receive a vh.session roster naming the first one host
#   2. bots exchange script events -> each must receive the others' events, sender stamped
#   3. a bot sends its class avatar -> the others must see that puppet respawn with the record
# Exits non-zero on the first failed expectation.
#
# Usage: coop-smoke-test.sh <server-out-dir> <bot-harness-binary> [port]
set -euo pipefail

SERVER_DIR=$1
BOT=$2
PORT=${3:-14777}
LOG_DIR=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

cd "$SERVER_DIR"
SERVER_CMD=(dotnet Cyberverse.Server.dll --port="$PORT")
[ -x ./Cyberverse.Server ] && SERVER_CMD=(./Cyberverse.Server --port="$PORT")
"${SERVER_CMD[@]}" > "$LOG_DIR/server.log" 2>&1 &
sleep 4

timeout -s INT 12 "$BOT" --server 127.0.0.1 --port "$PORT" --count 3 --pattern static \
    --script-every 2 --avatar Character.Judy --avatar-delay 3 > "$LOG_DIR/bots.log" 2>&1 || true

fail() { echo "FAIL: $1"; echo "--- server"; tail -40 "$LOG_DIR/server.log"; echo "--- bots"; tail -60 "$LOG_DIR/bots.log"; exit 1; }

grep -q 'session: host 1, 3 member(s)' "$LOG_DIR/bots.log" || fail "no 3-member roster with host 1"
for me in 1 2 3; do
    grep -q "me $me, roster \"1:Bot01;2:Bot02;3:Bot03\"" "$LOG_DIR/bots.log" || fail "bot $me never learned its own id"
done
for bot in Bot01 Bot02 Bot03; do
    n=$(grep -c "^\[$bot\] script event: .*hello from" "$LOG_DIR/bots.log" || true)
    [ "$n" -ge 2 ] || fail "$bot received $n script events (expected >= 2)"
    grep -q "^\[$bot\] script event: .*hello from $bot\"" "$LOG_DIR/bots.log" && fail "$bot received its own event"
done
grep -q 'from 3735928559' "$LOG_DIR/bots.log" && fail "server did not overwrite the client-sent sender"
JUDY=$(grep -o 'avatar record "Character.Judy" -> tdbid [0-9]*' "$LOG_DIR/bots.log" | awk '{print $NF}')
[ -n "$JUDY" ] || fail "harness did not report the avatar tdbid"
grep -q "peer entity spawned: networkId [0-9]* (record $JUDY)" "$LOG_DIR/bots.log" || fail "no puppet respawned with the avatar record"

echo "PASS: roster, relay, sender stamping and avatar respawn"
