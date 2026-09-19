/** @file
  Boot progress log written to the SPI NOR flash.

  The board's debug UART is often not reachable during bring-up (the TTL pins
  need a mux change, the RS232 port needs an adapter), so the firmware also
  records how far it got into a dedicated flash region.  After a power cycle
  the chip can be read with a programmer and the log decoded offline with
  tools/decode_bootlog.py -- no serial console needed.

  Region: LS2K_BOOTLOG_BASE .. +LS2K_BOOTLOG_SIZE (64 KB, 16 sectors of 4 KB),
  carved out just below the variable store.  One sector is used per boot and
  the sectors are consumed in order, so the last 16 boots stay available; once
  all 16 are full the region is erased and the sequence restarts.

  Every write is best effort: a missing or uncooperative flash must never stop
  the boot, so all waits are bounded and failures are simply dropped.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#ifndef LOONGSON_BOOT_LOG_H_
#define LOONGSON_BOOT_LOG_H_

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
  One long beep, used for the "reached the boot menu" milestone.
**/
VOID
EFIAPI
LoongsonBootBeepLong (
  VOID
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
