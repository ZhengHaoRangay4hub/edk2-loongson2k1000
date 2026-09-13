/** @file
  Loongson 2K1000LA SoC register map shared by platform drivers.

  Addresses match the mainline kernel device tree
  (arch/loongarch/boot/dts/loongson-2k1000.dtsi) and the PMON BSP.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef LOONGSON_2K1000_H_
#define LOONGSON_2K1000_H_

/*
 * LoongArch maps I/O space at 0x9000000000000000 (uncached) and
 * 0xA000000000000000 (strongly uncached) in 64-bit mode.
 */
#define LS_MMIO_UNCACHED(Base)  (0x9000000000000000ULL | (UINT64)(Base))

/* APB / low-speed peripherals on the 2K1000LA internal bus */
#define LS2K_UART0_BASE         0x1fe001e0  /* 16550, console */
#define LS2K_UART0_CLOCK        125000000   /* 125 MHz APB clock */

#define LS2K_SPI0_BASE          0x1fff0220  /* on-chip SPI master (SPI NOR) */

#define LS2K_PMC_BASE           0x1fe27000  /* power management (reset/shutdown) */

#define LS2K_RTC_BASE           0x1fe27400  /* TOY/RTC counters */

/* SPI NOR execute-in-place window (16 MB device visible below 256 MB) */
#define LS2K_SPI_NOR_XIP_BASE   0x1c000000

/* Loongson compressed ECAM (32-bit bus/dev/fn packed, 8 bytes per function) */
#define LS2K_PCI_CFG_BASE       0xFE00000000ULL

/* Memory-mapped register access helpers (LoongArch IOCSR-free MMIO) */
#define LS_READ32(Addr)         (*(volatile UINT32 *)(UINTN)(LS_MMIO_UNCACHED(Addr)))
#define LS_WRITE32(Addr, Val)   do { (*(volatile UINT32 *)(UINTN)(LS_MMIO_UNCACHED(Addr))) = (Val); } while (0)

#endif /* LOONGSON_2K1000_H_ */
