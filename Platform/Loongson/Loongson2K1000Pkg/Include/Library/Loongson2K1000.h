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
 * LoongArch maps I/O space through an uncached DMW window - 0x8000_0000_... on
 * this board, the window PMON, the field-proven beep stub and Linux all use - and
 * 0xA000000000000000 (strongly uncached) in 64-bit mode.
 */
#define LS_MMIO_UNCACHED(Base)  (0x8000000000000000ULL | (UINT64)(Base))

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
/*
 * Only UART0 and UART3 are live in the reset configuration.  The pin-mux field
 * is uart0_enable, in general configuration register 1 at 0x1fe00428 (manual
 * table 5-3, printed page 37), and it resets to 4'b0001 = "8 wire mode, uart0
 * only"; 0x1fe00420 is general configuration register 0 (table 5-2) and has no
 * UART field at all.  UartPinMuxInit() writes 0xF - the factory's running
 * state, "2 wire mode" with uart0 + uart3 + uart4 + uart5 - late in SEC, so
 * before that only UART0 is muxed out.  Poking 0x1fe20400/0x1fe20500 on this
 * board is pointless in the reset configuration and was observed to disturb
 * the boot.
 */
#define LS2K_CONSOLE_BASE        LS2K_UART0_BASE   /* RS232, pins 59/60 (PMON's port) */
#define LS2K_CONSOLE_MIRROR0_BASE LS2K_UART3_BASE  /* LVTTL, pins 8/10, GND 9         */
#define LS2K_CONSOLE_MIRROR1_BASE 0                /* UART4 needs a mux change: none  */
#define LS2K_CONSOLE_MIRROR2_BASE 0                /* UART5 needs a mux change: none  */

#define LS2K_SPI0_BASE          0x1fff0220  /* on-chip SPI master (SPI NOR) */

/*
 * Boot progress log: 60 KB carved out of the firmware volume's tail, just
 * below the variable store, so the firmware can record how far it got without
 * a serial console.  Read the chip with a programmer and decode with
 * tools/decode_bootlog.py.  FVMAIN_SIZE in Loongson2K1000Pkg.fdf.inc must stay
 * below this address (0x360000 in the full-feature build, 0xF0000 in BOARD_MIN).
 */
#define LS2K_BOOTLOG_BASE       0x360000
#define LS2K_BOOTLOG_SIZE       0xF000

/*
 * Progress marks (Library/LoongsonBootLogLib, LoongsonBootMark): one 4 KB sector
 * held out of the top of the log region so the log can never consume it.  Where
 * it sits is not arbitrary -- it is the only 4 KB of the 4 MB part that meets all
 * four constraints at once:
 *   - above the 1 MB reset window (0x1c000000-0x1c0fffff): never inside the window
 *     the XIP engine serves, never inside the part an image write to the boot
 *     window can touch;
 *   - outside FVMAIN_COMPACT, which ends at 0x360000 in the full-feature build
 *     (Loongson2K1000Pkg.fdf.inc:119-123) and at 0xF0000 under BOARD_MIN;
 *   - outside the variable store (0x370000-0x3B0000), the FTW working block
 *     (0x3B0000-0x3C0000) and the FTW spare block (0x3C0000-0x400000) -- which is
 *     where the marks used to live (Loongson2K1000Pkg.dsc:366-375);
 *   - erased (0xFF) as the board ships: measured all-0xFF over 0x36F000-0x36FFFF
 *     in the factory dump W25Q32_dump_20260915_115813.bin, in the post-boot read
 *     readback_after_boot_195016.bin and in the latest full-chip read
 *     readback_marks_20260919_211728.bin.
 * The slot layout inside the sector is fixed by LoongsonBootLog.h; every mark must
 * name one of LS2K_MARK_A1..A5, because LoongsonBootMark() refuses anything else.
 */
#define LS2K_MARK_BASE          0x36F000
#define LS2K_MARK_SIZE          0x1000

#define LS2K_MARK_A1            (LS2K_MARK_BASE + 0x00)  /* reset path ran     */
#define LS2K_MARK_A2            (LS2K_MARK_BASE + 0x01)  /* PreMemInit entered */
#define LS2K_MARK_A3            (LS2K_MARK_BASE + 0x02)  /* UART up            */
#define LS2K_MARK_A4            (LS2K_MARK_BASE + 0x03)  /* after clock/PLL    */
#define LS2K_MARK_A5            (LS2K_MARK_BASE + 0x04)  /* DDR up             */

/* Status-register snapshot, programmed in the same page program as the mark. */
#define LS2K_MARK_SR1           (LS2K_MARK_BASE + 0x08)
#define LS2K_MARK_SR2           (LS2K_MARK_BASE + 0x09)
#define LS2K_MARK_SR3           (LS2K_MARK_BASE + 0x0A)
#define LS2K_MARK_PAGE_LEN      0x0B

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
