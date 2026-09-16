/** @file
  PCI Host Bridge Library for Loongson 2K1000LA.

  Single root bridge covering the internal PCIe complex:
    bus   : 0x00 - 0xFF
    io    : 0x18008000 - 0x1800FFFF
    memory: 0x60000000 - 0x7FFFFFFF
    config: 0xFE00000000 - 0xFE1FFFFFFF (Loongson compressed ECAM,
            handled by LoongsonPciLib)

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/
#include <PiDxe.h>

#include <Library/DebugLib.h>
#include <Library/PciHostBridgeLib.h>
#include <Library/PciHostBridgeUtilityLib.h>
#include <Library/MemoryAllocationLib.h>

#include <Protocol/PciRootBridgeIo.h>
#include <Protocol/PciHostBridgeResourceAllocation.h>

//
// PCI_ROOT_BRIDGE_APERTURE is { Base, Limit, Translation }, not { Base, Size }.
// Handing the size in as the limit makes Limit < Base, so every aperture looks
// empty and PciHostBridgeDxe reports "Base/Length/Alignment =
// FFFFFFFFFFFFFFFF/... - Out Of Resource!" for the first root bridge, aborts
// resource allocation with EFI_OUT_OF_RESOURCES, and PciBusDxe then fails to
// connect any device.
//
STATIC PCI_ROOT_BRIDGE_APERTURE  mNonExistAperture = { MAX_UINT64, 0 };

STATIC PCI_ROOT_BRIDGE_APERTURE  mIoAperture  = { 0x18008000, 0x1800FFFF };

STATIC PCI_ROOT_BRIDGE_APERTURE  mMemAperture = { 0x60000000, 0x7FFFFFFF };

/**
  Return all the root bridge instances in an array.

  The array has to be heap allocated: the caller releases it with
  PciHostBridgeFreeRootBridges(), which drops the device path of every bridge
  and then the array itself.  A static array here would make the device path
  come from the utility library (it always allocates one) and still be handed
  to FreePool() twice over, tripping ASSERT_EFI_ERROR() in FreePool().

  @param Count  Return the count of root bridge instances.

  @return All the root bridge instances in an array.
**/
PCI_ROOT_BRIDGE *
EFIAPI
PciHostBridgeGetRootBridges (
  UINTN  *Count
  )
{
  UINT64            AllocationAttributes;
  EFI_STATUS        Status;
  PCI_ROOT_BRIDGE   *RootBridge;

  RootBridge = AllocateZeroPool (sizeof (PCI_ROOT_BRIDGE));
  if (RootBridge == NULL) {
    *Count = 0;
    return NULL;
  }

  AllocationAttributes = EFI_PCI_HOST_BRIDGE_COMBINE_MEM_PMEM;

  Status = PciHostBridgeUtilityInitRootBridge (
    0,
    EFI_PCI_ATTRIBUTE_IDE_PRIMARY_IO | EFI_PCI_ATTRIBUTE_IDE_SECONDARY_IO |
    EFI_PCI_ATTRIBUTE_VGA_PALETTE_IO | EFI_PCI_ATTRIBUTE_ISA_MOTHERBOARD_IO |
    EFI_PCI_ATTRIBUTE_ISA_IO,
    AllocationAttributes,
    FALSE,                 /* DmaAbove4G  */
    FALSE,                 /* NoExtendedConfigSpace */
    0x00,                  /* RootBusNumber */
    0xFF,                  /* MaxSubBusNumber */
    &mIoAperture,
    &mMemAperture,
    &mNonExistAperture,    /* MemAbove4G  */
    &mNonExistAperture,    /* PMem        */
    &mNonExistAperture,    /* PMemAbove4G */
    RootBridge
    );
  if (EFI_ERROR (Status)) {
    DEBUG ((
      DEBUG_ERROR,
      "%a: PciHostBridgeUtilityInitRootBridge() failed - %r\n",
      __func__,
      Status
      ));
    FreePool (RootBridge);
    *Count = 0;
    return NULL;
  }

  *Count = 1;
  return RootBridge;
}

/**
  Free the root bridge instances array returned from
  PciHostBridgeGetRootBridges().
**/
VOID
EFIAPI
PciHostBridgeFreeRootBridges (
  PCI_ROOT_BRIDGE  *Bridges,
  UINTN            Count
  )
{
  PciHostBridgeUtilityFreeRootBridges (Bridges, Count);
}

/**
  Inform the platform that the resource conflict happens.
**/
VOID
EFIAPI
PciHostBridgeResourceConflict (
  EFI_HANDLE  HostBridgeHandle,
  VOID        *Configuration
  )
{
  PciHostBridgeUtilityResourceConflict (Configuration);
}
