#!/bin/bash
# Step-by-step chromium debug. Each line prints what it's about to do.

LOG=/tmp/chr.log
PORT=9222

step() { echo ""; echo "==> $1"; }

step "1. Memory"
free -h

step "2. Disk usage"
df -h /tmp /

step "3. Kill any leftover chromium"
pgrep -x chromium && pkill -9 -x chromium
sleep 1
echo "    done"

step "4. Remove old log"
rm -f "$LOG"
echo "    done"

step "5. Launch chromium (background)"
chromium --headless \
    --no-sandbox \
    --disable-setuid-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-port=$PORT \
    about:blank > "$LOG" 2>&1 &
CHR_PID=$!
echo "    PID: $CHR_PID"

step "6. Sleep 5s"
sleep 5
echo "    awake"

step "7. Is chromium still alive?"
if kill -0 $CHR_PID 2>/dev/null; then
    echo "    ALIVE (PID $CHR_PID)"
else
    echo "    DEAD"
fi

step "8. Process tree"
pgrep -ax chromium || echo "    no chromium processes"

step "9. /proc/net/tcp listening (port 9222 = 2406 hex)"
awk 'NR>1 && $4=="0A" && $2 ~ /:2406$/ {print "    IPv4 listening: "$2}' /proc/net/tcp
awk 'NR>1 && $4=="0A" && $2 ~ /:2406$/ {print "    IPv6 listening: "$2}' /proc/net/tcp6
echo "    (no match above = nothing on 9222)"

step "10. Log (devtools line + last 5 errors)"
grep -i 'devtools listening' "$LOG" || echo "    NO 'DevTools listening' line in log"
echo "    --- last 5 non-noise lines ---"
grep -v 'dbus\|gcm\|UPower\|NameHasOwner' "$LOG" | tail -5

step "11a. curl /json/version (HTTP)"
timeout 5 curl -sv "http://127.0.0.1:$PORT/json/version" 2>&1 | head -15

step "11b. WebSocket upgrade test"
timeout 5 curl -sv \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    "http://127.0.0.1:$PORT/" 2>&1 | head -15

step "12. Cleanup"
pkill -9 -x chromium
echo "    done"
