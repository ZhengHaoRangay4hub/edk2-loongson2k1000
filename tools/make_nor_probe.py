#!/usr/bin/env python3
"""Build a LoongArch ladder probe for the LS2K1000LA education board.

Diagnostics tool: emits PROBE_nor_window_test.bin (4 MB image) used to measure
how far instruction fetch through the low NOR window actually reaches on real
hardware.  Generated with an in-file LoongArch64 encoder whose every encoding
was cross-checked against real bytes from the factory PMON binary and verified
with capstone.  See docs/BRINGUP.md ("下一步") for how to read its output.


Why: the factory PMON never executes from the SPI NOR.  Its start.S enables the
SoC's 256 KB locked (scratch) cache at LOCK_CACHE_BASE, copies its own text
there and jumps into the copy:

    /* enable locked cache */  ... 0x1fe00200, LOCK_CACHE_SIZE = 0x40000
    /* copy flash code to scache */  a1 = NOR, a0 = start .. edata
    /* jump to locked cache address */  jirl zero, ra, 0

Our EDK II port instead runs SEC/PEI straight out of the NOR window for the
whole 3.4 MB firmware, so if instruction fetch through that window only covers
a limited region, the SEC dies at its very first `bl` (to +38 KB) without
printing anything -- which is exactly what the board does.

What the probe measures: how far instruction fetch through the low window
(LOCK_CACHE_BASE-relative, i.e. plain 0x1c000000 + offset) actually reaches.

    offset 0x0000  prologue (DMW, SPI, APB BAR, UART -- PMON's sequences)
    offset 0x0100  print "0 " then jump (low window) to 0x010000
    offset 0x010000 print "1 " then jump to 0x040000      <- rung 1
    offset 0x040000 print "2 " then jump to 0x100000      <- rung 2
    offset 0x100000 print "3 " then jump to 0x200000      <- rung 3
    offset 0x200000 print "4 " then jump to 0x300000      <- rung 4
    offset 0x300000 print "5 " then jump (DMW window) to 0x900000001c040000
    offset 0x040000+  DMW phase: print "DMW " + marker bytes, then "END"

Expected when everything is reachable:

    0 1 2 3 4 5 DMW 4=A 16=B 64=C 256=D 1024=E 2048=F END

The highest rung number that appears is the reach of the low window; the DMW
half proves the alternative (PMON's) execution path works on this board.
"""

import struct

R_ZERO, R_RA, R_A0, R_A1, R_A3, R_A4 = 0, 1, 4, 5, 7, 8
R_T0, R_T1 = 12, 13


def lu12i_w(rd, imm20):
    return (0x0A << 25) | ((imm20 & 0xFFFFF) << 5) | rd


def lu32i_d(rd, imm20):
    return (0x0B << 25) | ((imm20 & 0xFFFFF) << 5) | rd


def lu52i_d(rd, rj, imm12):
    return (0x0C << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def ori(rd, rj, imm12):
    return (0x0E << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def andi(rd, rj, imm12):
    return (0x0D0 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def addi_d(rd, rj, imm12):
    return (0x0B << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def st_b(rd, rj, imm12):
    return (0x0A4 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def st_w(rd, rj, imm12):
    return (0x0A6 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def ld_bu(rd, rj, imm12):
    return (0x0A8 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def ld_w(rd, rj, imm12):
    return (0x0A2 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def move(rd, rj):
    return (0x2A << 15) | (rj << 5) | rd


def _branch(op, off):
    v = (off >> 2) & 0x3FFFFFF
    return (op << 26) | ((v & 0xFFFF) << 10) | ((v >> 16) & 0x3FF)


def b(off):
    return _branch(0x14, off)


def bl(off):
    return _branch(0x15, off)


def beqz(rj, off):
    v = (off >> 2) & 0x3FFFFFF
    return (0x10 << 26) | ((v & 0xFFFF) << 10) | (rj << 5) | ((v >> 16) & 0x1F)


def jirl(rd, rj, off16):
    return (0x13 << 26) | ((off16 & 0xFFFF) << 10) | (rj << 5) | rd


def csrwr(rd, csr):
    return (0x04 << 24) | ((csr & 0x3FFF) << 10) | (0x01 << 5) | rd


def ret():
    return jirl(R_ZERO, R_RA, 0)


NOP = 0x03400000

PROLOGUE = 0x0040          # runs from the low window, like our SEC
RUNG0 = 0x0100             # prologue's own print + jump
RUNGS = [0x010000, 0x040000, 0x100000, 0x200000, 0x300000]
DMW_PHASE = 0x040000       # placed below the rung-2 slot? no: see layout check
DMW_PHASE = 0x0C0000       # free area between rungs
HELPERS = 0x0300
STRINGS = 0x0380
UNCACHED = 0x800
# markers must not collide with the rung code or the DMW phase
MARKERS = [(0x002000, 'A'), (0x008000, 'B'), (0x020000, 'C'),
           (0x080000, 'D'), (0x180000, 'E'), (0x280000, 'F')]
IMAGE = 0x400000


class Probe:
    def __init__(self):
        self.buf = bytearray(IMAGE)
        for i in range(IMAGE):
            self.buf[i] = 0xFF

    def word(self, off, w):
        struct.pack_into('<I', self.buf, off, w)

    def string(self, off, text):
        raw = text.encode('ascii') + b'\x00'
        self.buf[off:off + len(raw)] = raw
        return off + len(raw)


def addr_seq(off, window=0):
    """Materialise `window<<52 | off` in $a3."""
    return [lu12i_w(R_A3, (off >> 12) & 0xFFFFF),
            ori(R_A3, R_A3, off & 0xFFF),
            lu52i_d(R_A3, R_A3, window)]


def jump_seq(p, off, window, at):
    """Absolute jump to `window<<52 | off`, emitted at address `at`."""
    p.word(at + 0, lu12i_w(R_T0, (off >> 12) & 0xFFFFF))
    p.word(at + 4, ori(R_T0, R_T0, off & 0xFFF))
    p.word(at + 8, lu52i_d(R_T0, R_T0, window))
    p.word(at + 12, jirl(R_ZERO, R_T0, 0))
    return at + 16


def build():
    p = Probe()
    strs = {}
    so = STRINGS
    for text in ('0 ', '1 ', '2 ', '3 ', '4 ', '5 ', '\r\nDMW ', ' ', '\r\nEND\r\n'):
        so = p.string(so, text)
        strs[text] = so - len(text) - 1
    for mk, _ in MARKERS:
        lab = '%d=' % (mk >> 10)
        so = p.string(so, lab)
        strs[lab] = so - len(lab) - 1
    assert so < RUNGS[0], "string table ran into rung 1"

    # ---- helpers (low window, reachable by `bl` from every rung) ------------
    puts = HELPERS
    p.word(puts + 0, ld_bu(R_A1, R_A3, 0))
    p.word(puts + 4, beqz(R_A1, puts + 20 - (puts + 4)))
    p.word(puts + 8, bl(0))                       # patched to putc
    p.word(puts + 12, addi_d(R_A3, R_A3, 1))
    p.word(puts + 16, b(puts - (puts + 16)))
    p.word(puts + 20, ret())
    putc = puts + 24
    p.word(putc + 0, ld_bu(R_A4, R_A0, 5))
    p.word(putc + 4, andi(R_A4, R_A4, 0x20))
    p.word(putc + 8, beqz(R_A4, putc - (putc + 8)))
    p.word(putc + 12, st_b(R_A1, R_A0, 0))
    p.word(putc + 16, ret())
    p.word(puts + 8, bl(putc - (puts + 8)))
    assert putc + 20 <= STRINGS, "helpers overlap the string table"

    # ---- prologue: PMON's sequences, executed from the low window -----------
    o = PROLOGUE
    for w in (ori(R_T0, R_ZERO, 0x0F), lu52i_d(R_T0, R_T0, UNCACHED), csrwr(R_T0, 0x180),
              ori(R_T0, R_ZERO, 0x1F), lu52i_d(R_T0, R_T0, 0x900), csrwr(R_T0, 0x181),
              lu12i_w(R_T0, 0x1FFF0), ori(R_T0, R_T0, 0x220), lu52i_d(R_T0, R_T0, UNCACHED),
              ori(R_T1, R_ZERO, 0xFF), st_b(R_T1, R_T0, 5),
              ori(R_T1, R_ZERO, 0x27), st_b(R_T1, R_T0, 4),
              lu12i_w(R_T0, 0x1), lu32i_d(R_T0, 0x0FE), lu52i_d(R_T0, R_T0, UNCACHED),
              lu12i_w(R_A0, 0x1FE20), lu52i_d(R_A0, R_A0, UNCACHED),
              st_w(R_A0, R_T0, 0x10), ld_w(R_T1, R_T0, 0x04), ori(R_T1, R_T1, 0x2),
              st_w(R_T1, R_T0, 0x04),
              ori(R_A1, R_ZERO, 0x80), st_b(R_A1, R_A0, 3),
              move(R_A1, R_ZERO), st_b(R_A1, R_A0, 1),
              ori(R_A1, R_ZERO, 0x36), st_b(R_A1, R_A0, 0),
              ori(R_A1, R_ZERO, 0x03), st_b(R_A1, R_A0, 3),
              ori(R_A1, R_ZERO, 0x47), st_b(R_A1, R_A0, 2)):
        p.word(o, w)
        o += 4
    assert o <= RUNG0, "prologue ends 0x%x past rung0 0x%x" % (o, RUNG0)

    def emit_print(text, window, at):
        for w in addr_seq(strs[text], window):
            p.word(at, w)
            at += 4
        p.word(at, bl(puts - at))
        return at + 4

    # ---- rung 0: in the first 4 KB, jumps to rung 1 through the low window --
    at = RUNG0
    at = emit_print('0 ', 0, at)
    at = jump_seq(p, RUNGS[0], 0, at)
    assert at <= RUNGS[0], "rung0 overran"

    # ---- rungs 1..N, each living further out in the NOR ---------------------
    for i, rung in enumerate(RUNGS):
        at = rung
        at = emit_print('%d ' % (i + 1), 0, at)
        if i + 1 < len(RUNGS):
            at = jump_seq(p, RUNGS[i + 1], 0, at)
        else:
            at = jump_seq(p, DMW_PHASE, UNCACHED, at)   # into the DMW window
        assert at <= rung + 0x100, "rung %d overran" % (i + 1)

    # ---- DMW phase: markers read through the uncached window ---------------
    at = DMW_PHASE
    at = emit_print('\r\nDMW ', UNCACHED, at)
    for mk, _ in MARKERS:
        at = emit_print('%d=' % (mk >> 10), UNCACHED, at)
        for w in addr_seq(mk, UNCACHED):
            p.word(at, w)
            at += 4
        p.word(at, ld_bu(R_A1, R_A3, 0))
        at += 4
        p.word(at, bl(putc - at))
        at += 4
    at = emit_print(' ', UNCACHED, at)
    at = emit_print('\r\nEND\r\n', UNCACHED, at)
    p.word(at, b(at - at))
    at += 4
    assert at <= DMW_PHASE + 0x400, "DMW phase overran: 0x%x" % at

    # every marker must sit in untouched (0xFF) space
    for mk, ch in MARKERS:
        assert p.buf[mk] == 0xFF, "marker 0x%x collides with code" % mk
        p.buf[mk] = ord(ch)
    return p


def main():
    p = build()
    path = '/tmp/probe2.bin'
    open(path, 'wb').write(p.buf)
    print("probe: %s (%d bytes)" % (path, len(p.buf)))
    try:
        from capstone import Cs, CS_ARCH_LOONGARCH, CS_MODE_LOONGARCH64
    except ImportError:
        return 1
    md = Cs(CS_ARCH_LOONGARCH, CS_MODE_LOONGARCH64)
    for name, start in (('prologue', PROLOGUE), ('rung0', RUNG0),
                        ('rung1 @0x10000', RUNGS[0]), ('rung5 @0x30000', RUNGS[-1])):
        print("\n=== %s (0x%x) ===" % (name, start))
        n = 0
        for insn in md.disasm(bytes(p.buf[start:start + 0x40]), start):
            print("  %06x: %-11s %s" % (insn.address, insn.mnemonic, insn.op_str))
            n += 1
            if n >= 12:
                break
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
