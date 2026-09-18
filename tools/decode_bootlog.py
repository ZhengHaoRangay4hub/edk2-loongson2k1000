#!/usr/bin/env python3
"""Decode the firmware's boot progress log out of a SPI NOR dump.

The firmware records every bring-up milestone in the flash window at
0x360000..0x370000: a 16-byte header followed by one 4-byte slot per event
code (see Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonBootLogLib).
Reading the chip with a programmer is therefore enough to tell how far the boot
got -- no serial console needed.

The log is write-only and is never erased by the firmware, so it accumulates
the furthest progress reached since the region was last erased -- a fresh
firmware image (its log window is 0xFF) gives a clean slate, as does erasing
the sector with the programmer.

Usage:
    python3 decode_bootlog.py <dump.bin>
    python3 decode_bootlog.py <dump.bin> --hex     # raw slot values too

The dump may be a full 4 MB image or a 4 KB/64 KB read starting at 0x360000.
"""

import argparse
import sys

LOG_BASE = 0x360000
LOG_SIZE = 0x10000
HDR = 16
SLOT = 4
MARK = 0x5A
MAGIC = b"BLOG"
VERSION = 1

# code -> (severity, text).  Keep in sync with Include/Library/LoongsonBootLog.h
EVENTS = {
    0x01: ("info", "SEC entry (reset vector reached us)"),
    0x02: ("info", "SEC spi flash speedup done"),
    0x03: ("info", "SEC APB window opened"),
    0x04: ("info", "SEC uart pin mux set"),
    0x05: ("info", "SEC external watchdog released"),
    0x06: ("info", "SEC console uart initialised"),
    0x07: ("info", "SEC PCIe early config done"),
    0x08: ("info", "SEC SoC early init done"),
    0x09: ("info", "SEC clock/PLL bring-up begin"),
    0x0A: ("info", "SEC clock/PLL bring-up done"),
    0x0B: ("info", "SEC DDR init begin"),
    0x0C: ("info", "SEC DDR init done"),
    0x0D: ("info", "SEC device tree copied"),
    0x0E: ("info", "SEC handing over to PEI"),
    0x10: ("info", "PEI core entry"),
    0x11: ("info", "PEI low RAM described"),
    0x12: ("info", "PEI high RAM described"),
    0x13: ("info", "PEI device tree relocated"),
    0x14: ("info", "PEI done"),
    0x20: ("info", "DXE display driver entry"),
    0x28: ("info", "DXE DC BAR0 read"),
    0x29: ("warn", "DXE DC BAR0 unusable, internal window assumed"),
    0x2A: ("info", "DXE SII9022A found on I2C1"),
    0x2B: ("warn", "DXE SII9022A MISSING on I2C1"),
    0x2C: ("info", "DXE GOP installed"),
    0x2D: ("error", "DXE GOP install FAILED"),
    0x30: ("info", "BDS entry"),
    0x31: ("info", "BDS boot attempt"),
    0x32: ("info", "BDS shell"),
    0xE0: ("error", "assertion"),
    0xE1: ("error", "CPU exception"),
    0xE2: ("error", "hang reported"),
}


def find_base(data):
    if len(data) >= LOG_SIZE and data[LOG_BASE:LOG_BASE + 4] in (MAGIC, b"\xff\xff\xff\xff"):
        return LOG_BASE
    if len(data) <= LOG_SIZE and data[:4] in (MAGIC, b"\xff\xff\xff\xff"):
        return 0
    idx = data.find(MAGIC)
    if idx >= 0:
        return idx - (idx % 0x1000)
    return None


def detail(code, arg):
    if code == 0x04:
        return "uart0_enable = 0x%x" % arg
    if code in (0x11, 0x12):
        return "%d MB" % arg
    if code == 0x0C:
        return "raw 0x%x (DDR code's own units)" % arg
    if code == 0x0D:
        return ("%d bytes" % arg) if arg else "NOT FOUND"
    if code == 0x13:
        return "0x%06x" % arg
    if code == 0x28:
        return "BAR0 = 0x%05x000" % arg
    if code == 0x2C:
        return "%dx%d" % (arg >> 12, arg & 0xFFF)
    if code == 0x2D:
        return "status 0x%x" % arg
    if code in (0xE0, 0xE1, 0xE2):
        return "0x%x" % arg
    return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump")
    ap.add_argument("--hex", action="store_true", help="also print raw slot bytes")
    args = ap.parse_args()

    data = open(args.dump, "rb").read()
    base = find_base(data)
    if base is None:
        print("no boot log found in %s" % args.dump)
        return 1

    hdr = data[base:base + HDR]
    if hdr[:4] != MAGIC:
        print("log header is not written (window still erased or foreign data)")
        print("=> the firmware did not reach its first milestone, or the flash")
        print("   write path failed; first 16 bytes: %s" % hdr.hex(" "))
        return 1
    if hdr[4] != VERSION:
        print("unexpected log version %d (expected %d)" % (hdr[4], VERSION))
        return 1

    print("boot log at file offset 0x%x (format v%d)" % (base, hdr[4]))
    print("write-only log: shows the furthest progress since the region was erased")
    print()

    seen = []
    for code in range(1, 0xFF):
        off = base + HDR + code * SLOT
        if off + SLOT > base + LOG_SIZE:
            break
        slot = data[off:off + SLOT]
        if len(slot) < SLOT or slot[3] != MARK:
            continue
        arg = slot[0] | (slot[1] << 8) | (slot[2] << 16)
        seen.append((code, arg, slot))

    if not seen:
        print("header present but no event slots are marked -- the boot died")
        print("between the first milestone and the next one")
        return 1

    for code, arg, slot in seen:
        sev, text = EVENTS.get(code, ("info", "unknown event 0x%02x" % code))
        det = detail(code, arg)
        line = "  0x%02x  %-6s %s" % (code, sev, text)
        if det:
            line += " [%s]" % det
        print(line)
        if args.hex:
            print("             raw: %s" % slot.hex(" "))

    last_code = seen[-1][0]
    sev, text = EVENTS.get(last_code, ("info", "unknown 0x%02x" % last_code))
    print()
    print("  -> last milestone reached: %s" % text)
    if last_code in (0x2B, 0x2D, 0xE0, 0xE1, 0xE2):
        print("     (the failure is here or immediately after)")
    elif last_code >= 0x30:
        print("     (BDS was reached)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
