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
#include <Library/BaseMemoryLib.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include "PreMem.h"
#include <Library/LoongsonBootLog.h>
#include <Library/Loongson2K1000.h>

/* Uncached alias of a physical address (DMW0 in Start.S).  0x8000 is the
   window PMON, the field-proven beep stub and Linux all use for uncached
   MMIO; this port had it on 0x9000, which only QEMU tolerates (it masks to
   48 bits and never consults the DMWs). */
#define UNCACHED(x)  ((UINTN)(0x8000000000000000ULL | (UINT64)(x)))

/*
 * Console fan-out: the board exposes three LVTTL UARTs plus the RS232 debug
 * port and nothing public says which are pin-muxed at reset, so all four get
 * every character.  See Include/Library/Loongson2K1000.h.
 */
#define UART0        UNCACHED (0x1fe20000)   /* console: RS232, pins 59/60 */
#define UART0_MIRROR UNCACHED (0x1fe20300)   /* mirror:  LVTTL, pins 8/10 */

#define UART_LSR_THR_EMPTY  0x20
#define UART_MIRROR_GUARD   0x800       /* bounded polls for a mirror port */
#define UART_BLOCKING_GUARD 0x100000    /* bounded polls on the primary too */
/* Generic configuration registers 0/1 (manual 5.1/5.2, printed page 34-37).
   CFG0 carries the gmac/sata/i2c/pwm/can/hda/i2s selects and has no UART
   field at all; CFG1[3:0] is uart0_enable, the field that decides which UART
   controllers reach the shared "UART0 interface" pin group. */
#define SYSCONF_CFG0             0x420
#define SYSCONF_CFG1             0x428
#define CFG1_UART0_ENABLE_MASK   0x0000000Fu
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
  Early 16550 initialization, for the clock that exists before the clock stage
  runs.  At reset (SYS_CLKSEL = 2'b10, software configuration) every PLL output
  defaults to the 100 MHz reference clock (manual 3.5.2, printed page 23), and
  divisor 54 = 0x36 gives 100 MHz / (16 x 54) = 115.7 kbaud (+0.5%; the 16x
  oversampling is the 16550 convention the working PMON values follow).  This
  is the value the shipped firmware programs first - its initserial at file
  offset 0x5ae0 stores 0x36 - and it is wrong once the clock stage has switched
  the DC PLL in: the APB clock is then 125 MHz and 54 would give 144.7 kbaud.
  ClkSetting.S:161 reprograms UART0 for that clock (initserial_later, divisor
  68); EarlySerialInitAt125M() below does the same for both console ports,
  because initserial_later only touches UART0.
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
    MmioWrite8 (Ports[Index] + 0, 0x36);   /* DLL = 54: pre-PLL 100 MHz   */
    MmioWrite8 (Ports[Index] + 3, 0x03);   /* 8N1      */
    MmioWrite8 (Ports[Index] + 2, 0x47);   /* FIFO     */
  }
}

/**
  Re-program both console UARTs for the clock that is live after the clock
  stage switched the DC PLL in.  gmac_clock is 125 MHz (manual 3.4, printed
  page 22) and FREQSCALE resets to apb_freqscale = 0x7, i.e. 8/(7+1) = 1
  division, so the APB clock is 125 MHz (manual 5.18 / table 5-19, printed
  page 52) and the divisor is 68: 125 MHz / (16 x 68) = 114.9 kbaud (-0.3%).

  Needed because the ported PMON helper only reprograms UART0: UART3 would
  keep divisor 54 and print at 144.7 kbaud from that point on, so every
  character written after the clock stage must be preceded by this call.
**/
STATIC
VOID
EarlySerialInitAt125M (
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
    MmioWrite8 (Ports[Index] + 0, 0x44);   /* DLL = 68: post-PLL 125 MHz  */
    MmioWrite8 (Ports[Index] + 3, 0x03);   /* 8N1      */
    MmioWrite8 (Ports[Index] + 2, 0x47);   /* FIFO     */
  }
}

/**
  Write one byte to a UART.  Both ports are polled with a bound: an ungated
  UART (or one whose APB window is not decoded) can report "never ready", and
  the firmware must not be able to hang on a single character.

  Every call site in this file passes Blocking = FALSE today, so the old
  "if (Blocking) continue;" was unreachable - but it was an unbounded loop
  sitting one call-site edit away from a dead board.  The long wait is now
  finite as well.
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

  Guard = Blocking ? UART_BLOCKING_GUARD : UART_MIRROR_GUARD;
  while ((MmioRead8 (Base + 5) & UART_LSR_THR_EMPTY) == 0) {
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
    /* Bounded: a UART that never reports ready must not hang the boot. */
    EarlyPutByte (UART0, (UINT8)*String, FALSE);
    EarlyPutByte (UART0_MIRROR, (UINT8)*String, FALSE);
    String++;
  }
}

/**
  One hexadecimal digit on both console ports.
**/
STATIC
VOID
EarlyPutHexDigit (
  IN UINT8  Digit
  )
{
  UINT8  Char;

  Char = (UINT8)((Digit < 10) ? ('0' + Digit) : ('A' + (Digit - 10)));
  EarlyPutByte (UART0, Char, FALSE);
  EarlyPutByte (UART0_MIRROR, Char, FALSE);
}

/**
  Eight hexadecimal digits, for register readbacks on the serial console.
**/
STATIC
VOID
EarlyPutHex32 (
  IN UINT32  Value
  )
{
  INTN  Nibble;

  for (Nibble = 7; Nibble >= 0; Nibble--) {
    EarlyPutHexDigit ((UINT8)((Value >> (Nibble * 4)) & 0xF));
  }
}

/**
  Two hexadecimal digits, for register readbacks on the serial console.
**/
STATIC
VOID
EarlyPutHex8 (
  IN UINT8  Value
  )
{
  EarlyPutHexDigit ((UINT8)(Value >> 4));
  EarlyPutHexDigit ((UINT8)(Value & 0xF));
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

  /* All CS high, then the SPI configuration byte.  0x27 does not touch the
     read clock divider - the reset value already has clk_div = 2 - it turns on
     fast_read and burst_en; the factory PMON binary programs exactly this byte
     (the source default of 0x17 is only used when BOOT_SPI_FREQ is undefined,
     and 0x17 *would* change the divider, so do not "align" this to it). */
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

  Two registers are involved, and only one of them was being written:

    - 0x1FE00420 (generic configuration register 0, manual 5.1 / table 5-2,
      printed page 34-36) has no UART field at all - it carries the gmac,
      sata, i2c, pwm, can, hda and i2s selects.  The factory PMON writes
      0x3FD19 into it (shipped image, file offset 0x15f4-0x1610) and so does
      this function; that part stays byte for byte, and it is NOT what brings
      the UART pins out.
    - 0x1FE00428 (generic configuration register 1, manual 5.2 / table 5-3,
      printed page 36-37) holds uart0_enable[3:0], whose reset value 4'b0001
      is "8 wire mode (uart0 only)".  Nothing in this firmware wrote it, so
      the UART3 controller the board wires to header pins 8/10 (GND on 9) was
      never connected to anything.

  4'b1111 = "2 wire mode (uart0 + uart3 + uart4 + uart5)" (table 5-3 printed
  page 37; table 2-39 printed page 20) is the value the shipped PMON leaves
  behind: its source does readq(LS2K1000_GENERAL_CFG1) |= 0xe
  (CONFIG_UART0_SPLIT, Targets/ls2k/ls2k/tgt_machdep.c:361) and later |= 0xf
  (UART0_ENABLE, :457), both options enabled in conf/ls2k_gypi:356-357, and
  the shipped binary contains exactly those two read-modify-writes to
  0x1fe00428 (offsets 0xa3800 and 0xa2a58/0xa32d8 of the gzip-decompressed
  PMON payload at image offset 0xf0c0).  It is also the only mode that brings
  out all three LVTTL ports this board exposes (board manual 5.3.1: 8/10,
  53/54, 55/56).

  The previous note here claimed 4'b0011 ("4 wire mode, uart0 + uart3") is
  not a valid bitmask because writing 0x3 killed the RS232 port.  4'b0011 is
  a documented value, and table 2-22 (printed page 15) puts TXD0 on the first
  pad and RXD0 on the fourth in all three modes, so that observation is not
  explained by the manual - it needs a re-test on hardware, not a comment.
  4'b1111 sidesteps the question and matches the factory.

  Read-modify-write on 0x1FE00428: only bits [3:0] change, so
  uart1_enable/uart2_enable (4'b0001 each at reset) and uart1_sel/uart2_sel
  keep their values, as do the delay_ , usb_ and awmon_ fields.
**/
STATIC
VOID
UartPinMuxInit (
  VOID
  )
{
  UINT32  Value;

  Value  = MmioRead32 (SYSCONF (SYSCONF_CFG0));
  Value |= 0x3FD19u;         /* factory value, byte for byte */
  MmioWrite32 (SYSCONF (SYSCONF_CFG0), Value);

  MmioOrBit32 (SYSCONF (SYSCONF_CFG1), CFG1_UART0_ENABLE_MASK);
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
  UINT32  Guard;

  MmioWrite64 (PCIE_PHY,      (UINT64)Value | 0x100000000ULL);
  MmioWrite64 (PCIE_PHY + 32, (UINT64)Value | 0x100000000ULL);

  /*
   * Bounded.  The ported PMON code spins here forever waiting for the PHY's
   * "done" bit; on this board the bit does not come up, and the firmware sat in
   * this loop -- after the first beep and before the second, which is exactly
   * where the board went quiet.  A best-effort PHY write must not be able to
   * stop the boot.
   */
  Guard = 100000;
  while (((MmioRead32 (PCIE_PHY + 4) & (1 << 2)) == 0) && (--Guard != 0)) {
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

/* FILE GUID of the FREEFORM file that carries the DTB; it must stay in sync
   with the FILE statement in Loongson2K1000Pkg.fdf. */
STATIC CONST EFI_GUID  mDtbFileGuid = {
  0xe1f5c2a9, 0x8b3d, 0x4c6e, { 0x9f, 0x70, 0x1a, 0x2b, 0x3c, 0x4d, 0x5e, 0x6f }
};

/**
  Locate the DTB (RAW section of the file named mDtbFileGuid) in the firmware
  volume and copy it to the well-known RAM address. Runs after DRAM init.

  Matching on the file GUID is what makes this reliable: FVMAIN_COMPACT holds
  more than one FREEFORM file with a RAW section - the PEI APRIORI list is the
  first of them - so "first FREEFORM + RAW" copies the APRIORI GUID array and
  the device tree library then reads it as an FDT header.
**/
UINTN
CopyDtbFromFv (
  IN EFI_PHYSICAL_ADDRESS  FvBase,
  IN EFI_PHYSICAL_ADDRESS  Destination
  )
{
  EFI_FIRMWARE_VOLUME_HEADER      *Fv;
  EFI_FIRMWARE_VOLUME_EXT_HEADER  *ExtHeader;
  EFI_FFS_FILE_HEADER             *File;
  EFI_COMMON_SECTION_HEADER       *Section;
  UINT8                           *Src;
  UINT8                           *Dst;
  UINTN                           Offset;
  UINTN                           FileSize;
  UINTN                           SectionSize;
  UINTN                           FvLength;
  UINTN                           CopySize;

  Fv       = (EFI_FIRMWARE_VOLUME_HEADER *)(UINTN)FvBase;
  FvLength = Fv->FvLength;

  if (Fv->Signature != EFI_FVH_SIGNATURE) {
    return 0;
  }

  /* The FFS chain starts behind the volume extension header, which is written
     past HeaderLength (GenFv pads the gap with a FFS pad file).  Follow the
     same rule the FV driver uses so the walk never starts inside header
     bytes. */
  if (Fv->ExtHeaderOffset != 0) {
    ExtHeader = (EFI_FIRMWARE_VOLUME_EXT_HEADER *)((UINT8 *)(UINTN)FvBase + Fv->ExtHeaderOffset);
    Offset    = Fv->ExtHeaderOffset + ExtHeader->ExtHeaderSize;
  } else {
    Offset = Fv->HeaderLength;
  }

  while (Offset + sizeof (EFI_FFS_FILE_HEADER) < FvLength) {
    Offset   = (Offset + 7) & ~(UINTN)7;
    File     = (EFI_FFS_FILE_HEADER *)((UINT8 *)(UINTN)FvBase + Offset);
    FileSize = File->Size[0] | (File->Size[1] << 8) | (File->Size[2] << 16);
    if (FileSize < sizeof (EFI_FFS_FILE_HEADER)) {
      break;
    }

    if ((File->Type == EFI_FV_FILETYPE_FREEFORM) &&
        CompareGuid (&File->Name, &mDtbFileGuid))
    {
      Section     = (EFI_COMMON_SECTION_HEADER *)(File + 1);
      SectionSize = Section->Size[0] | (Section->Size[1] << 8) | (Section->Size[2] << 16);
      if ((Section->Type == EFI_SECTION_RAW) &&
          (SectionSize > sizeof (EFI_COMMON_SECTION_HEADER)))
      {
        Src      = (UINT8 *)Section + sizeof (EFI_COMMON_SECTION_HEADER);
        CopySize = SectionSize - sizeof (EFI_COMMON_SECTION_HEADER);

        /* Only accept a real flattened device tree. */
        if ((CopySize < 8) ||
            (Src[0] != 0xd0) || (Src[1] != 0x0d) ||
            (Src[2] != 0xfe) || (Src[3] != 0xed))
        {
          break;
        }

        Dst = (UINT8 *)(UINTN)Destination;
        while (CopySize-- != 0) {
          *Dst++ = *Src++;
        }

        return SectionSize - sizeof (EFI_COMMON_SECTION_HEADER);
      }

      break;
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

  /* The clock stage has run since the SEC console was programmed, so both
     ports still carry the pre-PLL divisor; put them on the 125 MHz APB clock
     before the first character written from here on. */
  EarlySerialInitAt125M ();

  DtbSize = CopyDtbFromFv (
              (EFI_PHYSICAL_ADDRESS)FixedPcdGet64 (PcdOvmfFdBaseAddress),
              (EFI_PHYSICAL_ADDRESS)FixedPcdGet64 (PcdDeviceTreeInitialBaseAddress)
              );

  LoongsonBootLogEvent (BOOTLOG_SEC_DTB, (UINT32)DtbSize);

  if (DtbSize == 0) {
    EarlyPutString ("WARNING: DTB not found in firmware volume!\r\n");
  }
}

/**
  Pre-memory SEC initialization. Called from Start.S with the stack in PMON's
  pre-DRAM stack region - the locked 256 KB of scache, top at PREMEM_STACK_TOP
  (see the note there; the region is probed over the buzzer immediately before
  this call).  PMON's own early stage uses no stack at all.
  Clock and DDR assembly stages are invoked from Start.S directly because
  they deliberately clobber callee-saved registers.
**/
UINT64
EFIAPI
PreMemInit (
  VOID
  )
{
  UINT32  PinMux;
  UINT32  Mux0;
  UINT32  Mux1;

  /* Order matters, and it is the factory PMON's order: the UART sits behind
     the APB window that ApbBarConfig() opens, so initialising or printing
     before that writes into an unrouted address and the output is lost.  The
     SPI controller needs no BAR (PMON pokes it, at dump offsets 0x00-0x18,
     before it configures one; this board's factory image runs that way), so
     the speedup may come before the BAR.  Start.S opens the same BAR before
     its three clicks, so this call is normally a repeat of an already
     configured window. */
  /*
   * Record progress before anything that could hang.  The flash log is the one
   * channel that survives a board with no serial console and a buzzer too slow
   * to hear, and it goes through the SPI command engine -- which needs no APB
   * window, so it can run first.
   */
  LoongsonBootLogBoot ();
  LoongsonBootLogEvent (BOOTLOG_SEC_ENTRY, 0);
  LoongsonBootLogEvent (BOOTLOG_SEC_SPI, 0);

  ApbBarConfig ();
  WatchdogClose ();

  /*
   * The console comes up before anything else that can fail, on both ports:
   * UART0 on the RS232 pins and UART3 on the LVTTL header (8 = TX, 10 = RX,
   * 9 = GND), so a plain USB-serial adapter on the TTL pins sees every message
   * from the first one onwards.  Everything after this point that can wedge --
   * the buzzer, the flash marks -- is downstream of a line that has already
   * been printed, so its failure can no longer be mistaken for a dead board.
   */
  EarlySerialInit ();
  /* The banner is the only in-band version marker this image has, and the one
     channel a totally silent board would use to say anything at all.  It must
     therefore name the image that is actually in the chip: v16 is the round
     that fixed CRMD (BOOT_CRMD), the APB window before the clicks, the UART
     mux register (0x1FE00428), the mark address (0x36F000) and the unbounded
     waits.  A board that answers "v15" here is running the never-flashed
     working tree, not this image -- see docs/BRINGUP.md, "v16" section. */
  EarlyPutString ("\r\n\r\n=== LS2K1000LA EDK2 SEC [v16] ===\r\n");
  EarlyPutString ("APB BAR, watchdog: done; UART mux not yet written\r\n");

  /*
   * SPI speedup moved after the first line: it writes the controller this code
   * is executing from, and the console must be able to report it if that ever
   * goes wrong.  PMON writes the same byte as its third instruction and is fine,
   * so this is ordering, not suspicion.
   */
  SpiFlashSpeedup ();
  EarlyPutString ("SPI speedup done\r\n");
  /* The same two LSR reads as after the mux write below, but under the reset
     value of CFG1: together they separate "the mux write killed the console"
     from "the console never worked". */
  EarlyPutString ("LSR0=0x");
  EarlyPutHex8 (MmioRead8 (UART0 + 5));
  EarlyPutString (" LSR3=0x");
  EarlyPutHex8 (MmioRead8 (UART0_MIRROR + 5));
  EarlyPutString ("\r\n");

  /*
   * Order experiment: the pin-mux write used to happen before the first
   * character, so a mux write that kills the console -- the board has one old
   * observation of writing 0x3 doing exactly that (see UartPinMuxInit) --
   * would leave an image that is silent for a reason no test can reach.  First
   * line under the reset value of CFG1, then the write, then the readback
   * line.  The values are unchanged: 0xF is the factory's running state.
   */
  UartPinMuxInit ();

  /* Read both mux registers back.  CFG1[3:0] (uart0_enable) is the field that
     decides which UART controllers reach the pin group, so that nibble is
     what goes into the boot log as the pin-mux evidence; CFG0 is kept for the
     serial readback below. */
  Mux0   = MmioRead32 (SYSCONF (SYSCONF_CFG0));
  Mux1   = MmioRead32 (SYSCONF (SYSCONF_CFG1));
  PinMux = Mux1 & CFG1_UART0_ENABLE_MASK;
  /* Make the readback line self-describing: CFG1's low nibble proves the UART
     pin-mux write landed (0x1 = nothing was written, 0xF = the factory 2-wire
     mode), and the two LSR reads separate "controller present" (bit 5 =
     transmitter FIFO empty, 0x20) from "this port is not decoded at all"
     (0x00 / 0xFF) - the two states a silent console leaves indistinguishable.
     Reading LSR clears only bits [4:1] and [7] (manual 15.4.7, table 15-9,
     printed page 125), so it does not disturb the status polling. */
  EarlyPutString ("CFG0=0x");
  EarlyPutHex32 (Mux0);
  EarlyPutString (" CFG1=0x");
  EarlyPutHex32 (Mux1);
  EarlyPutString (" LSR0=0x");
  EarlyPutHex8 (MmioRead8 (UART0 + 5));
  EarlyPutString (" LSR3=0x");
  EarlyPutHex8 (MmioRead8 (UART0_MIRROR + 5));
  EarlyPutString ("\r\n");

  /* Audible progress, part 1: one beep means the firmware runs and the SoC
     window is open.  The buzzer needs neither the UART nor the display, so it
     is the one channel that works on an otherwise silent board. */
  LoongsonBootBeep (1);
  EarlyPutString ("first beep done\r\n");

  /* Mark LS2K_MARK_A2: the C environment was entered and ran this far.  The
     message is guarded, not just the call: with the marks compiled out
     (BOOTMARK_FLASH_ENABLE = 0, LoongsonBootLog.h) printing "written" would
     assert a flash write that never happened. */
  LoongsonBootMark (LS2K_MARK_A2, 0xa2);
#if BOOTMARK_FLASH_ENABLE
  EarlyPutString ("flash mark A2 written\r\n");
#else
  EarlyPutString ("flash mark A2 compiled out (BOOTMARK_FLASH_ENABLE=0)\r\n");
#endif

  /*
   * A scale to find the pitch this board's buzzer is actually loud at.  It
   * needs only the GPIO block, which by now is reachable: the APB window is
   * open (ApbBarConfig above, and Start.S before the clicks).  PMON reaches
   * GPIO the same way - its watchdog_close() is the first GPIO touch and it
   * follows the APB BAR writes.
   */
  LoongsonBootBeepScale ();
  EarlyPutString ("buzzer scale played\r\n");

  /* Mark LS2K_MARK_A3: the UART is up, so APB routing and pin muxing worked. */
  LoongsonBootMark (LS2K_MARK_A3, 0xa3);
#if BOOTMARK_FLASH_ENABLE
  EarlyPutString ("flash mark A3 written\r\n");
#else
  EarlyPutString ("flash mark A3 compiled out (BOOTMARK_FLASH_ENABLE=0)\r\n");
#endif

  EarlyPutString ("PCIe early config...\r\n");
  PcieEarlyConf ();
  EarlyPutString ("PCIe early config done\r\n");

  /* Audible progress, part 2: the console is alive. */
  LoongsonBootBeep (2);
  EarlyPutString ("SEC stage finished, clock stage next\r\n");

  /* The rest of the SEC phase lands in the log as it happens. */
  LoongsonBootLogEvent (BOOTLOG_SEC_APB, 0);
  LoongsonBootLogEvent (BOOTLOG_SEC_PINMUX, PinMux);
  LoongsonBootLogEvent (BOOTLOG_SEC_WATCHDOG, 0);
  LoongsonBootLogEvent (BOOTLOG_SEC_UART, 0);
  LoongsonBootLogEvent (BOOTLOG_SEC_PCIE, 0);
  LoongsonBootLogEvent (BOOTLOG_SEC_SOC_DONE, 0);

  return 0;
}
