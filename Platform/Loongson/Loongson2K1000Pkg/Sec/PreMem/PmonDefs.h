/** @file
  PMON assembly compatibility shim for Loongson 2K1000LA.

  The DDR / clock assembly ported from Loongson's PMON (BSD licensed,
  github.com/loongson-community/pmon-ls2k1000la, branch loongson-22.09)
  expects PMON's header environment. This header provides the same macros
  under the standard LoongArch EDK2 direct-mapping-window convention:

    DMW0 = 0x8000000000000000 : PLV0..3, MAT=0 (strongly-ordered uncached)
    DMW1 = 0x9000000000000000 : PLV0..3, MAT=1 (coherent cached)

  CACHED_MEMORY_ADDR is the uncached address on purpose, so PHYS_TO_CACHED()
  and PHYS_TO_UNCACHED() are the same value here: every MMIO access in this
  tree goes through the uncached window, and PMON's "cached alias" only ever
  mattered for the locked-cache region, which is addressed with hard-coded
  0x9000... literals (Sec/LoongArch64/Start.S, Sec/PreMem/DdrEntry.S) and is
  not affected by this header.  Do not "fix" this back to 0x9000000000000000:
  that would turn every access through this macro into a cached one, which is
  how this port went silent on hardware.  The two consumers that still call it
  are dead code today - ddr_dir/Test_Mem.h:63 (MEM_TEST_BASE, needs DEBUG_DDR)
  and ddr_dir/store_auto_arb_level_info.S:3 (DIMM_INFO_ADDR, needs ARB_LEVEL) -
  and both must be revisited before anything else starts using it.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __PMON_DEFS_H__
#define __PMON_DEFS_H__

/* Both are the 0x8000 uncached window; see the note above. */
#define UNCACHED_MEMORY_ADDR  0x8000000000000000
#define CACHED_MEMORY_ADDR    0x8000000000000000

#define PHYS_TO_UNCACHED(x)  (UNCACHED_MEMORY_ADDR | (x))
#define PHYS_TO_CACHED(x)    (CACHED_MEMORY_ADDR | (x))

/*
 * Console UART of the Loongson education board (LS2K1000LA).
 *
 * Primary is the LVTTL port (board pins 8/10, GND on 9) so a 3.3V USB-TTL
 * adapter can read the firmware directly; every character is mirrored to the
 * RS232 debug port on UART0 so existing wiring keeps working.  Keep the
 * COM1_BASE_ADDR name: the PMON derived assembly helpers all use it.
 */
#define LS2K1000_UART0_PHYS   0x1fe20000   /* RS232 debug port, pins 59/60 */
#define LS2K1000_UART3_PHYS   0x1fe20300   /* LVTTL, pins 8=TX 10=RX 9=GND */
#define LS2K1000_UART4_PHYS   0x1fe20400   /* LVTTL, pins 53/54 */
#define LS2K1000_UART5_PHYS   0x1fe20500   /* LVTTL, pins 55/56 */
#define LS2K1000_CONSOLE_PHYS LS2K1000_UART0_PHYS
#define COM1_BASE_ADDR        PHYS_TO_UNCACHED(LS2K1000_CONSOLE_PHYS)
/* Mirror to the LVTTL port; UART4/UART5 are not muxed in on this board. */
#define COM1_MIRROR0_ADDR     PHYS_TO_UNCACHED(LS2K1000_UART3_PHYS)
#define COM2_BASE_ADDR        COM1_BASE_ADDR
#define COM3_BASE_ADDR        COM1_BASE_ADDR

/* I2C0 controller (used by the DDR power / SPD helpers). */
#define LS2K1000_I2C0_REG_BASE    PHYS_TO_UNCACHED(0x1fe21000)
#define LS2K1000_I2C0_PRER_LO_REG (LS2K1000_I2C0_REG_BASE + 0x0)
#define LS2K1000_I2C0_PRER_HI_REG (LS2K1000_I2C0_REG_BASE + 0x1)
#define LS2K1000_I2C0_CTR_REG     (LS2K1000_I2C0_REG_BASE + 0x2)
#define LS2K1000_I2C0_TXR_REG     (LS2K1000_I2C0_REG_BASE + 0x3)
#define LS2K1000_I2C0_RXR_REG     (LS2K1000_I2C0_REG_BASE + 0x3)
#define LS2K1000_I2C0_CR_REG      (LS2K1000_I2C0_REG_BASE + 0x4)
#define LS2K1000_I2C0_SR_REG      (LS2K1000_I2C0_REG_BASE + 0x4)

#define CR_START  0x80
#define CR_STOP   0x40
#define CR_READ   0x20
#define CR_WRITE  0x10
#define CR_ACK    0x8
#define CR_IACK   0x1

#define SR_NOACK  0x80
#define SR_BUSY   0x40
#define SR_AL     0x20
#define SR_TIP    0x2
#define SR_IF     0x1

/* msize lives in $s2 across the DDR init assembly (PMON convention). */
#define msize  $s2

#endif /* __PMON_DEFS_H__ */

/*
 * PMON assembly function entry/exit macros. The PMON sources rely on
 * LEAF()/END() emitting a global label; gas has no such builtin, so the
 * cpp must expand them explicitly.
 */
#define LEAF(x)  .globl x ; x:
#define END(x)

/* 16550 register offsets used by the PMON memdebug routines (byte stride). */
#define NSREG(x)          (x)
#define NS16550_DATA      0x0
#define NS16550_IER       0x1
#define NS16550_LSR       0x5
#define LSR_TXRDY         0x20
#define LSR_RXRDY         0x01

/* DDR PHY clock in MHz (matches ClkSetting.S default; education board = 400). */
#ifndef DDR_FREQ
#define DDR_FREQ 400
#endif

/*
 * The PMON ls2k build defines DDR3_DIMM: the soldered-down DDR3 on the
 * 2K1000LA boards still runs the write-leveling paths guarded by it.
 */
#define DDR3_DIMM 1
