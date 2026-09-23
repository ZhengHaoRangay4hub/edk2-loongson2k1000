/** @file
  Boot progress log written to the SPI NOR flash.

  The board's debug UART is often not reachable during bring-up (the TTL pins
  need a mux change, the RS232 port needs an adapter), so the firmware also
  records how far it got into a dedicated flash region.  After a power cycle
  the chip can be read with a programmer and the log decoded offline with
  tools/decode_bootlog.py -- no serial console needed.

  Region: LS2K_BOOTLOG_BASE .. +LS2K_BOOTLOG_SIZE (60 KB, 15 sectors of 4 KB),
  carved out just below the variable store, with the last 4 KB sector of the log
  area (LS2K_MARK_BASE, Loongson2K1000.h) reserved for the progress marks and
  never used by the log.  The implementation today writes one fixed slot per
  event code in the first sector (see the LOG_* defines in the library) rather
  than one sector per boot; if the per-boot rotation is implemented, it must stop
  at LS2K_MARK_BASE.

  Every write is best effort: a missing or uncooperative flash must never stop
  the boot, so all waits are bounded and failures are simply dropped.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#ifndef LOONGSON_BOOT_LOG_H_
#define LOONGSON_BOOT_LOG_H_

/*
 * Build-time switches for the two flash-writing paths (the event log and the
 * progress marks).  They are defined here rather than inside the library's .c
 * so that every caller can tell whether the call it is about to make writes
 * anything at all: a console message printed next to a compiled-out call
 * ("flash mark A2 written") reads as evidence that the flash was programmed,
 * and on a board whose only other symptom is silence that is exactly the wrong
 * conclusion to hand an operator.  Guard such messages with these macros.
 *
 * Both default to 0 because each of them switches off the instruction fetch
 * the SEC phase is running from (manual 10.5.3: with the SPI read enable
 * clear, the chip cannot fetch from SPI flash).  To enable, edit this file --
 * EDK2 command-line -D defines expand in the DSC/FDF and never reach C code.
 */
#ifndef BOOTLOG_FLASH_ENABLE
#define BOOTLOG_FLASH_ENABLE   0
#endif

#ifndef BOOTMARK_FLASH_ENABLE
#define BOOTMARK_FLASH_ENABLE  0
#endif

/*
 * Event codes.  Keep the numeric values stable: the decoder in
 * tools/decode_bootlog.py maps them to text.
 */
#define BOOTLOG_SEC_ENTRY      0x01  /* arg: 0 */
#define BOOTLOG_SEC_SPI        0x02  /* arg: 0 */
#define BOOTLOG_SEC_APB        0x03  /* arg: 0 */
#define BOOTLOG_SEC_PINMUX     0x04  /* arg: uart0_enable nibble after write */
#define BOOTLOG_SEC_WATCHDOG   0x05  /* arg: 0 */
#define BOOTLOG_SEC_UART       0x06  /* arg: 0 */
#define BOOTLOG_SEC_PCIE       0x07  /* arg: 0 */
#define BOOTLOG_SEC_SOC_DONE   0x08  /* arg: 0 */
#define BOOTLOG_SEC_CLK_BEGIN  0x09  /* arg: 0 */
#define BOOTLOG_SEC_CLK_DONE   0x0A  /* arg: 0 */
#define BOOTLOG_SEC_DDR_BEGIN  0x0B  /* arg: 0 */
#define BOOTLOG_SEC_DDR_DONE   0x0C  /* arg: memory size in MB */
#define BOOTLOG_SEC_DTB        0x0D  /* arg: device tree size, 0 = not found */
#define BOOTLOG_SEC_TO_PEI     0x0E  /* arg: 0 */

#define BOOTLOG_PEI_ENTRY      0x10  /* arg: 0 */
#define BOOTLOG_PEI_MEM        0x11  /* arg: low RAM MB */
#define BOOTLOG_PEI_MEM_HIGH   0x12  /* arg: high RAM MB */
#define BOOTLOG_PEI_FDT        0x13  /* arg: relocated FDT address low 24 bits */
#define BOOTLOG_PEI_TO_DXE     0x14  /* arg: 0 */

#define BOOTLOG_DXE_ENTRY      0x20  /* arg: 0 */
#define BOOTLOG_DXE_NVRAM      0x21  /* arg: 0 */
#define BOOTLOG_DXE_DISPLAY    0x28  /* arg: DC BAR0 as read from PCI config */
#define BOOTLOG_DXE_DC_FALLBACK 0x29 /* arg: 0 -- BAR0 unusable, using internal */
#define BOOTLOG_DXE_SII_FOUND  0x2A  /* arg: (id0 << 16) | (id1 << 8) | id2 */
#define BOOTLOG_DXE_SII_MISSING 0x2B /* arg: 0 */
#define BOOTLOG_DXE_GOP_READY  0x2C  /* arg: (width << 16) | height */
#define BOOTLOG_DXE_GOP_FAIL   0x2D  /* arg: status */

#define BOOTLOG_BDS_ENTRY      0x30  /* arg: 0 */
#define BOOTLOG_BDS_BOOT_TRY   0x31  /* arg: boot option number */
#define BOOTLOG_BDS_SHELL      0x32  /* arg: 0 */

#define BOOTLOG_ERR_ASSERT     0xE0  /* arg: line number */
#define BOOTLOG_ERR_EXCEPTION  0xE1  /* arg: ESTAT bits */
#define BOOTLOG_ERR_HANG       0xE2  /* arg: last stage code before the hang */

/**
  Sound N short beeps on the board's buzzer (GPIO39, the pin the factory PMON
  beeps with).

  This is the bring-up channel that needs neither a serial console nor a
  display: the operator hears how far the firmware got and can count the beeps.
  Called before the corresponding flash log entry, so a hang inside a flash
  program still leaves the audible progress behind.

  @param[in]  Count  Number of beeps (1..9 sensible).
**/
VOID
EFIAPI
LoongsonBootBeep (
  IN UINTN  Count
  );

/**
  Play PMON's own beep waveform from assembly.  Defined in Sec/LoongArch64/
  Start.S: half period 0x2000 iterations of addi.w+nop+bnez, 0x80 half periods
  per beep, GPIO39.  Needs no stack.

  @param[in]  Count  Number of beeps.
**/
VOID
LoongsonBeepRaw (
  IN UINTN  Count
  );

/**
  One long beep, used for the "reached the boot menu" milestone.
**/
VOID
EFIAPI
LoongsonBootBeepLong (
  VOID
  );

/**
  Program one byte in the mark sector, as a "the firmware reached here" mark.

  The board has no console and no display before DXE, so the only dependable way
  to see how far a boot got is to leave a trace in the flash and read it back
  with a programmer.  All marks live in the single 4 KB sector at LS2K_MARK_BASE
  (top of the log region, the one 4 KB of the part that is above the 1 MB reset
  window, outside every firmware volume, outside the variable store and outside
  its FTW blocks, and erased as the board ships), so a mark is a lone byte in a
  field of 0xFF:

    0x36F000 0xA1  reset path ran          LS2K_MARK_A1
    0x36F001 0xA2  PreMemInit entered      LS2K_MARK_A2
    0x36F002 0xA3  UART up                 LS2K_MARK_A3
    0x36F003 0xA4  after clock/PLL         LS2K_MARK_A4
    0x36F004 0xA5  DDR up                  LS2K_MARK_A5
    0x36F008 SR1 read back after the unprotect  LS2K_MARK_SR1
    0x36F009 SR2 read back                      LS2K_MARK_SR2
    0x36F00A SR3 read back                      LS2K_MARK_SR3

  There is no erase in the firmware: the sector ships erased, programming 0xFF
  into 0xFF is a no-op, and a 4 KB erase would keep the chip busy for tens of
  milliseconds with the SPI read enable off.  Erase the sector with the
  programmer to reset the baseline before an experiment.

  The function is compiled out unless BOOTMARK_FLASH_ENABLE is set (see the
  library): it is the only code in SEC that turns off the instruction fetch it
  depends on.

  @param[in]  Offset  One of LS2K_MARK_A1..A5.  Any other address is refused.
  @param[in]  Code    0xA1..0xA5, matching the slot; a mismatch is refused.
**/
VOID
EFIAPI
LoongsonBootMark (
  IN UINTN  Offset,
  IN UINT8  Code
  );

/**
  Play a rising scale from the slowest delay to the fastest.

  Diagnostic, not progress: it exists to find the delay range the buzzer on
  this board is actually loud in, which depends on an instruction fetch cost
  that cannot be worked out from the source.  Run it once and listen, then fix
  the pitch used by LoongsonBootBeep().
**/
VOID
EFIAPI
LoongsonBootBeepScale (
  VOID
  );

/**
  Start the log for this boot: choose the next free sector, erase the region
  when the sectors have all been used, and write the sector header.  Safe to
  call from SEC; repeats after the first call in the same boot are ignored by
  way of the header already being present.
**/
VOID
EFIAPI
LoongsonBootLogBoot (
  VOID
  );

/**
  Append one event to the boot log.

  @param[in]  Code  Event code, see BOOTLOG_* above (must not be 0xFF).
  @param[in]  Arg   24 bit event specific value.
**/
VOID
EFIAPI
LoongsonBootLogEvent (
  IN UINT8   Code,
  IN UINT32  Arg
  );

#endif /* LOONGSON_BOOT_LOG_H_ */
