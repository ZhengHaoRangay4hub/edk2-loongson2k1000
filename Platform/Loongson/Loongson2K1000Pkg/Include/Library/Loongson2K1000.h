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
#define LS2K_UART0_BASE         0x1fe20000  /* 16550, RS232 debug port (board pins 59/60) */
#define LS2K_UART3_BASE         0x1fe20300  /* 16550, LVTTL (board pins 8=TX 10=RX 9=GND) */
#define LS2K_UART4_BASE         0x1fe20400  /* 16550, LVTTL (board pins 53/54) */
#define LS2K_UART5_BASE         0x1fe20500  /* 16550, LVTTL (board pins 55/56) */
#define LS2K_UART0_CLOCK        125000000   /* 125 MHz APB clock, all UARTs */

/*
 * Console fan-out.  The board brings out three LVTTL UARTs plus the RS232
 * debug port, and there is no reliable public description of which of them is
 * pin-muxed and clock-gated at reset, so the firmware writes every character
 * to all four: whichever pair of pins is wired up will show the log, and the
 * RS232 port keeps working through the existing adapter.
 *
 * The primary port is polled properly (its bytes must get out); the mirrors
 * are written with a bounded wait, because an ungated UART can return a status
 * register that never reports "ready" and a full poll there would hang the
 * firmware on the first character.
 */
#define LS2K_CONSOLE_BASE        LS2K_UART3_BASE   /* primary: LVTTL pins 8/10  */
#define LS2K_CONSOLE_MIRROR0_BASE LS2K_UART0_BASE  /* RS232  pins 59/60         */
#define LS2K_CONSOLE_MIRROR1_BASE LS2K_UART4_BASE  /* LVTTL  pins 53/54         */
#define LS2K_CONSOLE_MIRROR2_BASE LS2K_UART5_BASE  /* LVTTL  pins 55/56         */

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
