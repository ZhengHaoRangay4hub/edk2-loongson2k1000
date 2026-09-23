#!/usr/bin/env python3
"""Patch a firmware image so the reset vector beeps before doing anything else.

Why: the board is silent with our firmware (no UART, no HDMI, no buzzer from the
SEC code) while the factory PMON boots.  Two very different causes look the
same: either the boot ROM never hands control to our image, or it does and the
first few instructions die.  This stub separates them.

It rewrites the reset vector at flash offset 0 (normally `b 0x2000`, the branch
EDK2 installs to reach the SEC entry) to jump to a stub placed in the free tail
of the firmware volume.  The stub:

  1. programs the PCIe APB BAR the way ApbBarConfig() does -- the GPIO block is
     behind that window, so nothing else would reach it;
  2. sets GPIO39 as an output (the pin the factory PMON beeps with);
  3. beeps three times;
  4. branches to 0x2000, i.e. continues the normal boot.

So: three beeps mean the boot ROM did execute our image and the reset vector
works; silence means it never got there and the problem is the image format or
the entry address, not the firmware logic.

The stub uses the same 0x8000_0000_... uncached aliases the factory PMON uses in
its first instructions, so it needs no assumptions beyond the ones PMON itself
makes.

Usage:  python3 make_entry_beep.py <in.fd> <out.bin> [--no-continue]
"""

import argparse
import struct
import sys

# --- LoongArch64 encoders (verified against real bytes + capstone) -----------
R_ZERO = 0
R_T0, R_T1, R_T2, R_T3, R_T4 = 12, 13, 14, 15, 16
R_T5, R_T6, R_T7, R_T8, R_T9 = 17, 18, 19, 20, 21


def lu12i_w(rd, imm20):
    return (0x0A << 25) | ((imm20 & 0xFFFFF) << 5) | rd


def lu32i_d(rd, imm20):
    return (0x0B << 25) | ((imm20 & 0xFFFFF) << 5) | rd


def lu52i_d(rd, rj, imm12):
    return (0x0C << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def ori(rd, rj, imm12):
    return (0x0E << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def move(rd, rj):
    return or_(rd, rj, R_ZERO)


def or_(rd, rj, rk):
    return (0x2A << 15) | (rk << 10) | (rj << 5) | rd


def and_(rd, rj, rk):
    return (0x29 << 15) | (rk << 10) | (rj << 5) | rd


def xor_(rd, rj, rk):
    return (0x2B << 15) | (rk << 10) | (rj << 5) | rd


def addi_w(rd, rj, imm12):
    return (0x0A << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def st_w(rd, rj, imm12):
    return (0x0A6 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def ld_w(rd, rj, imm12):
    return (0x0A2 << 22) | ((imm12 & 0xFFF) << 10) | (rj << 5) | rd


def csrwr(rd, csr):
    return (0x04 << 24) | ((csr & 0x3FFF) << 10) | (0x01 << 5) | rd


def slli_d(rd, rj, sa):
    return (0x11 << 15) | ((sa & 0x3F) << 10) | (rj << 5) | rd


def beq_(rj, rd, off):
    v = (off >> 2) & 0xFFFF
    return (0x16 << 26) | ((v & 0xFFFF) << 10) | (rj << 5) | rd


def b(off):
    v = (off >> 2) & 0x3FFFFFF
    return (0x14 << 26) | ((v & 0xFFFF) << 10) | ((v >> 16) & 0x3FF)


def bnez(rj, off):
    """bnez is opcode 0x11, laid out like beqz.

    NOT 0x17: that is `bne rj, rd, offs`, whose low field is a register number --
    emitting a 0x17 there silently compares against a garbage register and the
    loop falls apart (the reason the earlier stubs stayed silent).
    """
    v = (off >> 2) & 0x3FFFFFF
    return (0x11 << 26) | ((v & 0xFFFF) << 10) | (rj << 5) | ((v >> 16) & 0x1F)


def li64(rd, value):
    """Materialise a 64-bit constant.

    lu12i.w only loads bits [31:12], so the low 12 bits need an explicit ori --
    the same lu12i.w + ori + lu52i.d pattern the SEC assembly uses.  Missing
    that ori silently drops the low bits (e.g. a DMW loses its PLV/MAT field and
    an MMIO address loses its offset), which is exactly the bug that made the
    first two entry tests useless.
    """
    value &= 0xFFFFFFFFFFFFFFFF
    lo12 = (value >> 12) & 0xFFFFF
    mid = (value >> 32) & 0xFFFFF
    hi = (value >> 52) & 0xFFF
    low = value & 0xFFF
    out = [lu12i_w(rd, lo12)]
    if low:
        out.append(ori(rd, rd, low))
    out.append(lu32i_d(rd, mid))
    out.append(lu52i_d(rd, rd, hi))
    return out


class Stub:
    """Tiny assembler with label patching."""

    def __init__(self, base):
        self.base = base
        self.words = []
        self.labels = {}
        self.fixups = []

    def emit(self, words):
        for w in words:
            self.words.append(w)

    def label(self, name):
        self.labels[name] = self.base + len(self.words) * 4

    def branch(self, kind, name, reg=None):
        """Emit a branch whose target label is not known yet."""
        self.fixups.append((len(self.words), kind, name, reg))
        self.words.append(0)

    def resolve(self):
        for idx, kind, name, reg in self.fixups:
            here = self.base + idx * 4
            off = self.labels[name] - here
            if kind == "b":
                self.words[idx] = b(off)
            else:
                self.words[idx] = bnez(reg, off)

    def bytes(self):
        self.resolve()
        return b"".join(struct.pack("<I", w) for w in self.words)


def build_stub(base, continue_to, beeps=3, setup_cpu=False):
    s = Stub(base)

    if setup_cpu:
        # Same direct-mapping windows and CRMD the SEC entry installs, so the
        # stub does not depend on whatever mode the boot ROM left behind.
        s.emit(li64(R_T0, 0x800000000000000F))          # DMW0: MMIO, uncached
        s.emit([csrwr(R_T0, 0x180)])
        s.emit(li64(R_T0, 0x800000000000001F))          # DMW1: cached
        s.emit([csrwr(R_T0, 0x181)])
        s.emit([ori(R_T0, R_ZERO, 0xA8)])               # DATF/DATM cached, DA=1
        s.emit([csrwr(R_T0, 0x0)])

    # --- APB BAR: route the APB space behind the PCIe root complex ----------
    s.emit(li64(R_T0, 0x800000FE00001000))   # uncached alias of the BAR reg
    s.emit(li64(R_T1, 0x800000001FE20000))     # APB window base
    s.emit([st_w(R_T1, R_T0, 0x10)])
    s.emit([ld_w(R_T2, R_T0, 0x04), ori(R_T2, R_T2, 2), st_w(R_T2, R_T0, 0x04)])

    # --- GPIO39 as an output ------------------------------------------------
    s.emit(li64(R_T3, 0x800000001FE00504))     # direction register, pins 32-63
    s.emit([ld_w(R_T4, R_T3, 0)])
    # t5 = ~0x80
    s.emit([lu12i_w(R_T5, 0xFFFFF), ori(R_T5, R_T5, 0xF7F), and_(R_T4, R_T4, R_T5)])
    s.emit([st_w(R_T4, R_T3, 0)])

    # --- beep on GPIO39 data register --------------------------------------
    s.emit(li64(R_T3, 0x800000001FE00514))     # data register, pins 32-63
    s.emit([ori(R_T2, R_ZERO, 0x80)])          # the buzzer bit (PMON keeps it in t2)
    s.emit([ori(R_T6, R_ZERO, beeps)])         # beep counter

    #
    # Square wave the way the factory PMON does it: force the bit low with
    # (x | b) ^ b and force it high with (x | b), never depending on the value
    # read back from the register -- reading the GPIO data register does not
    # give back what was written, and a read-modify-write toggle therefore
    # produces a single click instead of a tone.
    #
    #
    # Four bursts with geometrically spaced delays (0x40, 0x100, 0x400, 0x1000),
    # then repeat.  The stub runs in whatever address window the boot ROM handed
    # over in, and that window is not cached, so instruction fetch is a slow SPI
    # read and the loop delay maps to a far lower tone than the cycle count
    # suggests.  One power-up then shows which delay actually makes an audible
    # tone, which pins down the effective fetch cost.
    #
    s.emit([ori(R_T6, R_ZERO, 0x40)])

    s.label("burst")
    s.emit([ori(R_T7, R_ZERO, 0x80)])          # half periods per burst

    s.label("tone")
    # clear bit 7: (x | b) ^ b -- never trust what the register reads back
    s.emit([ld_w(R_T4, R_T3, 0)])
    s.emit([or_(R_T5, R_T4, R_T2)])
    s.emit([xor_(R_T5, R_T5, R_T2)])
    s.emit([st_w(R_T5, R_T3, 0)])
    s.emit([move(R_T8, R_T6)])
    s.label("dly1")
    s.emit([addi_w(R_T8, R_T8, -1)])
    s.branch("bnez", "dly1", R_T8)
    # set bit 7
    s.emit([ld_w(R_T4, R_T3, 0)])
    s.emit([or_(R_T4, R_T4, R_T2)])
    s.emit([st_w(R_T4, R_T3, 0)])
    s.emit([move(R_T8, R_T6)])
    s.label("dly2")
    s.emit([addi_w(R_T8, R_T8, -1)])
    s.branch("bnez", "dly2", R_T8)
    s.emit([addi_w(R_T7, R_T7, -1)])
    s.branch("bnez", "tone", R_T7)

    # gap, then quadruple the delay; after 0x1000 start over at 0x40
    s.emit([lu12i_w(R_T8, 0x04)])
    s.label("gap")
    s.emit([addi_w(R_T8, R_T8, -1)])
    s.branch("bnez", "gap", R_T8)
    s.emit([slli_d(R_T6, R_T6, 2)])
    s.emit([lu12i_w(R_T5, 0x1)])
    s.emit([beq_(R_T6, R_T5, "restart")])
    s.branch("b", "burst")
    s.label("restart")
    s.emit([ori(R_T6, R_ZERO, 0x40)])
    s.branch("b", "burst")

    # --- hand over to the real firmware ------------------------------------
    if continue_to is not None:
        here = s.base + len(s.words) * 4
        s.emit([b(continue_to - here)])
    else:
        # Keep beeping: an operator who is not staring at the board at power-on
        # should still catch it.
        s.branch("b", "beep")

    return s.bytes()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", help="input firmware (.fd, the firmware volume)")
    ap.add_argument("out", help="output image (4 MB flash image)")
    ap.add_argument("--no-continue", action="store_true",
                    help="beep forever instead of continuing into the firmware")
    ap.add_argument("--no-cpu-setup", action="store_true",
                    help="skip the DMW/CRMD setup (keep whatever the ROM left)")
    ap.add_argument("--stub-offset", type=lambda v: int(v, 0), default=0x1F0000,
                    help="where to place the stub (default 0x1F0000, free tail of the FV)")
    ap.add_argument("--image-size", type=lambda v: int(v, 0), default=0x400000)
    ap.add_argument("--fv-size", type=lambda v: int(v, 0), default=0x360000)
    args = ap.parse_args()

    fv = bytearray(open(args.image, "rb").read())
    if len(fv) != args.fv_size:
        print("note: firmware is %d bytes, expected %d" % (len(fv), args.fv_size))

    stub = build_stub(args.stub_offset,
                      0x2000 if not args.no_continue else None,
                      setup_cpu=not args.no_cpu_setup)
    print("stub: %d bytes at 0x%x" % (len(stub), args.stub_offset))

    if any(b != 0xFF for b in fv[args.stub_offset:args.stub_offset + len(stub)]):
        print("warning: stub area is not erased -- overwriting whatever is there")

    fv[args.stub_offset:args.stub_offset + len(stub)] = stub

    # reset vector: branch from 0 to the stub
    vec = b(args.stub_offset - 0)
    struct.pack_into("<I", fv, 0, vec)
    print("reset vector at 0x0 -> 0x%x (%s)" % (args.stub_offset,
          "beep then continue at 0x2000" if not args.no_continue else "beep forever"))

    img = bytes(fv) + b"\xff" * (args.image_size - len(fv))
    open(args.out, "wb").write(img)
    print("wrote %s (%d bytes)" % (args.out, len(img)))

    # verify with capstone when available
    try:
        from capstone import Cs, CS_ARCH_LOONGARCH, CS_MODE_LOONGARCH64
    except ImportError:
        return 0
    md = Cs(CS_ARCH_LOONGARCH, CS_MODE_LOONGARCH64)
    print("\n=== stub disassembly ===")
    for insn in md.disasm(stub, args.stub_offset):
        print("  %06x: %-11s %s" % (insn.address, insn.mnemonic, insn.op_str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
