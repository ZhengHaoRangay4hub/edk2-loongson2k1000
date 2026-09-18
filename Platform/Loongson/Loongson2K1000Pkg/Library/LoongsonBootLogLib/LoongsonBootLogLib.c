/** @file
  Boot progress log on the SPI NOR flash.  See Include/Library/LoongsonBootLog.h
  for the region layout and the event codes.

  Design notes
  ------------
  * Write-only.  The firmware never reads the log back: the XIP window only
    mirrors the first 1 MB of the chip (above that the boot strap maps the
    local-bus flash, which this board does not populate), and the SPI
    controller's read path cannot be relied on this early either.  Every event
    therefore has its own fixed 4-byte slot, keyed by its event code, and the
    log is written by programming those slots directly.

  * No erase.  A 4 KB sector erase keeps the flash busy for tens of milliseconds
    while the CPU is still executing from that same chip, so the firmware never
    erases: slots are programmed once (a second boot writes the same bytes into
    the same slots, which is a no-op for NOR) and the log therefore accumulates
    the furthest progress reached since the region was last erased -- which is
    exactly what a flash write of a new image gives you.  Erase the region with
    a programmer if you want a clean slate.

  * No writable globals.  SEC executes in place from the SPI NOR window, so its
    .data/.bss bytes live in flash and stores to them are discarded; the library
    keeps no state at all.

  * Failure is silent and cheap.  All SPI waits are bounded and every error just
    stops the current entry; a missing or wedged flash must never keep the board
    from booting.

  * Writes also mirror into the XIP window.  On silicon those stores land in the
    unpopulated local-bus window and are dropped, but QEMU maps that window as
    RAM, so the mirror is what makes the log readable in the emulator.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/IoLib.h>
#include <Library/Loongson2K1000.h>
#include <Library/LoongsonBootLog.h>

/* Uncached alias of a physical address (DMW0 in Start.S). */
#define UNCACHED(x)  ((UINTN)(0x9000000000000000ULL | (UINT64)(x)))

#define SPI_REG_BASE  UNCACHED (LS2K_SPI0_BASE)

/* SPI controller registers (same layout the NOR device library uses). */
#define SPI_SPCR    0x0
#define SPI_SPSR    0x1
#define SPI_FIFO    0x2
#define SPI_SPER    0x3
#define SPI_PARAM   0x4
#define SPI_SOFTCS  0x5
#define SPI_PARAM2  0x6
#define SPI_RFEMPTY 0x1

/* NOR flash opcodes. */
#define NOR_WREN     0x06
#define NOR_RDSR     0x05
#define NOR_PROGRAM  0x02

#define SPI_CS_ASSERT   0x01
#define SPI_CS_RELEASE  0x11

/* Log geometry: one header record followed by a 4-byte slot per event code. */
#define LOG_BASE         LS2K_BOOTLOG_BASE
#define LOG_HDR_SIZE     16
#define LOG_SLOT_SIZE    4
#define LOG_MAGIC_0      'B'
#define LOG_MAGIC_1      'L'
#define LOG_MAGIC_2      'O'
#define LOG_MAGIC_3      'G'
#define LOG_VERSION      1
/* Marks a slot whose value is valid; neither 0xFF (erased) nor 0x00 (QEMU's
   filler), so a slot is unambiguous in both environments. */
#define LOG_VALUE_MARK   0x5A
/* Bounded waits: a flash that never answers costs milliseconds, not seconds. */
#define SPI_POLL_LIMIT  20000

/* The window the firmware fetches from -- also the mirror target, see above. */
#define FLASH_XIP  UNCACHED (LS2K_SPI_NOR_XIP_BASE)

/* ------------------------------------------------------------------ */
/* SPI NOR programming primitives                                      */
/* ------------------------------------------------------------------ */

STATIC
VOID
SpiSend (
  IN UINT8  Value
  )
{
  UINT32  Timeout = SPI_POLL_LIMIT;

  MmioWrite8 (SPI_REG_BASE + SPI_FIFO, Value);
  while (((MmioRead8 (SPI_REG_BASE + SPI_SPSR)) & SPI_RFEMPTY) != 0) {
    if (Timeout-- == 0) {
      break;
    }
  }

  (VOID)MmioRead8 (SPI_REG_BASE + SPI_FIFO);
}

STATIC
UINT8
SpiRecv (
  VOID
  )
{
  UINT32  Timeout = SPI_POLL_LIMIT;

  MmioWrite8 (SPI_REG_BASE + SPI_FIFO, 0x00);
  while (((MmioRead8 (SPI_REG_BASE + SPI_SPSR)) & SPI_RFEMPTY) != 0) {
    if (Timeout-- == 0) {
      break;
    }
  }

  return MmioRead8 (SPI_REG_BASE + SPI_FIFO);
}

STATIC
VOID
SpiCs (
  IN UINT8  State
  )
{
  MmioWrite8 (SPI_REG_BASE + SPI_SOFTCS, State);
}

STATIC
VOID
SpiInit (
  VOID
  )
{
  MmioWrite8 (SPI_REG_BASE + SPI_SPSR, 0xc0);
  MmioWrite8 (SPI_REG_BASE + SPI_PARAM, 0x10);
  MmioWrite8 (SPI_REG_BASE + SPI_PARAM2, 0x01);
  MmioWrite8 (SPI_REG_BASE + SPI_SPER, 0x04);
  MmioWrite8 (SPI_REG_BASE + SPI_SPCR, 0x51);
}

/**
  Wait for the flash to finish the previous operation.

  @retval TRUE   The flash is idle (or not answering, in which case nothing
                 more can be done anyway and the write is attempted).
**/
STATIC
BOOLEAN
SpiWaitReady (
  VOID
  )
{
  UINT32  Timeout = SPI_POLL_LIMIT;

  while (Timeout-- != 0) {
    UINT8  Status;

    SpiCs (SPI_CS_ASSERT);
    SpiSend (NOR_RDSR);
    Status = SpiRecv ();
    SpiCs (SPI_CS_RELEASE);

    if ((Status & 0x01) == 0) {
      return TRUE;
    }
  }

  return FALSE;
}

STATIC
BOOLEAN
SpiWriteEnable (
  VOID
  )
{
  SpiCs (SPI_CS_ASSERT);
  SpiSend (NOR_WREN);
  SpiCs (SPI_CS_RELEASE);

  SpiWaitReady ();
  return TRUE;
}

/**
  Program one byte, and mirror it into the XIP window.

  @retval TRUE   The flash accepted the byte.
  @retval FALSE  Programming timed out; the caller drops the entry.
**/
STATIC
BOOLEAN
LogWrite (
  IN UINTN        Offset,
  IN CONST UINT8  *Data,
  IN UINTN        Length
  )
{
  UINTN  Index;

  for (Index = 0; Index < Length; Index++) {
    SpiWriteEnable ();

    SpiCs (SPI_CS_ASSERT);
    SpiSend (NOR_PROGRAM);
    SpiSend ((UINT8)((Offset + Index) >> 16));
    SpiSend ((UINT8)((Offset + Index) >> 8));
    SpiSend ((UINT8)(Offset + Index));
    SpiSend (Data[Index]);
    SpiCs (SPI_CS_RELEASE);

    if (!SpiWaitReady ()) {
      return FALSE;
    }

    /*
     * QEMU models the boot window as RAM and treats the controller commands
     * as no-ops, so this is what makes the log observable in the emulator.
     * On silicon the same address lands in the local-bus window, which is not
     * populated on this board, and the store is simply dropped.
     */
    *(volatile UINT8 *)(FLASH_XIP + Offset + Index) = Data[Index];
  }

  return TRUE;
}

/* ------------------------------------------------------------------ */
/* Audible progress (buzzer on GPIO39)                                 */
/* ------------------------------------------------------------------ */

/*
 * The factory PMON drives the buzzer the same way: GPIO39 is bit 7 of the
 * upper GPIO word, its direction bit lives at 0x1fe00504 and its output data
 * at 0x1fe00514.  Toggling the data bit in a software delay loop makes the
 * tone, so the pitch depends on the loop -- the numbers below land around
 * 1.5 kHz with a ~20 ms beep, which is clearly audible.
 */
#define GPIO_DIR_HI   UNCACHED (0x1fe00504)
#define GPIO_DATA_HI  UNCACHED (0x1fe00514)
#define BEEP_BIT      0x80u

#define BEEP_HALF_PERIOD  0x10000
#define BEEP_HALF_CYCLES  0x40
#define BEEP_GAP_LOOPS    400

STATIC
VOID
BeepDelay (
  IN UINTN  Loops
  )
{
  volatile UINTN  Index;

  for (Index = 0; Index < Loops; Index++) {
  }
}

STATIC
VOID
BeepTone (
  VOID
  )
{
  UINTN  Half;

  for (Half = 0; Half < BEEP_HALF_CYCLES; Half++) {
    MmioWrite32 (GPIO_DATA_HI, MmioRead32 (GPIO_DATA_HI) ^ BEEP_BIT);
    BeepDelay (BEEP_HALF_PERIOD);
  }
}

STATIC
VOID
BeepOff (
  VOID
  )
{
  MmioWrite32 (GPIO_DATA_HI, MmioRead32 (GPIO_DATA_HI) & ~BEEP_BIT);
}

VOID
EFIAPI
LoongsonBootBeep (
  IN UINTN  Count
  )
{
  UINTN  Index;

  /* GPIO39 as an output; the factory PMON clears the same bit. */
  MmioWrite32 (GPIO_DIR_HI, MmioRead32 (GPIO_DIR_HI) & ~BEEP_BIT);
  BeepOff ();

  for (Index = 0; Index < Count; Index++) {
    BeepTone ();
    BeepOff ();
    BeepDelay (BEEP_GAP_LOOPS * BEEP_HALF_PERIOD);
  }
}

VOID
EFIAPI
LoongsonBootBeepLong (
  VOID
  )
{
  UINTN  Half;

  MmioWrite32 (GPIO_DIR_HI, MmioRead32 (GPIO_DIR_HI) & ~BEEP_BIT);

  for (Half = 0; Half < BEEP_HALF_CYCLES * 12; Half++) {
    MmioWrite32 (GPIO_DATA_HI, MmioRead32 (GPIO_DATA_HI) ^ BEEP_BIT);
    BeepDelay (BEEP_HALF_PERIOD);
  }

  BeepOff ();
}

/* ------------------------------------------------------------------ */
/* Log API                                                             */
/* ------------------------------------------------------------------ */

VOID
EFIAPI
LoongsonBootLogBoot (
  VOID
  )
{
  UINT8  Header[LOG_HDR_SIZE];
  UINTN  Index;

  SpiInit ();

  Header[0] = LOG_MAGIC_0;
  Header[1] = LOG_MAGIC_1;
  Header[2] = LOG_MAGIC_2;
  Header[3] = LOG_MAGIC_3;
  Header[4] = LOG_VERSION;
  for (Index = 5; Index < LOG_HDR_SIZE; Index++) {
    Header[Index] = 0xFF;
  }

  (VOID)LogWrite (LOG_BASE, Header, LOG_HDR_SIZE);
}

VOID
EFIAPI
LoongsonBootLogEvent (
  IN UINT8   Code,
  IN UINT32  Arg
  )
{
  UINT8  Slot[LOG_SLOT_SIZE];

  if (Code == 0xFF) {
    /* 0xFF is the erased byte value and doubles as "no event". */
    return;
  }

  /*
   * Three bytes of argument plus an explicit marker.  The marker is what makes
   * a slot recognisable whatever the surrounding media reads like: erased flash
   * returns 0xFF and QEMU's flash model returns 0x00 for the parts of the image
   * it has no data for, so neither "not 0xFF" nor "not 0x00" works as a test on
   * its own.  Values wider than 24 bits are encoded by the caller (see the BAR0
   * and GOP events).
   */
  Slot[0] = (UINT8)(Arg & 0xFF);
  Slot[1] = (UINT8)((Arg >> 8) & 0xFF);
  Slot[2] = (UINT8)((Arg >> 16) & 0xFF);
  Slot[3] = LOG_VALUE_MARK;

  (VOID)LogWrite (LOG_BASE + LOG_HDR_SIZE + (UINTN)Code * LOG_SLOT_SIZE,
                  Slot, LOG_SLOT_SIZE);
}
