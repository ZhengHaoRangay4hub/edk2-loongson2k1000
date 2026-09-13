#!/usr/bin/env sh
# Boot the QEMU-regression firmware built by this repo's CI in
# qemu-system-loongarch64 and drop into the UEFI Setup UI over serial.
#
# Usage: scripts/test-qemu-virt.sh <QEMU_EFI.fd> [QEMU_VARS.fd]
#
# Exits after 60s. Serial output (progress codes, BDS banner, Setup UI
# escape-sequence frames) is written to /tmp/qemu_ui.log.
set -eu

EFI=${1:?usage: test-qemu-virt.sh <QEMU_EFI.fd> [QEMU_VARS.fd]}
VARS=${2:-/tmp/ls2k-qemu-vars.fd}

cp -f "$(dirname "$0")/../QEMU_VARS.fd" "$VARS" 2>/dev/null || true
[ -f "$VARS" ] || : > "$VARS"

rm -f /tmp/ls2k-qemu-in.fifo
mkfifo /tmp/ls2k-qemu-in.fifo

# 20s: BDS prompt -> Enter opens the Boot Manager Menu (UiApp)
( sleep 20; printf '\r'; sleep 40 ) > /tmp/ls2k-qemu-in.fifo &

qemu-system-loongarch64 \
    -m 2G -M virt -smp 2 -cpu la464 \
    -drive if=pflash,format=raw,file="$EFI",readonly=on \
    -drive if=pflash,format=raw,file="$VARS" \
    -serial stdio -monitor none -display none \
    < /tmp/ls2k-qemu-in.fifo

rm -f /tmp/ls2k-qemu-in.fifo
