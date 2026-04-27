#!/bin/bash
LOG=/tmp/chr.log
PORT=9222

step() { echo ""; echo "==> $1"; }

step "1. Kill leftovers"
pkill -9 -x chromium 2>/dev/null
sleep 1

step "2. Launch chromium"
chromium --headless \
    --no-sandbox \
    --disable-setuid-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-port=$PORT \
    about:blank > "$LOG" 2>&1 &
CHR_PID=$!
echo "    PID: $CHR_PID"

step "3. Wait 5s"
sleep 5

step "4. Is chromium alive?"
kill -0 $CHR_PID 2>/dev/null && echo "    yes" || echo "    DEAD"

step "5. Full /proc/net/tcp (IPv4)"
cat /proc/net/tcp

step "6. Full /proc/net/tcp6 (IPv6)"
cat /proc/net/tcp6

step "7. Test TCP with bash /dev/tcp"
exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null && {
    echo "    /dev/tcp connect: OK"
    echo -e "GET /json/version HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3
    echo "    Reading response (3s timeout)..."
    timeout 3 cat <&3
    exec 3<&-
} || echo "    /dev/tcp connect: FAILED"

step "8. nc test (if available)"
if command -v nc >/dev/null; then
    echo "GET /json/version HTTP/1.0" | timeout 3 nc -w 2 127.0.0.1 $PORT
else
    echo "    (nc not installed)"
fi

step "9. Log devtools line"
grep -i 'devtools listening' "$LOG"

step "10. Cleanup"
pkill -9 -x chromium 2>/dev/null
echo "    done"
