/** @file
  PCI Library for Loongson 2K1000LA.

  The 2K1000LA PCIe controllers use a Loongson-style "compressed ECAM":
    cfg = 0xFE00000000 + (bus << 21) + (device << 11) + (function << 8) + reg

  (2MB per bus, 1KB per function; confirmed against both the device tree
  window size 0x20000000 for 256 buses and PMON's root port access at
  0xfe0800000c.)

  Segment 0 only. The CF8 family is not available on this platform and is
  redirected to the memory mapped form.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include <Library/PciLib.h>

/**
  Convert PCI Lib address (PCI_LIB_ADDRESS encoding) to the Loongson
  configuration space MMIO address.
**/
STATIC
UINTN
LoongsonPciConfigAddress (
  IN UINTN  Address
  )
{
  UINTN  Bus;
  UINTN  Device;
  UINTN  Function;
  UINTN  Register;

  Bus      = (Address >> 20) & 0xff;
  Device   = (Address >> 15) & 0x1f;
  Function = (Address >> 12) & 0x7;
  Register = Address & 0xfff;

  return (UINTN)(0x9000000000000000ULL | (UINT64)FixedPcdGet64 (PcdLoongsonPciConfigBaseAddress)) +
         (Bus << 21) + (Device << 11) + (Function << 8) + Register;
}

/**
  Read an 8-bit PCI configuration register.
**/
UINT8
EFIAPI
PciRead8 (
  IN UINTN  Address
  )
{
  return MmioRead8 (LoongsonPciConfigAddress (Address));
}

/**
  Write an 8-bit PCI configuration register.
**/
UINT8
EFIAPI
PciWrite8 (
  IN UINTN  Address,
  IN UINT8  Value
  )
{
  return MmioWrite8 (LoongsonPciConfigAddress (Address), Value);
}

UINT8
EFIAPI
PciOr8 (
  IN UINTN  Address,
  IN UINT8  OrData
  )
{
  return MmioWrite8 (LoongsonPciConfigAddress (Address), (UINT8)(MmioRead8 (LoongsonPciConfigAddress (Address)) | OrData));
}

UINT8
EFIAPI
PciAnd8 (
  IN UINTN  Address,
  IN UINT8  AndData
  )
{
  return MmioWrite8 (LoongsonPciConfigAddress (Address), (UINT8)(MmioRead8 (LoongsonPciConfigAddress (Address)) & AndData));
}

UINT8
EFIAPI
PciAndThenOr8 (
  IN UINTN  Address,
  IN UINT8  AndData,
  IN UINT8  OrData
  )
{
  return MmioWrite8 (LoongsonPciConfigAddress (Address), (UINT8)((MmioRead8 (LoongsonPciConfigAddress (Address)) & AndData) | OrData));
}

UINT16
EFIAPI
PciRead16 (
  IN UINTN  Address
  )
{
  return MmioRead16 (LoongsonPciConfigAddress (Address));
}

UINT16
EFIAPI
PciWrite16 (
  IN UINTN  Address,
  IN UINT16  Value
  )
{
  return MmioWrite16 (LoongsonPciConfigAddress (Address), Value);
}

UINT16
EFIAPI
PciOr16 (
  IN UINTN  Address,
  IN UINT16  OrData
  )
{
  return MmioWrite16 (LoongsonPciConfigAddress (Address), (UINT16)(MmioRead16 (LoongsonPciConfigAddress (Address)) | OrData));
}

UINT16
EFIAPI
PciAnd16 (
  IN UINTN  Address,
  IN UINT16  AndData
  )
{
  return MmioWrite16 (LoongsonPciConfigAddress (Address), (UINT16)(MmioRead16 (LoongsonPciConfigAddress (Address)) & AndData));
}

UINT16
EFIAPI
PciAndThenOr16 (
  IN UINTN   Address,
  IN UINT16  AndData,
  IN UINT16  OrData
  )
{
  return MmioWrite16 (LoongsonPciConfigAddress (Address), (UINT16)((MmioRead16 (LoongsonPciConfigAddress (Address)) & AndData) | OrData));
}

UINT32
EFIAPI
PciRead32 (
  IN UINTN  Address
  )
{
  return MmioRead32 (LoongsonPciConfigAddress (Address));
}

UINT32
EFIAPI
PciWrite32 (
  IN UINTN   Address,
  IN UINT32  Value
  )
{
  return MmioWrite32 (LoongsonPciConfigAddress (Address), Value);
}

UINT32
EFIAPI
PciOr32 (
  IN UINTN   Address,
  IN UINT32  OrData
  )
{
  return MmioWrite32 (LoongsonPciConfigAddress (Address), MmioRead32 (LoongsonPciConfigAddress (Address)) | OrData);
}

UINT32
EFIAPI
PciAnd32 (
  IN UINTN   Address,
  IN UINT32  AndData
  )
{
  return MmioWrite32 (LoongsonPciConfigAddress (Address), MmioRead32 (LoongsonPciConfigAddress (Address)) & AndData);
}

UINT32
EFIAPI
PciAndThenOr32 (
  IN UINTN   Address,
  IN UINT32  AndData,
  IN UINT32  OrData
  )
{
  return MmioWrite32 (LoongsonPciConfigAddress (Address), (MmioRead32 (LoongsonPciConfigAddress (Address)) & AndData) | OrData);
}

#define PCI_BITFIELD_FUNCS(WIDTH)                                              \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciBitFieldRead##WIDTH (                                                       \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit                                              \
  )                                                                            \
{                                                                              \
  return BitFieldRead##WIDTH ((UINT##WIDTH)PciRead##WIDTH (Address), StartBit, EndBit); \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciBitFieldWrite##WIDTH (                                                      \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           Value                                               \
  )                                                                            \
{                                                                              \
  return PciWrite##WIDTH (Address, BitFieldWrite##WIDTH ((UINT##WIDTH)PciRead##WIDTH (Address), StartBit, EndBit, Value)); \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciBitFieldOr##WIDTH (                                                         \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciWrite##WIDTH (Address, BitFieldOr##WIDTH ((UINT##WIDTH)PciRead##WIDTH (Address), StartBit, EndBit, OrData)); \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciBitFieldAnd##WIDTH (                                                        \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData                                             \
  )                                                                            \
{                                                                              \
  return PciWrite##WIDTH (Address, BitFieldAnd##WIDTH ((UINT##WIDTH)PciRead##WIDTH (Address), StartBit, EndBit, AndData)); \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciBitFieldAndThenOr##WIDTH (                                                  \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciWrite##WIDTH (Address, BitFieldAndThenOr##WIDTH ((UINT##WIDTH)PciRead##WIDTH (Address), StartBit, EndBit, AndData, OrData)); \
}

PCI_BITFIELD_FUNCS (8)
PCI_BITFIELD_FUNCS (16)
PCI_BITFIELD_FUNCS (32)

/*
 * The Express family behaves identically to the base family (segment 0,
 * memory mapped configuration space).
 */
#define PCI_EXPRESS_ALIASES(WIDTH)                                             \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressRead##WIDTH (                                                        \
  IN UINTN                 Address                                             \
  )                                                                            \
{                                                                              \
  return PciRead##WIDTH (Address);                                             \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressWrite##WIDTH (                                                       \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           Value                                               \
  )                                                                            \
{                                                                              \
  return PciWrite##WIDTH (Address, Value);                                     \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressOr##WIDTH (                                                          \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciOr##WIDTH (Address, OrData);                                       \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressAnd##WIDTH (                                                         \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           AndData                                             \
  )                                                                            \
{                                                                              \
  return PciAnd##WIDTH (Address, AndData);                                     \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressAndThenOr##WIDTH (                                                   \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           AndData,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciAndThenOr##WIDTH (Address, AndData, OrData);                       \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressBitFieldRead##WIDTH (                                                \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit                                              \
  )                                                                            \
{                                                                              \
  return PciBitFieldRead##WIDTH (Address, StartBit, EndBit);                   \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressBitFieldWrite##WIDTH (                                               \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           Value,                                              \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit                                              \
  )                                                                            \
{                                                                              \
  return PciBitFieldWrite##WIDTH (Address, Value, StartBit, EndBit);           \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressBitFieldOr##WIDTH (                                                  \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciBitFieldOr##WIDTH (Address, StartBit, EndBit, OrData);             \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressBitFieldAnd##WIDTH (                                                 \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData                                             \
  )                                                                            \
{                                                                              \
  return PciBitFieldAnd##WIDTH (Address, StartBit, EndBit, AndData);           \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciExpressBitFieldAndThenOr##WIDTH (                                           \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  return PciBitFieldAndThenOr##WIDTH (Address, StartBit, EndBit, AndData, OrData); \
}

PCI_EXPRESS_ALIASES (8)
PCI_EXPRESS_ALIASES (16)
PCI_EXPRESS_ALIASES (32)

/*
 * CF8/CFC style access does not exist on LoongArch; reinterpret the CF8
 * encoded address into the equivalent library address so that stray
 * references still reach the right device.
 */
#define PCI_CF8_ALIASES(WIDTH)                                                 \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8Read##WIDTH (                                                            \
  IN UINTN                 Address                                             \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciRead##WIDTH (Conv);                                                \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8Write##WIDTH (                                                           \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           Value                                               \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciWrite##WIDTH (Conv, Value);                                        \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8Or##WIDTH (                                                              \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciOr##WIDTH (Conv, OrData);                                          \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8And##WIDTH (                                                             \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           AndData                                             \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciAnd##WIDTH (Conv, AndData);                                        \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8AndThenOr##WIDTH (                                                       \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           AndData,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciAndThenOr##WIDTH (Conv, AndData, OrData);                          \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8BitFieldRead##WIDTH (                                                    \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciBitFieldRead##WIDTH (Conv, StartBit, EndBit);                      \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8BitFieldWrite##WIDTH (                                                   \
  IN UINTN                 Address,                                            \
  IN UINT##WIDTH           Value,                                              \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciBitFieldWrite##WIDTH (Conv, Value, StartBit, EndBit);              \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8BitFieldOr##WIDTH (                                                      \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciBitFieldOr##WIDTH (Conv, StartBit, EndBit, OrData);                \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8BitFieldAnd##WIDTH (                                                     \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData                                             \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciBitFieldAnd##WIDTH (Conv, StartBit, EndBit, AndData);              \
}                                                                              \
                                                                               \
UINT##WIDTH                                                                    \
EFIAPI                                                                         \
PciCf8BitFieldAndThenOr##WIDTH (                                               \
  IN UINTN                 Address,                                            \
  IN UINTN                 StartBit,                                           \
  IN UINTN                 EndBit,                                             \
  IN UINT##WIDTH           AndData,                                            \
  IN UINT##WIDTH           OrData                                              \
  )                                                                            \
{                                                                              \
  UINTN  Conv = PCI_LIB_ADDRESS (((Address) >> 16) & 0xff, ((Address) >> 11) & 0x1f, \
                                 ((Address) >> 8) & 0x7, (Address) & 0xfc);    \
  return PciBitFieldAndThenOr##WIDTH (Conv, StartBit, EndBit, AndData, OrData); \
}

PCI_CF8_ALIASES (8)
PCI_CF8_ALIASES (16)
PCI_CF8_ALIASES (32)
