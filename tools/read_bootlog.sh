#!/bin/bash
#
# Read the SPI NOR with the CH341A and decode the firmware's boot progress log.
#
#   tools/read_bootlog.sh [dump-path]
#
# The firmware records every bring-up milestone into the flash window at
# 0x360000, so this works with no serial console at all: power the board (the
# log accumulates the furthest progress reached since the region was erased),
# move the chip to the programmer, run this, and read how far it got.
#
# The CH341A must be in SPI/programmer mode (USB ID 1a86:5512).  If flashrom
# reports "Couldn't open device 1a86:5512", the board is in its UART-mode
# position -- move the mode jumper and replug USB.
#
set -u

FLASHROM="${FLASHROM:-$HOME/.local/opt/flashrom/sbin/flashrom}"
CHIP="W25Q32BV/W25Q32CV/W25Q32DV"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-/tmp/chip-$(date +%Y%m%d_%H%M%S).bin}"

[ -x "$FLASHROM" ] || { echo "flashrom not found at $FLASHROM" >&2; exit 1; }

echo "reading $OUT (4 MB, takes about a minute)"
if ! "$FLASHROM" -p ch341a_spi -c "$CHIP" -r "$OUT" >/tmp/read_bootlog.log 2>&1; then
  tail -5 /tmp/read_bootlog.log
  echo
  echo "read failed. If the log says 'Couldn't open device 1a86:5512', the" >&2
  echo "CH341A is in UART mode: move the mode jumper to SPI and replug USB." >&2
  exit 1
fi

echo "saved $OUT"
echo
python3 "$HERE/decode_bootlog.py" "$OUT"
