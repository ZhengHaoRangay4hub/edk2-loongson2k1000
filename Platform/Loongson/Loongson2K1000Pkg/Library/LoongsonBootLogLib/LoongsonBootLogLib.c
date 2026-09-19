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
#define NOR_ERASE_4K 0x20

#define SPI_CS_ASSERT   0x01
#define SPI_CS_RELEASE  0x11

/*
 * The read and write clocks of the controller.  PARAM bit 0 (memory_en) is what
 * the hardware gates software chip select on: while it is set the controller
 * serves the boot window and ignores the command engine, which is why a log
 * that never wrote PARAM never programmed a byte.
 *
 * PMON's spi_initw/spi_initr carry exactly these two values, and it can flip
 * between them at run time because its code is executing from RAM, not from
 * the flash it is writing -- the boot ROM copies the image into the on-chip
 * memory at reset.  The same is true here.
 */
#define SPI_PARAM_READ   0x17
#define SPI_PARAM_WRITE  0x10

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

/**
  Play a rising scale, from the slowest delay to the fastest.

  The pitch of a software square wave is set by how fast this code can toggle
  the pin, and SEC executes uncached from the boot window, so that cost is not
  knowable from outside: a single guessed delay already cost two silent boots.
  A scale answers the question in one power cycle -- whichever step sounds
  loudest and cleanest names the delay worth using.

  Six steps, each four times faster than the last, so the range spans a factor
  of a thousand either side of anything guessed so far.  The slowest step takes
  many times longer than the fastest, which is intentional: the fast ones only
  need to be present, not beautiful.
**/
VOID
EFIAPI
LoongsonBootBeepScale (
  VOID
  )
{
  UINTN   Step;
  UINTN   Delay;
  UINTN   Half;
  UINT32  Value;

  MmioWrite32 (GPIO_DIR_HI, MmioRead32 (GPIO_DIR_HI) & ~BEEP_BIT);
  Value = MmioRead32 (GPIO_DATA_HI) & ~BEEP_BIT;

  for (Step = 0; Step < 6; Step++) {
    Delay = (UINTN)0x2000 >> (Step * 2);

    for (Half = 0; Half < 32; Half++) {
      Value ^= BEEP_BIT;
      MmioWrite32 (GPIO_DATA_HI, Value);
      BeepDelay (Delay);
    }

    /* Long enough to separate one step from the next. */
    BeepDelay (0x4000);
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

/* ------------------------------------------------------------------ */
/* "I got here" marks in the flash                                     */
/* ------------------------------------------------------------------ */

/*
 * The primitives below follow PMON's spi_w.c byte for byte, because getting
 * them subtly wrong is invisible: a controller that refuses the command, or a
 * chip whose block protection is still set, both leave the flash exactly as it
 * was -- indistinguishable from firmware that never ran.
 */

/**
  Send one byte and wait for it to leave the FIFO.  PMON's send_spi_cmd does
  this for every byte; skipping the wait drops bytes on the floor.
**/
STATIC
UINT8
BootMarkSend (
  IN UINTN  Spi,
  IN UINT8  Value
  )
{
  UINT32  Timeout;

  MmioWrite8 (Spi + SPI_FIFO, Value);

  Timeout = 100000;
  while (((MmioRead8 (Spi + SPI_SPSR)) & SPI_RFEMPTY) != 0) {
    if (Timeout-- == 0) {
      break;
    }
  }

  return MmioRead8 (Spi + SPI_FIFO);
}

STATIC
VOID
BootMarkCs (
  IN UINTN  Spi,
  IN UINT8  State
  )
{
  MmioWrite8 (Spi + SPI_SOFTCS, State);
}

/** Read the status register (0x05), PMON's read_sr. */
STATIC
UINT8
BootMarkReadSr (
  IN UINTN  Spi
  )
{
  UINT8  Value;

  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, NOR_RDSR);
  Value = BootMarkSend (Spi, 0x00);
  BootMarkCs (Spi, SPI_CS_RELEASE);

  return Value;
}

/** Wait out the chip's busy bit, with a bound so a dead chip cannot hang boot. */
STATIC
VOID
BootMarkWaitBusy (
  IN UINTN  Spi
  )
{
  UINT32  Timeout;

  Timeout = 1000000;
  while (((BootMarkReadSr (Spi) & 0x01) != 0) && (Timeout-- != 0)) {
  }
}

/** Write enable: 0x06, PMON's set_wren. */
STATIC
VOID
BootMarkWren (
  IN UINTN  Spi
  )
{
  BootMarkWaitBusy (Spi);

  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, NOR_WREN);
  BootMarkCs (Spi, SPI_CS_RELEASE);
}

/**
  Clear every block-protection bit in the status register.

  This is the step that decides whether anything else works.  A chip with BP0-3,
  TB, SEC or SRP set answers a sector erase or a page program by ignoring it and
  reporting success on the bus, so the firmware's marks would never appear and
  the board would look exactly like one that never ran.  PMON writes the status
  register to zero before every erase and every program for the same reason.
**/
STATIC
VOID
BootMarkUnprotect (
  IN UINTN  Spi
  )
{
  BootMarkWren (Spi);

  /* Enable-Write-Status-Register (0x50), PMON's en_write_sr. */
  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, 0x50);
  BootMarkCs (Spi, SPI_CS_RELEASE);

  /* Write status register (0x01), PMON's write_sr. */
  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, 0x01);
  BootMarkSend (Spi, 0x00);
  BootMarkCs (Spi, SPI_CS_RELEASE);
}

/*
 * This board offers nothing to watch: no serial console, no display before DXE,
 * and a buzzer whose pitch depends on an instruction-fetch cost that cannot be
 * worked out from the source.  "Where did it stop?" has therefore been
 * unanswerable, and every attempt to answer it by ear was a guess.
 *
 * A mark answers it by machine: each milestone programs one byte into a sector
 * high in the chip, so reading the chip with the programmer afterwards shows
 * how far the firmware got.  Programming turns 0xFF into the code, which is
 * the direction NOR flash moves on its own -- the sectors used here are erased
 * (0xFF) as the board ships, so a mark is a lone byte standing out in 4 KB of
 * 0xFF.  Erasing would have been the wrong direction: an erased sector reads
 * the same as one that was never touched.
 *
 * The write uses PMON's own clock dance: put the controller on its write clock
 * first, because PARAM bit 0 (memory_en) is what gates software chip select --
 * with it set the controller serves the boot window and ignores the command
 * engine.  PMON gets away with flipping this at run time because its code
 * executes from on-chip memory rather than from the flash it is programming;
 * the same holds for this image.
 *
 * The mark sits far above the firmware, so no image overwrites it and it
 * survives across boots until the chip is erased.
 */
VOID
EFIAPI
LoongsonBootMark (
  IN UINTN  SectorOffset,
  IN UINT8  Code
  )
{
  UINTN  Spi;

  Spi = SPI_REG_BASE;

  /* All chip selects high, then the write clock (PMON's spi_initw). */
  MmioWrite8 (Spi + SPI_SOFTCS, 0xff);
  MmioWrite8 (Spi + SPI_PARAM, SPI_PARAM_WRITE);
  MmioWrite8 (Spi + SPI_SPSR, 0xc0);
  MmioWrite8 (Spi + SPI_PARAM2, 0x01);
  MmioWrite8 (Spi + SPI_SPER, 0x04);
  MmioWrite8 (Spi + SPI_SPCR, 0x51);

  BootMarkUnprotect (Spi);

  /*
   * Erase the sector before programming into it.
   *
   * A sector that is already 0xFF cannot show whether an erase command ever
   * arrived -- erasing it is a no-op either way.  So the field below is
   * pre-loaded with 0x00 by the programmer, and this erase turns it to 0xFF:
   * a sector still reading 0x00 means the firmware never got here, a sector
   * reading 0xFF means it got here and the controller accepted commands, and
   * the code byte appearing means the program step works too.  Without the
   * erase there is no way to tell "never ran" from "ran but could not write".
   */
  BootMarkWren (Spi);
  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, NOR_ERASE_4K);
  BootMarkSend (Spi, (UINT8)(SectorOffset >> 16));
  BootMarkSend (Spi, (UINT8)(SectorOffset >> 8));
  BootMarkSend (Spi, (UINT8)SectorOffset);
  BootMarkCs (Spi, SPI_CS_RELEASE);
  BootMarkWaitBusy (Spi);

  BootMarkWren (Spi);

  /* Page program, one byte, 24 bit address. */
  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, NOR_PROGRAM);
  BootMarkSend (Spi, (UINT8)(SectorOffset >> 16));
  BootMarkSend (Spi, (UINT8)(SectorOffset >> 8));
  BootMarkSend (Spi, (UINT8)SectorOffset);
  BootMarkSend (Spi, Code);
  BootMarkCs (Spi, SPI_CS_RELEASE);

  BootMarkWaitBusy (Spi);

  /* Back to the read clock so the next fetch is served again. */
  MmioWrite8 (Spi + SPI_PARAM, SPI_PARAM_READ);
}
