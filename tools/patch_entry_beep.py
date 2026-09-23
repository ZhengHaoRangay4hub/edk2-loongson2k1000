#!/usr/bin/env python3
"""Patch a firmware image to beep from its reset vector.

The stub itself is assembled by the real toolchain (tools/stub_beep.S) -- hand
rolled encoders produced two silent bugs, so the instruction bytes now come from
gas and this script only places them.

    python3 patch_entry_beep.py <image.fd> <out.bin> <stub.bin> [stub-offset]

The reset vector at offset 0 is rewritten to branch to the stub; the stub must
fit between stub-offset and the next used byte (0xF00 sits in the zero gap the
factory PMON image has there).
"""
import struct
import sys

RESET_VECTOR_B_OPCODE = 0x14


def b(off):
    v = (off >> 2) & 0x3FFFFFF
    return (RESET_VECTOR_B_OPCODE << 26) | ((v & 0xFFFF) << 10) | ((v >> 16) & 0x3FF)


def main():
    img_path, out_path, stub_path = sys.argv[1], sys.argv[2], sys.argv[3]
    stub_off = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0xF00
    image_size = 0x400000

    data = bytearray(open(img_path, "rb").read())
    stub = open(stub_path, "rb").read()

    if len(data) < image_size:
        data += b"\xff" * (image_size - len(data))
    if len(stub) > 0x100 or stub_off + len(stub) > 0xFE8:
        sys.exit("stub too large for the gap")

    data[stub_off:stub_off + len(stub)] = stub
    struct.pack_into("<I", data, 0, b(stub_off))
    open(out_path, "wb").write(data)
    print("stub %d bytes -> 0x%x, reset vector -> 0x%x" % (len(stub), stub_off, stub_off))


if __name__ == "__main__":
    main()
