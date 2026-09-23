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
#define UNCACHED(x)  ((UINTN)(0x8000000000000000ULL | (UINT64)(x)))

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
/*
 * SR2/SR3.  On the W25Q32 family the protection bits are not all in SR1 (BP0-4
 * and SRP0 are; SRP1/CMP/WPS live in SR2/SR3, per docs/understanding/
 * 09-adversarial-flash.md §4.2), so a single-byte 0x01 write cannot claim to have
 * cleared block protection on its own.  A part that does not implement these
 * opcodes answers something meaningless, so the values below are only ever
 * recorded, never interpreted by the firmware.
 */
#define NOR_RDSR2    0x35
#define NOR_RDSR3    0x15

#define SPI_CS_ASSERT   0x01
#define SPI_CS_RELEASE  0x11

/*
 * The read and write clocks of the controller.  PARAM bit 0 is memory_en, and
 * the manual is explicit about what it does: it is the SPI flash read enable,
 * and "无效时 csn[0]可由软件控制" (表 10-8，印刷第 105 页)。§10.5.3（第 108 页）说明后果：
 * 关掉读使能后软件才直接控制 csn[0]，"这意味着在进行此操作时，不能从 SPI
 * Flash 中取指"。
 *
 * 所以标记的 SPI 事务与这段代码的取指是互斥的——手册里没有"置位时控制器忽略
 * 命令引擎"这句话，那是本库自己写的猜测（原文在 docs/BRINGUP.md:506）。下面两条
 * 规则就是从这里来的，标记通路必须两条都守：PARAM 是第一个 SPI 事务之前最后写的
 * 一个寄存器、也是最后一个事务之后第一个被恢复的寄存器；中间不允许夹任何非 SPI
 * 事务的代码。
 *
 * SPI_PARAM_READ 必须是 XIP 读通路当时真正在用的值：SpiFlashSpeedup()
 * （Sec/PreMem/LoongsonPreMem.c:144）写的是 0x27，所以回写 0x27。原来的 0x17 是
 * 0x27 把 clk_div 从 2 改成 1（表 10-7 / 表 10-8），回写它等于在退出每个标记时把
 * 读时钟翻倍——正在出问题的那条通路不该再动。
 *
 * PMON 的 spi_initw/spi_initr 用的是 0x10/0x17（refs/pmon spawn Targets/ls2k/dev/
 * spi_w.c:52-68），但 PMON 在这块板上从没跑过它的 flash 写命令，所以那不是"这两个
 * 值能用"的证据。
 */
#define SPI_PARAM_READ   0x27
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

/**
  PMON's own waveform, from Start.S.

  Everything audible used to be produced here with a C delay loop, and it never
  sounded like the factory firmware: PMON's half period is 0x2000 iterations of
  addi.w + nop + bnez, while this was 0x40..0x200 iterations of a volatile
  counter - two orders of magnitude off the frequency the element is loud at,
  which is why the board's owner could not hear it well enough to count beeps.
  The assembly version is PMON's loop, unchanged, and needs no stack.
**/
VOID
LoongsonBeepRaw (
  IN UINTN  Count
  );

VOID
EFIAPI
LoongsonBootBeep (
  IN UINTN  Count
  )
{
  LoongsonBeepRaw (Count);
}

VOID
EFIAPI
LoongsonBootBeepLong (
  VOID
  )
{
  LoongsonBeepRaw (3);
}

/**
  Kept for its call site, but no longer a scale.

  The sweep existed to find the pitch this board's buzzer is loud at, by
  wandering through delays and listening for the loudest step.  The answer
  turned out to be PMON's own half period, so the scale has nothing left to
  search: it plays one beep, in the waveform that is known to be loud, and the
  call site still marks the same milestone.
**/
VOID
EFIAPI
LoongsonBootBeepScale (
  VOID
  )
{
  LoongsonBeepRaw (1);
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
 * Compiled out of the board build by default, on purpose.
 *
 * This is the only code in SEC that deliberately switches off the instruction
 * fetch it is running from: 表 10-8 gives csn[0] to software only while PARAM
 * bit 0 is clear, and §10.5.3 says that with the read enable off the chip cannot
 * fetch from SPI flash at all.  Whether the silicon really stops fetching is
 * untested on this board (docs/understanding/09-adversarial-flash.md §2.4), but
 * every boot since the marks were added has been silent, and a mark is the one
 * action in the boot path whose failure mode is indistinguishable from a dead
 * board.  So the marks default to off, and the image that gets flashed next must
 * be able to boot with the SPI command engine untouched from reset to DXE.
 *
 * Turn them on only in a diagnostic image, by setting this #define to 1 and
 * rebuilding (a one-character edit, the same way BOOTLOG_FLASH_ENABLE is
 * switched).  A command-line `build -D BOOTMARK_FLASH_ENABLE=1` does NOT reach
 * C code: EDK2's command-line defines are build-tool macros, they expand in the
 * DSC/FDF and never land in the module's CC_FLAGS - measured on this tree,
 * where gCommandLineDefines held the flag while CC_FLAGS did not and
 * LoongsonBootMark() still came out as a 4-byte ret.
 *
 * With the marks enabled LoongsonBootMark() keeps the
 * PARAM clear bracketed as tightly as the hardware allows: PARAM last in before
 * the first transaction, first out after the last, no erase, and the whole
 * record written by a single page program.
 */
#if BOOTMARK_FLASH_ENABLE

/*
 * The primitives below follow PMON's spi_w.c, because getting them subtly wrong
 * is invisible: a controller that refuses the command, or a chip whose block
 * protection is still set, both leave the flash exactly as it was --
 * indistinguishable from firmware that never ran.  Where they differ from PMON
 * the difference is a bound (see each function), because every wait here is
 * spent with the read enable clear.
 */

/**
  Send one byte and wait for it to leave the FIFO.  PMON's send_spi_cmd does
  this for every byte; skipping the wait drops bytes on the floor.

  The wait is on SPSR bit 0 (rfempty, 表 10-4 第 103 页), which is what PMON polls
  too: refs/pmon Targets/ls2k/dev/spi_w.c:76 `while(((GET_SPI(SPSR)) & RFEMPTY)
  && timeout--)`, with `#define RFEMPTY 1` at :38.  The read below drains the byte
  the controller shifted in at the same time.

  The bound is PMON's own, 1000, not the 100000 this used to be: every one of
  these iterations runs with PARAM bit 0 clear, where the CPU cannot fetch, so a
  bound that can outlast the boot is not a bound.
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

  Timeout = 1000;
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

/** Read a status register: 0x05 = SR1, 0x35 = SR2, 0x15 = SR3. */
STATIC
UINT8
BootMarkReadSrReg (
  IN UINTN  Spi,
  IN UINT8  Opcode
  )
{
  UINT8  Value;

  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, Opcode);
  Value = BootMarkSend (Spi, 0x00);
  BootMarkCs (Spi, SPI_CS_RELEASE);

  return Value;
}

/** Read SR1 (0x05), PMON's read_sr. */
STATIC
UINT8
BootMarkReadSr (
  IN UINTN  Spi
  )
{
  return BootMarkReadSrReg (Spi, NOR_RDSR);
}

/**
  Wait out the chip's busy bit, with a bound so a dead chip cannot hang boot.

  The bound is 20000 status reads, not the 1000000 this used to be.  Each read is
  a full SPI transaction issued with PARAM bit 0 clear, i.e. with instruction
  fetch from this very flash switched off (§10.5.3), so this number *is* the
  worst case the board can be left deaf for.  PMON's is 1000 (spi_w.c:101); this
  path still has to wait out one page program (milliseconds) and one status
  register write, so 20000 keeps a wide margin while staying inside tens of
  milliseconds.  The 4 KB sector erase that needed a seconds-scale bound is gone
  (see LoongsonBootMark).
**/
STATIC
VOID
BootMarkWaitBusy (
  IN UINTN  Spi
  )
{
  UINT32  Timeout;

  Timeout = 20000;
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
  Clear the status register's protection bits and report SR1 as it reads back.

  This is the step that decides whether anything else works.  A chip with BP0-4
  or SRP0 set answers a page program by ignoring it and reporting success on the
  bus, so the firmware's marks would never appear and the board would look
  exactly like one that never ran.  PMON writes the status register to zero
  before every erase and every program for the same reason (refs/pmon Targets/
  ls2k/dev/spi_w.c:121, :389, :421) -- but PMON's write_sr is one byte wide too
  (:143-155), so it proves only that SR1 was written.

  0x01 writes SR1 only: BP0-4 are SR1 bits 6:2 and SRP0 is bit 7, so this byte
  covers those.  The protection bits that live in SR2/SR3 (SRP1, CMP, WPS on the
  W25Q32 family) are not covered by it, which is exactly why the caller records
  SR1/SR2/SR3 as read back instead of assuming the clear worked.  Whether a
  given part implements 0x35/0x15 at all is not checked here; a part that does
  not answers with something meaningless, and that byte is recorded, not acted
  on.

  @return SR1 after the write.  bit0 = busy, bits 6:2 = BP0-4, bit7 = SRP0.
**/
STATIC
UINT8
BootMarkUnprotect (
  IN UINTN  Spi
  )
{
  UINT8  Sr1;

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

  /* 0x01 starts an internal write cycle; the chip ignores everything until it
     ends, and a WREN that lands inside it is dropped without a word. */
  BootMarkWaitBusy (Spi);

  Sr1 = BootMarkReadSrReg (Spi, NOR_RDSR);
  if ((Sr1 & 0xFC) != 0) {
    /* One retry, because the likeliest reason a clear did not take is a WREN
       that arrived during the previous write cycle. */
    BootMarkWren (Spi);
    BootMarkCs (Spi, SPI_CS_ASSERT);
    BootMarkSend (Spi, 0x01);
    BootMarkSend (Spi, 0x00);
    BootMarkCs (Spi, SPI_CS_RELEASE);
    BootMarkWaitBusy (Spi);
    Sr1 = BootMarkReadSrReg (Spi, NOR_RDSR);
  }

  return Sr1;
}

/*
 * This board offers nothing to watch: no serial console, no display before DXE,
 * and a buzzer whose pitch depends on an instruction-fetch cost that cannot be
 * worked out from the source.  "Where did it stop?" has therefore been
 * unanswerable, and every attempt to answer it by ear was a guess.
 *
 * A mark answers it by machine: each milestone programs one byte into one
 * dedicated 4 KB sector at the top of the log region (LS2K_MARK_BASE), so
 * reading the chip with the programmer afterwards shows how far the firmware
 * got.  Programming turns 0xFF into the code, which is the direction NOR flash
 * moves on its own: that sector ships erased and nothing else -- no firmware
 * volume, no log entry, no variable write -- ever lands in it, so a mark is a
 * lone byte standing out in 4 KB of 0xFF.
 *
 * There is no erase here, and there must not be one.  Erasing would be the wrong
 * direction (an erased sector reads like one that was never touched), and a 4 KB
 * sector erase keeps the chip busy for tens of milliseconds -- docs/BOOTLOG.md:66-67
 * reaches the same conclusion -- every millisecond of it spent with PARAM bit 0
 * clear while the CPU fetches from that same chip.  Instead the whole record is
 * written by one page program: the mark byte and the SR1/SR2/SR3 snapshot share
 * a 256 byte page, so the read enable is cleared once per mark rather than once
 * per byte and restored immediately after.
 *
 * The mark sector is the only 4 KB of the 4 MB part that is above the 1 MB
 * reset window, outside every firmware volume, outside the variable store and
 * outside its FTW working and spare blocks (Loongson2K1000Pkg.dsc:366-375), and
 * it is 0xFF as the board ships (verified in the factory dump and in the
 * full-chip read of the live chip).  LoongsonBootMark() enforces that: a call
 * naming any other address, or the wrong code for the slot, is refused instead
 * of written -- the old call sites named 0x3B0000..0x3F0000, which is precisely
 * the FTW area, so a stale call site used to corrupt variables rather than leave
 * a trace.
 */
VOID
EFIAPI
LoongsonBootMark (
  IN UINTN  Offset,
  IN UINT8  Code
  )
{
  UINT8  Record[LS2K_MARK_PAGE_LEN];
  UINTN  Index;
  UINTN  Spi;

  /*
   * Fail closed.  A mark is accepted only at one of the five slot addresses and
   * only with the code that belongs to that slot (0xA1 + slot); anything else is
   * a no-op.  A refused mark costs one missing byte in a diagnostic, an accepted
   * one at the wrong address used to corrupt the variable store's FTW blocks.
   */
  if ((Offset < LS2K_MARK_BASE) || (Offset >= LS2K_MARK_BASE + 5)) {
    return;
  }

  if (Code != (UINT8)(0xA1 + (Offset - LS2K_MARK_BASE))) {
    return;
  }

  /*
   * Build the record before touching the controller: nothing below this point
   * may run while the read enable is clear except the SPI transactions
   * themselves.  Slots left at 0xFF are no-ops on a byte that already holds a
   * value, so the status snapshot accumulates as the AND of every boot that got
   * this far -- 0xFF still means "no boot ever wrote it".
   */
  for (Index = 0; Index < LS2K_MARK_PAGE_LEN; Index++) {
    Record[Index] = 0xFF;
  }

  Record[Offset - LS2K_MARK_BASE] = Code;

  Spi = SPI_REG_BASE;

  /* Transaction setup.  SPSR is a status register: 0xc0 clears spif and wcol
     (表 10-4：写 1 清零), it enables nothing.  PMON's spi_initw writes the same
     four values (spi_w.c:52-60). */
  MmioWrite8 (Spi + SPI_SPER, 0x04);
  MmioWrite8 (Spi + SPI_PARAM2, 0x01);
  MmioWrite8 (Spi + SPI_SPCR, 0x51);

  /* The read enable goes off here.  §10.5.3 is why nothing but a SPI
     transaction may happen until it is back on. */
  MmioWrite8 (Spi + SPI_PARAM, SPI_PARAM_WRITE);
  MmioWrite8 (Spi + SPI_SOFTCS, 0xff);
  MmioWrite8 (Spi + SPI_SPSR, 0xc0);

  /* Clear the protection bits, then record what the three status registers read
     back -- a mark that never appears has to be explainable without a second
     bring-up. */
  Record[LS2K_MARK_SR1 - LS2K_MARK_BASE] = BootMarkUnprotect (Spi);
  Record[LS2K_MARK_SR2 - LS2K_MARK_BASE] = BootMarkReadSrReg (Spi, NOR_RDSR2);
  Record[LS2K_MARK_SR3 - LS2K_MARK_BASE] = BootMarkReadSrReg (Spi, NOR_RDSR3);

  /* One page program for the whole record: mark byte and snapshot together. */
  BootMarkWren (Spi);
  BootMarkCs (Spi, SPI_CS_ASSERT);
  BootMarkSend (Spi, NOR_PROGRAM);
  BootMarkSend (Spi, (UINT8)(LS2K_MARK_BASE >> 16));
  BootMarkSend (Spi, (UINT8)(LS2K_MARK_BASE >> 8));
  BootMarkSend (Spi, (UINT8)LS2K_MARK_BASE);
  for (Index = 0; Index < LS2K_MARK_PAGE_LEN; Index++) {
    BootMarkSend (Spi, Record[Index]);
  }
  BootMarkCs (Spi, SPI_CS_RELEASE);
  BootMarkWaitBusy (Spi);

  /* The read enable comes back before anything that is not a SPI transaction. */
  MmioWrite8 (Spi + SPI_PARAM, SPI_PARAM_READ);
}

#else

/*
 * Nothing is programmed when the marks are compiled out.  The call sites stay
 * in the tree -- they are part of the recorded boot order -- and become no-ops,
 * so enabling or disabling the marks never changes anything but this library.
 */
VOID
EFIAPI
LoongsonBootMark (
  IN UINTN  Offset,
  IN UINT8  Code
  )
{
  (VOID)Offset;
  (VOID)Code;
}

#endif
