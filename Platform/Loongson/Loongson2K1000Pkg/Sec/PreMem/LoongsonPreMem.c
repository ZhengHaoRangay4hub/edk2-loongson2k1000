/** @file
  Pre-memory (SEC) initialization for Loongson 2K1000LA (education board).

  Ported from Loongson PMON start.S (Targets/ls2k/ls2k/start.S,
  github.com/loongson-community/pmon-ls2k1000la, loongson-22.09 branch).

  This code runs in-place (XIP) from the SPI NOR window before DRAM is
  initialized. Constraints:
    - no writable static data (.data/.bss would sit in NOR)
    - no DEBUG()/SerialPortLib calls (device tree not published yet)
    - MMIO access only through the uncached DMW0 window (0x9000...)

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Uefi.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include "PreMem.h"

/* Uncached alias of a physical address (DMW0 configured in Start.S). */
#define UNCACHED(x)  ((UINTN)(0x9000000000000000ULL | (UINT64)(x)))

/*
 * Console fan-out: the board exposes three LVTTL UARTs plus the RS232 debug
 * port and nothing public says which are pin-muxed at reset, so all four get
 * every character.  See Include/Library/Loongson2K1000.h.
 */
#define UART0        UNCACHED (0x1fe20000)   /* console: RS232, pins 59/60 */
#define UART0_MIRROR UNCACHED (0x1fe20300)   /* mirror:  LVTTL, pins 8/10 */

#define UART_LSR_THR_EMPTY  0x20
#define UART_MIRROR_GUARD   0x800
#define SYSCONF(x)  UNCACHED (0x1fe00000 + (x))
#define GPIO_CFG    UNCACHED (0x1fe00500)
#define RTC_PWR(x)  UNCACHED (0x1fe27000 + (x))

/* PCIe root complex windows. */
#define PCIE_APB_BAR  UNCACHED (0xfe00001000)
#define PCIE_ECAM     UNCACHED (0xfe00000000)
#define PCIE_CTRL_A   UNCACHED (0xfe0800000c)
#define PCIE_CTRL_B   UNCACHED (0xfe0700001c)
#define PCIE_PHY      UNCACHED (0x1fe00590)

#define MmioOrBit32(addr, bits) \
  MmioWrite32 ((addr), MmioRead32 (addr) | (bits))
#define MmioAndBit32(addr, bits) \
  MmioWrite32 ((addr), MmioRead32 (addr) & (bits))

/**
  Early 16550 initialization, divisor for the pre-PLL APB clock
  (~99.5MHz, PMON uses DLL=0x36/54 to obtain 115200 baud).
**/
VOID
EarlySerialInit (
  VOID
  )
{
  UINTN  Ports[2];
  UINTN  Index;

  Ports[0] = UART0;
  Ports[1] = UART0_MIRROR;

  for (Index = 0; Index < 2; Index++) {
    MmioWrite8 (Ports[Index] + 3, 0x80);   /* DLAB = 1 */
    MmioWrite8 (Ports[Index] + 1, 0x00);   /* DLM      */
    MmioWrite8 (Ports[Index] + 0, 0x36);   /* DLL = 54 */
    MmioWrite8 (Ports[Index] + 3, 0x03);   /* 8N1      */
    MmioWrite8 (Ports[Index] + 2, 0x47);   /* FIFO     */
  }
}

/**
  Write one byte to a UART.  The primary port waits for room as long as it
  takes; a mirror only waits a bounded number of polls and then writes anyway,
  because an ungated UART can report "never ready" and block the firmware.
**/
STATIC
VOID
EarlyPutByte (
  IN UINTN    Base,
  IN UINT8    Byte,
  IN BOOLEAN  Blocking
  )
{
  UINT32  Guard;

  Guard = UART_MIRROR_GUARD;
  while ((MmioRead8 (Base + 5) & UART_LSR_THR_EMPTY) == 0) {
    if (Blocking) {
      continue;
    }

    if (--Guard == 0) {
      break;
    }
  }

  MmioWrite8 (Base + 0, Byte);
}

/**
  Polling character output, callable before the device tree is available.
**/
VOID
EarlyPutString (
  IN CONST CHAR8  *String
  )
{
  while (*String != '\0') {
    EarlyPutByte (UART0, (UINT8)*String, TRUE);
    EarlyPutByte (UART0_MIRROR, (UINT8)*String, FALSE);
    String++;
  }
}

STATIC
VOID
WatchdogClose (
  VOID
  )
{
  /* GPIO3 low releases the external watchdog feeder (PMON watchdog_close). */
  MmioWrite32 (GPIO_CFG,      MmioRead32 (GPIO_CFG) & ~0x8);
  MmioWrite32 (GPIO_CFG + 16, MmioRead32 (GPIO_CFG + 16) & ~0x8);
}

STATIC
VOID
SpiFlashSpeedup (
  VOID
  )
{
  UINTN  Spi = UNCACHED (0x1fff0220);

  /* All CS high, then the boot read clock divider.  The factory PMON binary
     programs 0x27 here (its source default of 0x17 is only used when
     BOOT_SPI_FREQ is undefined), so match the value the board ships with. */
  MmioWrite8 (Spi + 5, 0xff);
  MmioWrite8 (Spi + 4, 0x27);
}

STATIC
VOID
ApbBarConfig (
  VOID
  )
{
  /* Route the APB space behind the PCIe root complex (PMON APB BAR setup). */
  MmioWrite32 (PCIE_APB_BAR + 0x10, 0x1fe20000);
  MmioOrBit32 (PCIE_APB_BAR + 0x04, 0x2);
}

/**
  Bring the LVTTL console pins out.

  The chip pin mux (通用配置寄存器 0, 0x1fe00420) resets with uart0_enable =
  4'b0001 -- "8 wire mode, uart0 only" -- so the UART3 controller that the
  board wires to header pins 8/10 (TX/RX, GND on 9) is connected to nothing
  until firmware asks for it.  uart1/uart2_enable and the sdio/pwm/i2c/...
  enables in the upper bits are left exactly as they are.

  4'b0011 was assumed to select "4 wire mode (uart0 + uart3)", but on real
  hardware writing 0x3 killed the RS232 port (59/60): UART0 TX went from
  mark-idle (-5V on the RS232 side) to stuck-low (+6V), i.e. the nibble does
  NOT behave as an independent uart enable bitmask -- it re-slices the whole
  uart0 pin group and can move uart0 off 59/60.  The factory PMON image ORs
  0x3fd19 (nibble 0x9, uart0 known-good on RS232).

  v8b strategy: leave the nibble exactly at its reset value (uart0 on 59/60,
  proven) and only OR the upper factory enable bits (0x3fd10) -- those carry
  the i2c1 enable without which the SII9022A HDMI transmitter is unreachable.
  uart3-on-8/10 is postponed until the nibble semantics are nailed down.
**/
STATIC
VOID
UartPinMuxInit (
  VOID
  )
{
  UINT32  Value;

  Value  = MmioRead32 (SYSCONF (0x420));
  Value |= 0x3FD10u;         /* factory enable bits, uart nibble untouched */
  MmioWrite32 (SYSCONF (0x420), Value);
}

/**
  PMON ls2k_pcie_phy_write: a0[0:15] = phy register address,
  a0[16:31] = phy data.
**/
STATIC
VOID
PciePhyWrite (
  IN UINT32  Value
  )
{
  MmioWrite64 (PCIE_PHY,      (UINT64)Value | 0x100000000ULL);
  MmioWrite64 (PCIE_PHY + 32, (UINT64)Value | 0x100000000ULL);
  while ((MmioRead32 (PCIE_PHY + 4) & (1 << 2)) == 0) {
  }
}

/**
  Program one PCIe root port, faithful port of PMON ls2k_pcie0_port_conf /
  ls2k_pcie1_port_conf.  Dev is the PCI device number (9..14); Ctrl
  selects controller 0 (dev 9..12) or controller 1 (dev 13..14).
**/
STATIC
VOID
PciePortConf (
  IN UINTN  Dev,
  IN UINTN  Ctrl
  )
{
  UINTN   Cfg;
  UINTN   Bus;
  UINT32  Value;

  Cfg = PCIE_CTRL_A + (Dev << 11);
  MmioAndBit32 (Cfg, 0xfff9ffff);
  MmioOrBit32 (Cfg, 0x20000);

  Cfg = PCIE_CTRL_B + (Dev << 11);
  MmioOrBit32 (Cfg, (0x1 << 26));

  /* Root port config space behind the ECAM window (bus 0). */
  Cfg    = PCIE_ECAM + (Dev << 11);
  Value  = MmioRead32 (Cfg + 0x78);
  Value &= ~(0x7 << 12);
  Value |= 0x1000;
  MmioWrite32 (Cfg + 0x78, Value);

  /* BAR0 of the root port: internal bus MMIO window. */
  MmioWrite32 (Cfg + 0x10, (Ctrl == 0) ? 0x11000000 : 0x10000000);

  /* Internal bus control registers. */
  Bus = (Ctrl == 0) ? UNCACHED (0x11000000) : UNCACHED (0x10000000);

  Value  = MmioRead32 (Bus + 0x54);
  Value &= ~((0x7 << 18) | (0x7 << 2));
  MmioWrite32 (Bus + 0x54, Value);

  Value  = MmioRead32 (Bus + 0x58);
  Value &= ~((0x7 << 18) | (0x7 << 2));
  MmioWrite32 (Bus + 0x58, Value);

  MmioWrite32 (Bus + 0x0, 0xff204c);
}

STATIC
VOID
PcieEarlyConf (
  VOID
  )
{
  UINTN  Index;

  /* signal test pattern (PMON "pcie signal test copy") */
  MmioWrite32 (SYSCONF (0x580), 0xc2492331);
  MmioWrite32 (SYSCONF (0x5a0), 0xc2492331);
  MmioWrite32 (SYSCONF (0x584), 0xff3ff0a8);
  MmioWrite32 (SYSCONF (0x5a4), 0xff3ff0a8);
  MmioWrite32 (SYSCONF (0x588), 0x27fff);
  MmioWrite32 (SYSCONF (0x5a8), 0x27fff);

  /* PCIe PHY register programming (PMON sequence) */
  PciePhyWrite (0x4fff1002);
  PciePhyWrite (0x4fff1102);
  PciePhyWrite (0x4fff1202);
  PciePhyWrite (0x4fff1302);

  /*
   * Enable both PCIe controllers plus the DVO0/DVO1 pin output drivers.
   * The factory PMON image ORs 0x30012 here (disassembly of the backup at
   * file offset 0x15e4); writing only 0x30000 leaves the DVO pads gated off
   * and the HDMI transmitter (SII9022A on DVO0) never sees a pixel clock.
   */
  MmioOrBit32 (SYSCONF (0x430), 0x30012);

  for (Index = 9; Index <= 12; Index++) {
    PciePortConf (Index, 0);
  }

  for (Index = 13; Index <= 14; Index++) {
    PciePortConf (Index, 1);
  }
}

VOID
SataClkConfig (
  VOID
  )
{
  /* internal reference clock (PMON: SATA_USE_EXTERNAL_CLK not defined) */
  MmioWrite32 (SYSCONF (0x454), 0x30c31cf9);
  MmioWrite32 (SYSCONF (0x450), 0xf300040d);
  MmioWrite64 (SYSCONF (0x458), 0x1403f1002ULL);
}

VOID
GmacAndGeneralCfg (
  VOID
  )
{
  UINTN  Mux   = UNCACHED (0x1fe03800);
  UINTN  Index;

  /* Fix GMAC0 multi-function pins to enable GMAC1 */
  MmioWrite64 (Mux + 0x08, 0xffffff0000ffffffULL);

  MmioWrite32 (UNCACHED (0xfe00001800) + 0x0c, 0x0080ff08);

  /* Set the invalid BAR registers read-only */
  for (Index = 0; Index <= 0x50; Index += 8) {
    MmioWrite64 (Mux + Index, 0xff00ff0000fffff0ULL);
  }

  /* enable pcie0/pcie1, dvo0/dvo1 pin output */
  MmioOrBit32 (SYSCONF (0x430), 0x30012);

  /* enable sdio, pwm0, i2c0, i2c1, nand, sata, i2s, gmac1 (CONFIG_REG0) */
  MmioOrBit32 (SYSCONF (0x420), 0x1f49);

  /* clear ACPI power button status */
  MmioOrBit32 (RTC_PWR (0x0c), 0x100);
}

/**
  Locate the DTB (RAW section inside a FREEFORM FFS file) in the firmware
  volume and copy it to the well-known RAM address. Runs after DRAM init.
**/
UINTN
CopyDtbFromFv (
  IN EFI_PHYSICAL_ADDRESS  FvBase,
  IN EFI_PHYSICAL_ADDRESS  Destination
  )
{
  EFI_FIRMWARE_VOLUME_HEADER  *Fv;
  EFI_FFS_FILE_HEADER         *File;
  EFI_COMMON_SECTION_HEADER   *Section;
  UINT8                       *Src;
  UINT8                       *Dst;
  UINTN                       Offset;
  UINTN                       FileSize;
  UINTN                       SectionSize;
  UINTN                       FvLength;
  UINTN                       CopySize;

  Fv       = (EFI_FIRMWARE_VOLUME_HEADER *)(UINTN)FvBase;
  FvLength = Fv->FvLength;

  if (Fv->Signature != EFI_FVH_SIGNATURE) {
    return 0;
  }

  Offset = Fv->HeaderLength;
  while (Offset + sizeof (EFI_FFS_FILE_HEADER) < FvLength) {
    Offset   = (Offset + 7) & ~(UINTN)7;
    File     = (EFI_FFS_FILE_HEADER *)((UINT8 *)(UINTN)FvBase + Offset);
    FileSize = File->Size[0] | (File->Size[1] << 8) | (File->Size[2] << 16);
    if (FileSize < sizeof (EFI_FFS_FILE_HEADER)) {
      break;
    }

    if (File->Type == EFI_FV_FILETYPE_FREEFORM) {
      Section     = (EFI_COMMON_SECTION_HEADER *)(File + 1);
      SectionSize = Section->Size[0] | (Section->Size[1] << 8) | (Section->Size[2] << 16);
      if ((Section->Type == EFI_SECTION_RAW) &&
          (SectionSize > sizeof (EFI_COMMON_SECTION_HEADER)))
      {
        Src      = (UINT8 *)Section + sizeof (EFI_COMMON_SECTION_HEADER);
        CopySize = SectionSize - sizeof (EFI_COMMON_SECTION_HEADER);
        Dst      = (UINT8 *)(UINTN)Destination;
        while (CopySize-- != 0) {
          *Dst++ = *Src++;
        }

        return SectionSize - sizeof (EFI_COMMON_SECTION_HEADER);
      }
    }

    Offset += FileSize;
  }

  return 0;
}

/**
  Post-memory SEC initialization. Called from Start.S with the stack in
  DRAM; publishes the device tree for the FDT-based library classes.
**/
VOID
EFIAPI
PostMemInit (
  VOID
  )
{
  UINTN  DtbSize;

  DtbSize = CopyDtbFromFv (
              (EFI_PHYSICAL_ADDRESS)FixedPcdGet64 (PcdOvmfFdBaseAddress),
              (EFI_PHYSICAL_ADDRESS)FixedPcdGet64 (PcdDeviceTreeInitialBaseAddress)
              );

  if (DtbSize == 0) {
    EarlyPutString ("WARNING: DTB not found in firmware volume!\r\n");
  }
}

/**
  Pre-memory SEC initialization. Called from Start.S with the stack in the
  on-chip SRAM overlay behind 0x1c000000, exactly like PMON's early stage.
  Clock and DDR assembly stages are invoked from Start.S directly because
  they deliberately clobber callee-saved registers.
**/
UINT64
EFIAPI
PreMemInit (
  VOID
  )
{
  /* Order matters, and it is the factory PMON's order: the UART sits behind
     the APB window that ApbBarConfig() opens, so initialising or printing
     before that writes into an unrouted address and the output is lost.  The
     SPI controller is reachable without the BAR (PMON pokes it first), which
     is why the speedup can come before the BAR. */
  SpiFlashSpeedup ();
  ApbBarConfig ();
  UartPinMuxInit ();
  WatchdogClose ();

  EarlySerialInit ();
  EarlyPutString ("\r\nLoongson2K1000LA EDK2 SEC booting... [v8b]\r\n");

  PcieEarlyConf ();

  EarlyPutString ("SoC early init done\r\n");

  return 0;
}
