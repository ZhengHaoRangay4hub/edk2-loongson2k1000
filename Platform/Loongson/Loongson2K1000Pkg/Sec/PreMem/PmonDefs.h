/** @file
  PMON assembly compatibility shim for Loongson 2K1000LA.

  The DDR / clock assembly ported from Loongson's PMON (BSD licensed,
  github.com/loongson-community/pmon-ls2k1000la, branch loongson-22.09)
  expects PMON's header environment. This header provides the same macros
  under the standard LoongArch EDK2 direct-mapping-window convention:

    DMW0 = 0x9000000000000000 : PLV0..3, MAT=0 (strongly-ordered uncached)
    DMW1 = 0x8000000000000000 : PLV0..3, MAT=1 (coherent cached)

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __PMON_DEFS_H__
#define __PMON_DEFS_H__

#define UNCACHED_MEMORY_ADDR  0x9000000000000000
#define CACHED_MEMORY_ADDR    0x8000000000000000

#define PHYS_TO_UNCACHED(x)  (UNCACHED_MEMORY_ADDR | (x))
#define PHYS_TO_CACHED(x)    (CACHED_MEMORY_ADDR | (x))

/* Console UART0 of the Loongson education board (LS2K1000LA). */
#define LS2K1000_UART0_PHYS  0x1fe20000
#define COM1_BASE_ADDR       PHYS_TO_UNCACHED(LS2K1000_UART0_PHYS)
#define COM2_BASE_ADDR       COM1_BASE_ADDR
#define COM3_BASE_ADDR       COM1_BASE_ADDR

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
#define msize  s2

#endif /* __PMON_DEFS_H__ */
