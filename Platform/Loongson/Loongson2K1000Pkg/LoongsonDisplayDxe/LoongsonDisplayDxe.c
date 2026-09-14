/** @file
  Loongson 2K1000LA display (DC + SII9022A HDMI) GOP driver.

  Brings up the on-chip display controller (DC0 -> DVO0 -> SII9022A HDMI
  transmitter on I2C1 @ 0x1fe21800) at 1024x768-32@60, allocates a
  framebuffer, publishes EFI_GRAPHICS_OUTPUT_PROTOCOL and paints the
  platform boot logo so the panel/HDMI shows output from firmware on.

  Register programming ported from Loongson PMON (Targets/ls2k/dev/dc.c,
  dev/9022a.c, dev/i2c.c, BSD licensed).

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <PiDxe.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/CacheMaintenanceLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PcdLib.h>
#include <Library/PciLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>

#include <Guid/EventGroup.h>
#include <Protocol/GraphicsOutput.h>
#include <Protocol/PciEnumerationComplete.h>

#include "LoongsonLogo.h"

#define LS_MMIO_UNCACHED(Base)  (0x9000000000000000ULL | (UINT64)(Base))

/* ---------------- hardware constants (PMON port) ---------------- */

#define LS2K_I2C1_BASE          0x1fe21800  /* SII9022A sits on this bus */
#define SII9022A_ADDR           0x39        /* (0x72 / 2) */

#define LS2K_PIXCLK0_CTRL0      0x1fe004b0  /* pixel PLL 0 (DVO0) */
#define LS2K_PIXCLK1_CTRL0      0x1fe004c0  /* pixel PLL 1 (DVO1) */

#define DC_DVO0_OFF             0x1240
#define DC_DVO1_OFF             0x1250

/* buffer/pipe register offsets within one DVO block */
#define OF_BUF_CONFIG           0x000
#define OF_BUF_ADDR             0x020
#define OF_BUF_STRIDE           0x040
#define OF_DITHER_CONFIG        0x120
#define OF_PAN_CONFIG           0x180
#define OF_PAN_TIMING           0x1a0
#define OF_HDISPLAY             0x1c0
#define OF_HSYNC                0x1e0
#define OF_VDISPLAY             0x240
#define OF_VSYNC                0x260
#define OF_DBLBUF               0x340

/* opencores I2C registers/commands */
#define I2C_PRER_LO             0x0
#define I2C_PRER_HI             0x1
#define I2C_CTR                 0x2
#define I2C_TXR                 0x3
#define I2C_RXR                 0x3
#define I2C_CR                  0x4
#define I2C_SR                  0x4

#define CR_START                0x80
#define CR_STOP                 0x40
#define CR_READ                 0x20
#define CR_WRITE                0x10
#define CR_IACK                 0x01
#define CR_ACK                  0x08
#define SR_NOACK                0x80
#define SR_BUSY                 0x40
#define SR_TIP                  0x02

/* 1024x768@60 timing, verbatim from the PMON mode table */
#define MODE_HR                 1024
#define MODE_VR                 768
#define MODE_HSS                1080
#define MODE_HSE                1184
#define MODE_HFL                1344
#define MODE_VSS                769
#define MODE_VSE                772
#define MODE_VFL                795
#define MODE_PCLK_KHZ           64110

#define MODE_STRIDE             ((MODE_HR * 4 + 255) & ~255)   /* 4096 */

/* ---------------- state ---------------- */

STATIC UINT32           *mFrameBuffer;   /* cached VA */
STATIC EFI_PHYSICAL_ADDRESS mFbPhys;     /* DC scanout address */
STATIC UINTN             mDcBase;         /* uncached DC MMIO base */
STATIC EFI_EVENT         mExitBootEvent;

STATIC EFI_GRAPHICS_OUTPUT_PROTOCOL           mGop;
STATIC EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE      mGopMode;
STATIC EFI_GRAPHICS_OUTPUT_MODE_INFORMATION    mGopInfo;

/* ---------------- opencores I2C (PMON i2c.c port) ---------------- */

STATIC inline VOID I2cWriteReg (UINTN Off, UINT8 Val)
{
  MmioWrite8 (LS_MMIO_UNCACHED (LS2K_I2C1_BASE) + Off, Val);
}

STATIC inline UINT8 I2cReadReg (UINTN Off)
{
  return MmioRead8 (LS_MMIO_UNCACHED (LS2K_I2C1_BASE) + Off);
}

STATIC VOID I2cStop (VOID)
{
  for (;;) {
    I2cWriteReg (I2C_CR, CR_STOP);
    I2cReadReg (I2C_SR);
    if ((I2cReadReg (I2C_SR) & SR_BUSY) == 0) {
      break;
    }
  }
}

STATIC BOOLEAN I2cStart (UINT8 DevAddr, BOOLEAN Read)
{
  UINTN  Retry = 5;
  UINT8  Addr  = (UINT8)((DevAddr & 0x7f) << 1) | (Read ? 1 : 0);

  for ( ; ; ) {
    I2cWriteReg (I2C_TXR, Addr);
    I2cWriteReg (I2C_CR, CR_START | CR_WRITE);
    while (I2cReadReg (I2C_SR) & SR_TIP) {
    }
    if ((I2cReadReg (I2C_SR) & SR_NOACK) == 0) {
      return TRUE;
    }
    I2cStop ();
    if (Retry-- == 0) {
      return FALSE;
    }
  }
}

STATIC BOOLEAN I2cWriteBytes (CONST UINT8 *Buf, UINTN Count)
{
  UINTN  Idx;

  for (Idx = 0; Idx < Count; Idx++) {
    I2cWriteReg (I2C_TXR, Buf[Idx]);
    I2cWriteReg (I2C_CR, CR_WRITE);
    while (I2cReadReg (I2C_SR) & SR_TIP) {
    }
    if (I2cReadReg (I2C_SR) & SR_NOACK) {
      I2cStop ();
      return FALSE;
    }
  }
  return TRUE;
}

STATIC VOID I2cReadBytes (UINT8 *Buf, UINTN Count)
{
  UINTN  Idx;

  for (Idx = 0; Idx < Count; Idx++) {
    I2cWriteReg (I2C_CR, (Idx == Count - 1) ? (CR_READ | CR_ACK) : CR_READ);
    while (I2cReadReg (I2C_SR) & SR_TIP) {
    }
    Buf[Idx] = I2cReadReg (I2C_RXR);
  }
}

STATIC VOID LsI2cInit (VOID)
{
  I2cWriteReg (I2C_CTR, 0);
  I2cWriteReg (I2C_PRER_LO, 0x64);
  I2cWriteReg (I2C_PRER_HI, 0x04);
  I2cWriteReg (I2C_CTR, 0x80);
}

/* SMBus-style write: [reg] [val] */
STATIC BOOLEAN SiiWrite8 (UINT8 Reg, UINT8 Val)
{
  UINT8  Buf[2];

  if (!I2cStart (SII9022A_ADDR, FALSE)) {
    return FALSE;
  }
  Buf[0] = Reg;
  Buf[1] = Val;
  if (!I2cWriteBytes (Buf, 2)) {
    return FALSE;
  }
  I2cStop ();
  return TRUE;
}

/* SMBus-style read-modify-write */
STATIC BOOLEAN SiiRmw8 (UINT8 Reg, UINT8 AndMask, UINT8 OrValue)
{
  UINT8  Buf[1];
  UINT8  Val;

  if (!I2cStart (SII9022A_ADDR, FALSE)) {
    return FALSE;
  }
  Buf[0] = Reg;
  if (!I2cWriteBytes (Buf, 1)) {
    return FALSE;
  }
  if (!I2cStart (SII9022A_ADDR, TRUE)) {
    return FALSE;
  }
  I2cReadBytes (Buf, 1);
  I2cStop ();
  Val = (UINT8)((Buf[0] & AndMask) | OrValue);
  return SiiWrite8 (Reg, Val);
}

/**
  Init the SII9022A DVO->HDMI transmitter (PMON 9022a.c sequence).
**/
STATIC BOOLEAN Sii9022aInit (VOID)
{
  UINT8  Id0;
  UINT8  Id1;
  UINT8  Id2;

  LsI2cInit ();

  SiiWrite8 (0xc7, 0x00);           /* power up */

  if (!I2cStart (SII9022A_ADDR, FALSE)) {
    return FALSE;
  }
  {
    UINT8  Buf[1];

    Buf[0] = 0x1b;
    I2cWriteBytes (Buf, 1);
    if (!I2cStart (SII9022A_ADDR, TRUE)) {
      return FALSE;
    }
    I2cReadBytes (&Id0, 1);
    I2cStop ();
  }
  if (!I2cStart (SII9022A_ADDR, FALSE)) {
    return FALSE;
  }
  {
    UINT8  Buf[1];

    Buf[0] = 0x1c;
    I2cWriteBytes (Buf, 1);
    if (!I2cStart (SII9022A_ADDR, TRUE)) {
      return FALSE;
    }
    I2cReadBytes (&Id1, 1);
    I2cStop ();
  }
  if (!I2cStart (SII9022A_ADDR, FALSE)) {
    return FALSE;
  }
  {
    UINT8  Buf[1];

    Buf[0] = 0x1d;
    I2cWriteBytes (Buf, 1);
    if (!I2cStart (SII9022A_ADDR, TRUE)) {
      return FALSE;
    }
    I2cReadBytes (&Id2, 1);
    I2cStop ();
  }

  if ((Id0 != 0xb0) || (Id1 != 0x02) || (Id2 != 0x03)) {
    DEBUG ((DEBUG_WARN, "%a: SII9022A id mismatch %02x %02x %02x\n", __func__, Id0, Id1, Id2));
    return FALSE;
  }

  SiiRmw8 (0x1e, (UINT8)~0x03, 0x00);
  SiiRmw8 (0x1a, (UINT8)~(1 << 4), 0x00);

  return TRUE;
}

/* ---------------- pixel PLL + DC programming (PMON dc.c port) ---------------- */

STATIC VOID Write64 (UINTN Base, UINT64 Val)
{
  MmioWrite64 (Base, Val);
}

/**
  Program one pixel PLL. Register layout per PMON config_pll().
**/
STATIC VOID ConfigPixPll (UINTN Base, UINTN Loopc, UINTN Frefc, UINTN Pstdiv)
{
  UINT64  Out;

  Out = (1ULL << 7) | (1ULL << 42) | (3ULL << 10) |
        ((UINT64)Loopc << 32) | ((UINT64)Frefc << 26);

  Write64 (Base + 0, 0);
  Write64 (Base + 0, 1ULL << 19);
  Write64 (Base + 0, Out);
  Write64 (Base + 8, Pstdiv);
  Out |= (1ULL << 2);
  Write64 (Base + 0, Out);

  while ((MmioRead64 (Base) & 0x10000) == 0) {
  }

  Write64 (Base + 0, Out | 1);
}

/**
  Search pixel PLL parameters (PMON cal_freq, kHz domain).
**/
STATIC BOOLEAN CalPixPll (UINT32 PixclockKHz, OUT UINTN *Loopc, OUT UINTN *Frefc, OUT UINTN *Pstdiv)
{
  UINTN       A, B, C;
  UINT64      Min;
  UINTN       Pst, Refc, Loop;
  BOOLEAN     Found = FALSE;

  Min = 1000;
  for (Pst = 1; Pst < 64; Pst++) {
    A = (UINTN)PixclockKHz * Pst;
    for (Refc = 3; Refc < 6; Refc++) {
      for (Loop = 24; Loop < 161; Loop++) {
        if ((Loop < 12 * Refc) || (Loop > 32 * Refc)) {
          continue;
        }
        B = 100000UL * Loop / Refc;
        C = (A > B) ? (A - B) : (B - A);
        if (C < Min) {
          Min   = C;
          *Pstdiv = Pst;
          *Loopc  = Loop;
          *Frefc  = Refc;
          Found   = TRUE;
        }
      }
    }
  }
  return Found;
}

STATIC VOID ConfigPipe (UINTN Pipe, EFI_PHYSICAL_ADDRESS FbPhys)
{
  UINTN  Base = mDcBase + Pipe;

  MmioWrite32 (Base + OF_BUF_CONFIG, 0x00000000);
  /* 32bpp X8R8G8B8 */
  MmioWrite32 (Base + OF_BUF_CONFIG, 0x00100104);
  MmioWrite32 (Base + OF_BUF_ADDR, (UINT32)FbPhys);
  MmioWrite32 (Base + OF_DBLBUF, (UINT32)FbPhys);
  MmioWrite32 (Base + OF_DITHER_CONFIG, 0x00000000);
  MmioWrite32 (Base + OF_PAN_CONFIG, 0x80001311);
  MmioWrite32 (Base + OF_PAN_TIMING, 0x00000000);

  MmioWrite32 (Base + OF_HDISPLAY, (MODE_HFL << 16) | MODE_HR);
  MmioWrite32 (Base + OF_HSYNC, 0x40000000u | (MODE_HSE << 16) | MODE_HSS);
  MmioWrite32 (Base + OF_VDISPLAY, (MODE_VFL << 16) | MODE_VR);
  MmioWrite32 (Base + OF_VSYNC, 0x40000000u | (MODE_VSE << 16) | MODE_VSS);

  MmioWrite32 (Base + OF_BUF_CONFIG, 0x00100104);
  MmioWrite32 (Base + OF_BUF_STRIDE, MODE_STRIDE);
}

/* ---------------- logo ---------------- */

/**
  Paint the boot logo centered on the framebuffer (2x nearest scaling of
  the 512x256 source so it fills 1024x512 of the 1024x768 panel).
**/
STATIC VOID PaintLogo (VOID)
{
  UINT32  Y;
  UINT32  X;
  UINT32  OffX = 0;
  UINT32  OffY = (MODE_VR - LOGO_HEIGHT * 2) / 2;

  //
  // Dark navy backdrop matching the logo artwork.
  //
  for (Y = 0; Y < MODE_VR; Y++) {
    UINT32  *Line = mFrameBuffer + (UINTN)Y * (MODE_STRIDE / 4);
    UINT8   T     = (UINT8)(Y * 255 / MODE_VR);
    UINT32  Pix   = 0xFF000000u |
                    ((UINT32)(10 + (34 - 10) * T / 255) << 16) |
                    ((UINT32)(14 + (26 - 14) * T / 255) << 8) |
                    (UINT32)(38 + (90 - 38) * T / 255);
    for (X = 0; X < MODE_HR; X++) {
      Line[X] = Pix;
    }
  }

  for (Y = 0; Y < LOGO_HEIGHT; Y++) {
    CONST UINT32  *Src = &mLoongsonLogo[Y * LOGO_WIDTH];
    UINT32        *Dst = mFrameBuffer + (UINTN)(OffY + Y * 2) * (MODE_STRIDE / 4) + OffX;
    for (X = 0; X < LOGO_WIDTH; X++) {
      UINT32  Pix = Src[X];
      UINT32  R   = (Pix >> 16) & 0xff;
      UINT32  G   = (Pix >> 8) & 0xff;
      UINT32  B   = Pix & 0xff;
      UINT32  Out = (R << 16) | (G << 8) | B;
      Dst[X * 2]        = Out;
      Dst[X * 2 + 1]    = Out;
      Dst[(MODE_STRIDE / 4) + X * 2]     = Out;
      Dst[(MODE_STRIDE / 4) + X * 2 + 1] = Out;
    }
  }

  WriteBackInvalidateDataCacheRange (mFrameBuffer, MODE_STRIDE * MODE_VR);
}

/* ---------------- GOP ---------------- */

STATIC EFI_STATUS EFIAPI
GopQueryMode (
  IN  EFI_GRAPHICS_OUTPUT_PROTOCOL                   *This,
  IN  UINT32                                         ModeNumber,
  OUT UINTN                                          *SizeOfInfo,
  OUT EFI_GRAPHICS_OUTPUT_MODE_INFORMATION           **Info
  )
{
  if ((Info == NULL) || (SizeOfInfo == NULL) || (ModeNumber >= 1)) {
    return EFI_INVALID_PARAMETER;
  }

  *SizeOfInfo = sizeof (mGopInfo);
  *Info       = AllocateCopyPool (sizeof (mGopInfo), &mGopInfo);
  if (*Info == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }

  return EFI_SUCCESS;
}

STATIC EFI_STATUS EFIAPI
GopSetMode (IN EFI_GRAPHICS_OUTPUT_PROTOCOL  *This, IN UINT32  ModeNumber)
{
  if (ModeNumber >= 1) {
    return EFI_UNSUPPORTED;
  }

  ConfigPipe (DC_DVO0_OFF, mFbPhys);
  ConfigPipe (DC_DVO1_OFF, mFbPhys);
  PaintLogo ();

  mGopMode.Mode = 0;
  return EFI_SUCCESS;
}

STATIC EFI_STATUS EFIAPI
GopBlt (
  IN  EFI_GRAPHICS_OUTPUT_PROTOCOL       *This,
  IN  EFI_GRAPHICS_OUTPUT_BLT_PIXEL      *BltBuffer OPTIONAL,
  IN  EFI_GRAPHICS_OUTPUT_BLT_OPERATION  BltOperation,
  IN  UINTN                              SourceX,
  IN  UINTN                              SourceY,
  IN  UINTN                              DestinationX,
  IN  UINTN                              DestinationY,
  IN  UINTN                              Width,
  IN  UINTN                              Height,
  IN  UINTN                              Delta OPTIONAL
  )
{
  UINT32  *Src;
  UINT32  *Dst;
  UINTN   Y;

  if ((BltOperation < EfiBltVideoFill) || (BltOperation > EfiBltVideoToVideo)) {
    return EFI_INVALID_PARAMETER;
  }

  switch (BltOperation) {
    case EfiBltVideoFill:
      if (Delta != 0) {
        return EFI_INVALID_PARAMETER;
      }
      for (Y = 0; Y < Height; Y++) {
        UINT32  *Line = mFrameBuffer + (DestinationY + Y) * (MODE_STRIDE / 4) + DestinationX;
        UINTN   X;
        for (X = 0; X < Width; X++) {
          UINT32  Pix   = *(UINT32 *)BltBuffer;
          Line[X] = ((Pix >> 16) & 0xff) | (Pix & 0x00ff00) | ((Pix & 0xff) << 16);
        }
      }
      break;

    case EfiBltVideoToBltBuffer:
      if (Delta == 0) {
        Delta = Width * sizeof (EFI_GRAPHICS_OUTPUT_BLT_PIXEL);
      }
      for (Y = 0; Y < Height; Y++) {
        Src = mFrameBuffer + (SourceY + Y) * (MODE_STRIDE / 4) + SourceX;
        Dst = (UINT32 *)((UINT8 *)BltBuffer + (DestinationY + Y) * Delta) + DestinationX;
        for (UINTN X = 0; X < Width; X++) {
          UINT32  Pix = Src[X];
          Dst[X] = ((Pix >> 16) & 0xff) | (Pix & 0x00ff00) | ((Pix & 0xff) << 16);
        }
      }
      break;

    case EfiBltBufferToVideo:
      if (Delta == 0) {
        Delta = Width * sizeof (EFI_GRAPHICS_OUTPUT_BLT_PIXEL);
      }
      for (Y = 0; Y < Height; Y++) {
        Src = (UINT32 *)((UINT8 *)BltBuffer + (SourceY + Y) * Delta) + SourceX;
        Dst = mFrameBuffer + (DestinationY + Y) * (MODE_STRIDE / 4) + DestinationX;
        for (UINTN X = 0; X < Width; X++) {
          UINT32  Pix = Src[X];
          Dst[X] = ((Pix >> 16) & 0xff) | (Pix & 0x00ff00) | ((Pix & 0xff) << 16);
        }
      }
      WriteBackInvalidateDataCacheRange (
        mFrameBuffer + DestinationY * (MODE_STRIDE / 4) + DestinationX,
        Width * 4 * Height
        );
      break;

    case EfiBltVideoToVideo:
      for (Y = 0; Y < Height; Y++) {
        UINT32  *SrcL = mFrameBuffer + (SourceY + Y) * (MODE_STRIDE / 4) + SourceX;
        UINT32  *DstL = mFrameBuffer + (DestinationY + Y) * (MODE_STRIDE / 4) + DestinationX;
        CopyMem (DstL, SrcL, Width * 4);
      }
      WriteBackInvalidateDataCacheRange (mFrameBuffer, MODE_STRIDE * MODE_VR);
      break;

    default:
      return EFI_INVALID_PARAMETER;
  }

  return EFI_SUCCESS;
}

STATIC VOID EFIAPI
OnExitBootServices (IN EFI_EVENT Event, IN VOID *Context)
{
  //
  // Stop scanout before the framebuffer memory ownership changes.
  //
  MmioWrite32 (mDcBase + DC_DVO0_OFF + OF_BUF_CONFIG, 0);
  MmioWrite32 (mDcBase + DC_DVO1_OFF + OF_BUF_CONFIG, 0);
}

/* ---------------- driver entry ---------------- */

EFI_STATUS
EFIAPI
LoongsonDisplayDxeEntryPoint (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS  Status;
  UINT32      Bar0;
  UINTN       Loopc, Frefc, Pstdiv;
  EFI_HANDLE  Handle;

  //
  // DC is PCI device 0:6:0; take its MMIO BAR0 (PMON reads the same BAR).
  //
  Bar0 = PciRead32 (PCI_LIB_ADDRESS (0, 6, 0, 0x10));
  if ((Bar0 & 0xfffffff0u) == 0 || (Bar0 & 0xfffffff0u) == 0xfffffff0u) {
    DEBUG ((DEBUG_WARN, "%a: DC BAR0 unprogrammed (%08x), assuming 0x1f010000\n", __func__, Bar0));
    mDcBase = LS_MMIO_UNCACHED (0x1f010000);
  } else {
    mDcBase = LS_MMIO_UNCACHED (Bar0 & 0xfffffff0u);
  }

  if (!CalPixPll (MODE_PCLK_KHZ, &Loopc, &Frefc, &Pstdiv)) {
    DEBUG ((DEBUG_ERROR, "%a: pixel PLL search failed\n", __func__));
    return EFI_UNSUPPORTED;
  }

  ConfigPixPll (LS_MMIO_UNCACHED (LS2K_PIXCLK0_CTRL0), Loopc, Frefc, Pstdiv);
  ConfigPixPll (LS_MMIO_UNCACHED (LS2K_PIXCLK1_CTRL0), Loopc, Frefc, Pstdiv);

  //
  // 1024x768x4 = 3 MiB scanout buffer.
  //
  mFbPhys = EFI_PAGE_MASK + 1;
  Status  = gBS->AllocatePages (
                   AllocateAnyPages,
                   EfiBootServicesData,
                   EFI_SIZE_TO_PAGES ((UINTN)MODE_STRIDE * MODE_VR),
                   &mFbPhys
                   );
  if (EFI_ERROR (Status)) {
    return Status;
  }

  mFrameBuffer = (UINT32 *)(UINTN)mFbPhys;
  ZeroMem (mFrameBuffer, (UINTN)MODE_STRIDE * MODE_VR);

  if (!Sii9022aInit ()) {
    DEBUG ((DEBUG_WARN, "%a: SII9022A not found on I2C1; continuing with DC only\n", __func__));
  }

  mGopInfo.Version                    = 0;
  mGopInfo.HorizontalResolution       = MODE_HR;
  mGopInfo.VerticalResolution         = MODE_VR;
  mGopInfo.PixelFormat                = PixelBlueGreenRedReserved8BitPerColor;
  mGopInfo.PixelsPerScanLine          = MODE_STRIDE / 4;
  mGopInfo.PixelInformation.RedMask   = 0x00ff0000;
  mGopInfo.PixelInformation.GreenMask = 0x0000ff00;
  mGopInfo.PixelInformation.BlueMask  = 0x000000ff;
  mGopInfo.PixelInformation.ReservedMask = 0xff000000;

  mGopMode.MaxMode         = 1;
  mGopMode.Mode            = 0;
  mGopMode.Info            = &mGopInfo;
  mGopMode.SizeOfInfo      = sizeof (mGopInfo);
  mGopMode.FrameBufferBase = mFbPhys;
  mGopMode.FrameBufferSize = (UINTN)MODE_STRIDE * MODE_VR;

  mGop.QueryMode = GopQueryMode;
  mGop.SetMode   = GopSetMode;
  mGop.Blt       = GopBlt;
  mGop.Mode      = &mGopMode;

  GopSetMode (&mGop, 0);

  Status = gBS->InstallMultipleProtocolInterfaces (
                  &Handle,
                  &gEfiGraphicsOutputProtocolGuid,
                  &mGop,
                  NULL
                  );
  if (EFI_ERROR (Status)) {
    return Status;
  }

  Status = gBS->CreateEventEx (
                  EVT_NOTIFY_SIGNAL,
                  TPL_CALLBACK,
                  OnExitBootServices,
                  NULL,
                  &gEfiEventExitBootServicesGuid,
                  &mExitBootEvent
                  );
  if (EFI_ERROR (Status)) {
    gBS->UninstallMultipleProtocolInterfaces (Handle, &gEfiGraphicsOutputProtocolGuid, &mGop, NULL);
    return Status;
  }

  DEBUG ((DEBUG_INFO, "%a: DC@%lx fb=%lx GOP ready (1024x768-32)\n", __func__, mDcBase, mFbPhys));
  return EFI_SUCCESS;
}
