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
#define SPI_POLL_LIMIT  2000

/*
 * Flash logging is compiled out of the board build.
 *
 * Driving the controller's command engine means writing SPSR/SPCR on a part
 * whose instruction fetch is being served by that same controller, and it runs
 * from the first instruction of SEC -- before anything else, including the
 * buzzer.  Every boot since it was added has been silent, and not one byte of
 * log has ever been read back off the chip, so it costs boot progress and pays
 * nothing.  The primitives and the API stay in the tree behind this switch,
 * ready for the phase that runs from DRAM and can talk to the flash safely.
 */
#ifndef BOOTLOG_FLASH_ENABLE
#define BOOTLOG_FLASH_ENABLE  0
#endif

#if BOOTLOG_FLASH_ENABLE

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
     * No mirror write into the XIP window: the log lives at 0x360000, past the
     * chip's 1 MB boot window, where a store would go to the local-bus window
     * instead.  QEMU cannot see the log as a result (its SPI controller model
     * ignores the program opcodes), but the board is what this is for.
     */
    (VOID)Offset;
  }

  return TRUE;
}

#else

/* Nothing here runs on the board build; see BOOTLOG_FLASH_ENABLE above. */

#endif

/* ------------------------------------------------------------------ */
/* Audible progress (buzzer on GPIO39)                                 */
/* ------------------------------------------------------------------ */

#define GPIO_DIR_HI   UNCACHED (0x1fe00504)
#define GPIO_DATA_HI  UNCACHED (0x1fe00514)
#define BEEP_BIT      0x80u

/*
 * The factory PMON drives the buzzer the same way: GPIO39 is bit 7 of the
 * upper GPIO word, its direction bit lives at 0x1fe00504 and its output data
 * at 0x1fe00514.  Toggling that data bit from a software delay loop makes the
 * tone, so the pitch is whatever this code's loop timing happens to produce.
 *
 * That timing is not knowable from here: SEC executes from the uncached boot
 * window, where every instruction fetch costs a bus round trip, so the same
 * delay count lands on a different pitch than it would from cache.  Guessing
 * the count is what cost two boots: one attempt aimed for ~1.5 kHz and came out
 * silent.
 *
 * So the beep is played as a short chirp that walks four delay values spanning
 * one octave apart.  Every value in it is one the board has already been heard
 * to sound at, and between them the tone is bound to be audible whatever the
 * real loop cost turns out to be.  It warbles and sounds rough -- which is the
 * "hoarse but clear" the board's owner asked for.
 */
#define BEEP_FIRST_PERIOD  0x40  /* the four steps are this shifted by 0..3 */
#define BEEP_STEP_HALVES   8
#define BEEP_HALF_CYCLES   0x20  /* 32 half periods: 4 steps, ~0.2 s */
#define BEEP_GAP_LOOPS     0x4000

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
BeepToneCycles (
  IN UINTN  Cycles
  )
{
  UINT32  Value;
  UINTN   Half;

  /* The other pins in this word are left exactly as they were found. */
  Value = MmioRead32 (GPIO_DATA_HI) & ~BEEP_BIT;

  for (Half = 0; Half < Cycles; Half++) {
    Value ^= BEEP_BIT;
    MmioWrite32 (GPIO_DATA_HI, Value);

    /*
     * Shifted rather than looked up in a table: a table would be a load from
     * this image's read-only data, and the point of the exercise is that the
     * code and its constants are the only things known to be fetchable here.
     */
    BeepDelay ((UINTN)BEEP_FIRST_PERIOD << ((Half / BEEP_STEP_HALVES) & 3));
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
    BeepToneCycles (BEEP_HALF_CYCLES);
    BeepOff ();
    BeepDelay (BEEP_GAP_LOOPS);
  }
}

VOID
EFIAPI
LoongsonBootBeepLong (
  VOID
  )
{
  /* Distinct from any count pattern: three times as long. */
  MmioWrite32 (GPIO_DIR_HI, MmioRead32 (GPIO_DIR_HI) & ~BEEP_BIT);

  BeepToneCycles (BEEP_HALF_CYCLES * 3);
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
#if BOOTLOG_FLASH_ENABLE
  UINT8  Header[LOG_HDR_SIZE];
  UINTN  Index;

  /*
   * Bring up the command engine -- but leave PARAM alone.
   *
   * PMON's write setup (spi_initw) also writes PARAM=0x10, which re-clocks the
   * *read* path; harmless for PMON because it runs from the locked cache, fatal
   * here because this code executes from the flash itself: the next fetch would
   * never arrive.  So the engine gets SPSR/SPER/SPCR/PARAM2 and the clock stays
   * whatever SpiFlashSpeedup() programmed for the XIP read.
   *
   * Without these the controller only does XIP reads, the FIFO never reports
   * ready, and every log write burns its timeout without a byte reaching the
   * chip -- which is exactly what the empty log looked like.
   */
  MmioWrite8 (SPI_REG_BASE + SPI_SPSR, 0xc0);
  MmioWrite8 (SPI_REG_BASE + SPI_SPER, 0x04);
  MmioWrite8 (SPI_REG_BASE + SPI_SPCR, 0x51);
  MmioWrite8 (SPI_REG_BASE + SPI_PARAM2, 0x01);

  Header[0] = LOG_MAGIC_0;
  Header[1] = LOG_MAGIC_1;
  Header[2] = LOG_MAGIC_2;
  Header[3] = LOG_MAGIC_3;
  Header[4] = LOG_VERSION;
  for (Index = 5; Index < LOG_HDR_SIZE; Index++) {
    Header[Index] = 0xFF;
  }

  (VOID)LogWrite (LOG_BASE, Header, LOG_HDR_SIZE);
#endif
}

VOID
EFIAPI
LoongsonBootLogEvent (
  IN UINT8   Code,
  IN UINT32  Arg
  )
{
#if BOOTLOG_FLASH_ENABLE
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
#else
  (VOID)Code;
  (VOID)Arg;
#endif
}
