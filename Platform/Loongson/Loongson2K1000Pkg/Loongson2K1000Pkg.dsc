## @file
#  Loongson 2K1000LA (education board) platform DSC.
#
#  Forked from OvmfPkg/LoongArchVirt/LoongArchVirtQemu.dsc (BSD-2-Patent,
#  Copyright (c) 2024-2026 Loongson Technology Corporation Limited) and
#  adapted for real hardware: QEMU fw_cfg, virtio and ACPI-platform pieces
#  are replaced by on-chip drivers.
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
##

################################################################################
#
# Defines Section - statements that will be processed to create a Makefile.
#
###############################################################################
[Defines]
  PLATFORM_NAME                  = Loongson2K1000Pkg
  PLATFORMPKG_NAME               = Loongson2K1000Pkg
  PLATFORM_GUID                  = 8a9b0c1d-2e3f-4a5b-8c7d-6e5f4a3b2c1d
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 1.29
  OUTPUT_DIRECTORY               = Build/$(PLATFORM_NAME)
  SUPPORTED_ARCHITECTURES        = LOONGARCH64
  BUILD_TARGETS                  = DEBUG|RELEASE|NOOPT
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.fdf

!include Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.fdf.inc

  DEFINE TTY_TERMINAL            = TRUE
  DEFINE BUILD_SHELL             = TRUE

############################################################################
#
# Defines for default states.
#
############################################################################
[BuildOptions]
  GCC:RELEASE_*_*_CC_FLAGS       = -DSPEEDUP

  #
  # Disable deprecated APIs.
  #
  GCC:*_*_*_CC_FLAGS = -D DISABLE_NEW_DEPRECATED_INTERFACES

  #
  # PREMEM_STACK_TOP is consumed by the SEC assembly (Start.S); the board default
  # is set in Loongson2K1000Pkg.fdf.inc and can be overridden from the command
  # line (build -D PREMEM_STACK_TOP=0x90040000) for the QEMU smoke test.
  #
  # It has to go through PP_FLAGS, not CC_FLAGS: EDK2 assembles .S files with
  # `$(PP) $(PP_FLAGS)` followed by `$(ASM) $(ASM_FLAGS)`, and CC_FLAGS never
  # reaches either of those two steps - which is why the override silently had
  # no effect on the stack constant until it was moved here.
  #
  #
  # DDR configuration word for the memory controller, taken from the factory
  # PMON binary for this board: its `li.d $s1, ...` at flash offset 0x1648
  # loads 0xc0a18404, while the ported assembly's fallback (and the generic
  # PMON source default) is 0xf0a31004.  With the wrong word the DDR3 init
  # hangs, which is exactly where the board stopped (three beeps, never four).
  #
  #
  # DDR bring-up values for this board, read out of the factory PMON image
  # rather than guessed: a byte-level diff of the DDR3 parameter table between
  # that binary and our build shows these six knobs differ, and every one of
  # them is a per-board DRAM setting (DLL, ODT, drive strength, reset pad).
  # With any of them wrong the DDR init hangs, which is where the board stopped
  # (three beeps, never four).
  #
  #   $s1                 0xc0a18404            (li.d $s1 at flash 0x1648)
  #   DDR_PARAM_018       0x3030303016100000    (table entry 3)
  #   DDR_PARAM_140       0x00030000010f01ff    (entry 40)
  #   LS2K_STR                                  (clears bit 48 of entry 42)
  #   entries 56 and 62 are set directly in loongson_mc2_param.S -- their
  #   macros ignore a -D override on this branch.
  #
  GCC:*_*_*_PP_FLAGS = -D PREMEM_STACK_TOP=$(PREMEM_STACK_TOP) -D DDR_S1=0xc0a18404 -D DDR_PARAM_018=0x3030303016100000 -D DDR_PARAM_140=0x00030000010f01ff -D LS2K_STR

[BuildOptions.LOONGARCH64.EDKII.SEC]
  *_*_*_CC_FLAGS                 =

#
# Default page size is 16K for loongarch; code section separated with data
# section with 16K page alignment.
#
[BuildOptions.common.EDKII.DXE_CORE,BuildOptions.common.EDKII.DXE_DRIVER,BuildOptions.common.EDKII.UEFI_DRIVER,BuildOptions.common.EDKII.UEFI_APPLICATION]
  GCC:*_*_*_DLINK_FLAGS = -z common-page-size=0x4000

[BuildOptions.common.EDKII.DXE_RUNTIME_DRIVER]
  GCC:*_*_LOONGARCH64_DLINK_FLAGS = -z common-page-size=0x10000

################################################################################
#
# SKU Identification section
#
################################################################################
[SkuIds]
  0|DEFAULT

################################################################################
#
# Library Class section
#
################################################################################

!include MdePkg/MdeLibs.dsc.inc

[LibraryClasses.common]
  GptLib|MdeModulePkg/Library/GptLib/GptLib.inf
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  TimerLib                         | UefiCpuPkg/Library/CpuTimerLib/BaseCpuTimerLib.inf
  PrintLib                         | MdePkg/Library/BasePrintLib/BasePrintLib.inf
  BaseMemoryLib                    | MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  BaseLib                          | MdePkg/Library/BaseLib/BaseLib.inf
  SafeIntLib                       | MdePkg/Library/BaseSafeIntLib/BaseSafeIntLib.inf
  TimeBaseLib                      | EmbeddedPkg/Library/TimeBaseLib/TimeBaseLib.inf
  BmpSupportLib                    | MdeModulePkg/Library/BaseBmpSupportLib/BaseBmpSupportLib.inf
  SynchronizationLib               | MdePkg/Library/BaseSynchronizationLib/BaseSynchronizationLib.inf
  CpuLib                           | MdePkg/Library/BaseCpuLib/BaseCpuLib.inf
  PerformanceLib                   | MdePkg/Library/BasePerformanceLibNull/BasePerformanceLibNull.inf
  PeCoffLib                        | MdePkg/Library/BasePeCoffLib/BasePeCoffLib.inf
  CacheMaintenanceLib              | MdePkg/Library/BaseCacheMaintenanceLib/BaseCacheMaintenanceLib.inf
  UefiDecompressLib                | MdePkg/Library/BaseUefiDecompressLib/BaseUefiDecompressLib.inf
  UefiHiiServicesLib               | MdeModulePkg/Library/UefiHiiServicesLib/UefiHiiServicesLib.inf
  HiiLib                           | MdeModulePkg/Library/UefiHiiLib/UefiHiiLib.inf
  CapsuleLib                       | MdeModulePkg/Library/DxeCapsuleLibNull/DxeCapsuleLibNull.inf
  DxeServicesLib                   | MdePkg/Library/DxeServicesLib/DxeServicesLib.inf
  DxeServicesTableLib              | MdePkg/Library/DxeServicesTableLib/DxeServicesTableLib.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  PciLib                           | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonPciLib/LoongsonPciLib.inf
  PciSegmentLib                    | MdePkg/Library/BasePciSegmentLibPci/BasePciSegmentLibPci.inf
  PciCapLib                        | OvmfPkg/Library/BasePciCapLib/BasePciCapLib.inf
  PciCapPciSegmentLib              | OvmfPkg/Library/BasePciCapPciSegmentLib/BasePciCapPciSegmentLib.inf
  PciCapPciIoLib                   | OvmfPkg/Library/UefiPciCapPciIoLib/UefiPciCapPciIoLib.inf
  IoLib                            | MdePkg/Library/BaseIoLibIntrinsic/BaseIoLibIntrinsic.inf
  #
  # Native UART0 driver for the on-chip ns16550-compatible port.  The
  # OvmfPkg 16550 libraries find the UART through the QEMU device tree,
  # which does not exist here while SEC/PEI run, so they produced no
  # output at all on real hardware.
  #
  PlatformHookLib                  | MdeModulePkg/Library/BasePlatformHookLibNull/BasePlatformHookLibNull.inf
  SerialPortLib                    | Platform/Loongson/Loongson2K1000Pkg/Library/Loongson2KSerialPortLib/Loongson2KSerialPortLib.inf
  ResetSystemLib                   | Platform/Loongson/Loongson2K1000Pkg/Library/ResetSystemLib/Loongson2KResetSystemLib.inf

  UefiLib                          | MdePkg/Library/UefiLib/UefiLib.inf
  UefiBootServicesTableLib         | MdePkg/Library/UefiBootServicesTableLib/UefiBootServicesTableLib.inf
  UefiRuntimeServicesTableLib      | MdePkg/Library/UefiRuntimeServicesTableLib/UefiRuntimeServicesTableLib.inf
  UefiDriverEntryPoint             | MdePkg/Library/UefiDriverEntryPoint/UefiDriverEntryPoint.inf
  UefiApplicationEntryPoint        | MdePkg/Library/UefiApplicationEntryPoint/UefiApplicationEntryPoint.inf
  DevicePathLib                    | MdePkg/Library/UefiDevicePathLibDevicePathProtocol/UefiDevicePathLibDevicePathProtocol.inf
  FileHandleLib                    | MdePkg/Library/UefiFileHandleLib/UefiFileHandleLib.inf
  SecurityManagementLib            | MdeModulePkg/Library/DxeSecurityManagementLib/DxeSecurityManagementLib.inf
  UefiUsbLib                       | MdePkg/Library/UefiUsbLib/UefiUsbLib.inf
  SerializeVariablesLib            | OvmfPkg/Library/SerializeVariablesLib/SerializeVariablesLib.inf
  CustomizedDisplayLib             | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSetupThemeLib/CustomizedDisplayLib.inf
  LvglLib                          | LvglPkg/Library/LvglLib/LvglLib.inf
  DebugPrintErrorLevelLib          | MdePkg/Library/BaseDebugPrintErrorLevelLib/BaseDebugPrintErrorLevelLib.inf
  #
  # Progress log in the SPI NOR: works from SEC up, so early bring-up failures
  # are visible on a programmer read of the chip.
  #
  LoongsonBootLogLib               | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonBootLogLib/LoongsonBootLogLib.inf
  VarCheckLib                      | MdeModulePkg/Library/VarCheckLib/VarCheckLib.inf
  TpmMeasurementLib                | MdeModulePkg/Library/TpmMeasurementLibNull/TpmMeasurementLibNull.inf
  AuthVariableLib                  | MdeModulePkg/Library/AuthVariableLibNull/AuthVariableLibNull.inf
  ShellLib                         | ShellPkg/Library/UefiShellLib/UefiShellLib.inf
  HandleParsingLib                 | ShellPkg/Library/UefiHandleParsingLib/UefiHandleParsingLib.inf
  QemuFwCfgLib                     | OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgLibNull.inf
  VariablePolicyLib                | MdeModulePkg/Library/VariablePolicyLib/VariablePolicyLib.inf
  VariablePolicyHelperLib          | MdeModulePkg/Library/VariablePolicyHelperLib/VariablePolicyHelperLib.inf
  VariableFlashInfoLib             | MdeModulePkg/Library/BaseVariableFlashInfoLib/BaseVariableFlashInfoLib.inf
  SortLib                          | MdeModulePkg/Library/UefiSortLib/UefiSortLib.inf
  FdtLib                           | MdePkg/Library/BaseFdtLib/BaseFdtLib.inf
  PciHostBridgeLib                 | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonPciHostBridgeLib/LoongsonPciHostBridgeLib.inf
  PciHostBridgeUtilityLib          | OvmfPkg/Library/PciHostBridgeUtilityLib/PciHostBridgeUtilityLib.inf
  DxeHardwareInfoLib               | OvmfPkg/Library/HardwareInfoLib/DxeHardwareInfoLib.inf
  FileExplorerLib                  | MdeModulePkg/Library/FileExplorerLib/FileExplorerLib.inf
  ImagePropertiesRecordLib         | MdeModulePkg/Library/ImagePropertiesRecordLib/ImagePropertiesRecordLib.inf
  UefiBootManagerLib               | MdeModulePkg/Library/UefiBootManagerLib/UefiBootManagerLib.inf
  OrderedCollectionLib             | MdePkg/Library/BaseOrderedCollectionRedBlackTreeLib/BaseOrderedCollectionRedBlackTreeLib.inf
  ReportStatusCodeLib              | MdePkg/Library/BaseReportStatusCodeLibNull/BaseReportStatusCodeLibNull.inf
  PeCoffExtraActionLib             | MdePkg/Library/BasePeCoffExtraActionLibNull/BasePeCoffExtraActionLibNull.inf
  DebugAgentLib                    | MdeModulePkg/Library/DebugAgentLibNull/DebugAgentLibNull.inf
  TpmPlatformHierarchyLib          | SecurityPkg/Library/PeiDxeTpmPlatformHierarchyLibNull/PeiDxeTpmPlatformHierarchyLib.inf
  PlatformBmPrintScLib             | OvmfPkg/Library/PlatformBmPrintScLib/PlatformBmPrintScLib.inf
  PlatformBootManagerLib           | Platform/Loongson/Loongson2K1000Pkg/Library/PlatformBootManagerLib/PlatformBootManagerLib.inf
  BootLogoLib                      | MdeModulePkg/Library/BootLogoLib/BootLogoLib.inf
  PlatformBootManagerCommonLib     | OvmfPkg/Library/PlatformBootManagerCommonLib/PlatformBootManagerCommonLib.inf
  LockBoxLib                       | MdeModulePkg/Library/LockBoxNullLib/LockBoxNullLib.inf
  FrameBufferBltLib                | MdeModulePkg/Library/FrameBufferBltLib/FrameBufferBltLib.inf
  DebugLib                         | MdePkg/Library/BaseDebugLibSerialPort/BaseDebugLibSerialPort.inf
  PeiServicesLib                   | MdePkg/Library/PeiServicesLib/PeiServicesLib.inf
!if $(QEMU_FIT) == TRUE
  #
  # QEMU's ls2k machine backs only the first 1MB of the SPI NOR with the
  # firmware image and drops writes anywhere in the flash window, so the
  # variable store is moved into the low-DDR hole at 0x0F000000 (see the
  # PcdLoongsonSpiNor*/PcdFlashNvStorage* overrides below) and served by a
  # DRAM-backed device library.
  #
  VirtNorFlashDeviceLib            | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonQemuNorLib/LoongsonQemuNorFlashDeviceLib.inf
!else
  VirtNorFlashDeviceLib            | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSpiNorLib/LoongsonSpiNorFlashDeviceLib.inf
!endif
  VirtNorFlashPlatformLib          | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSpiNorLib/LoongsonSpiNorFlashPlatformLib.inf
  ShellCEntryLib                   | ShellPkg/Library/UefiShellCEntryLib/UefiShellCEntryLib.inf

[LibraryClasses.common.SEC]
  PcdLib                           | MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  PlatformHookLib                  | MdeModulePkg/Library/BasePlatformHookLibNull/BasePlatformHookLibNull.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/SecPeiCpuExceptionHandlerLib.inf

[LibraryClasses.common.PEI_CORE]
  PcdLib                           | MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeiCoreEntryPoint                | MdePkg/Library/PeiCoreEntryPoint/PeiCoreEntryPoint.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  OemHookStatusCodeLib             | MdeModulePkg/Library/OemHookStatusCodeLibNull/OemHookStatusCodeLibNull.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  PlatformHookLib                  | MdeModulePkg/Library/BasePlatformHookLibNull/BasePlatformHookLibNull.inf
  PerformanceLib                   | MdeModulePkg/Library/PeiPerformanceLib/PeiPerformanceLib.inf

[LibraryClasses.common.PEIM]
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeimEntryPoint                   | MdePkg/Library/PeimEntryPoint/PeimEntryPoint.inf
  PerformanceLib                   | MdeModulePkg/Library/PeiPerformanceLib/PeiPerformanceLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  OemHookStatusCodeLib             | MdeModulePkg/Library/OemHookStatusCodeLibNull/OemHookStatusCodeLibNull.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  ResourcePublicationLib           | MdePkg/Library/PeiResourcePublicationLib/PeiResourcePublicationLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/PeiExtractGuidedSectionLib/PeiExtractGuidedSectionLib.inf
  PcdLib                           | MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  CpuMmuLib                        | UefiCpuPkg/Library/CpuMmuLib/CpuMmuLib.inf
  CpuMmuInitLib                    | OvmfPkg/LoongArchVirt/Library/CpuMmuInitLib/CpuMmuInitLib.inf
  MpInitLib                        | UefiCpuPkg/Library/MpInitLib/PeiMpInitLib.inf
  PlatformHookLib                  | MdeModulePkg/Library/BasePlatformHookLibNull/BasePlatformHookLibNull.inf

[LibraryClasses.common.DXE_CORE]
  HobLib                           | MdePkg/Library/DxeCoreHobLib/DxeCoreHobLib.inf
  DxeCoreEntryPoint                | MdePkg/Library/DxeCoreEntryPoint/DxeCoreEntryPoint.inf
  MemoryAllocationLib              | MdeModulePkg/Library/DxeCoreMemoryAllocationLib/DxeCoreMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/DxeCpuExceptionHandlerLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxeCorePerformanceLib/DxeCorePerformanceLib.inf

[LibraryClasses.common.DXE_RUNTIME_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/RuntimeDxeReportStatusCodeLib/RuntimeDxeReportStatusCodeLib.inf
  UefiRuntimeLib                   | MdePkg/Library/UefiRuntimeLib/UefiRuntimeLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  RealTimeClockLib                 | Platform/Loongson/Loongson2K1000Pkg/Library/Ls2kRealTimeClockLib/LsRealTimeClockLib.inf
  VariablePolicyLib                | MdeModulePkg/Library/VariablePolicyLib/VariablePolicyLibRuntimeDxe.inf
!if $(TARGET) != RELEASE
  DebugLib                         | MdePkg/Library/DxeRuntimeDebugLibSerialPort/DxeRuntimeDebugLibSerialPort.inf
!endif

[LibraryClasses.common.UEFI_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  UefiScsiLib                      | MdePkg/Library/UefiScsiLib/UefiScsiLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf

[LibraryClasses.common.DXE_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  UefiScsiLib                      | MdePkg/Library/UefiScsiLib/UefiScsiLib.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/DxeCpuExceptionHandlerLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  MpInitLib                        | UefiCpuPkg/Library/MpInitLib/DxeMpInitLib.inf

[LibraryClasses.common.UEFI_APPLICATION]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf

################################################################################
#
# Pcd Section
#
################################################################################
[PcdsFeatureFlag]
   gEfiMdeModulePkgTokenSpaceGuid.PcdHiiOsRuntimeSupport               | FALSE
   gEfiMdeModulePkgTokenSpaceGuid.PcdDxeIplSupportUefiDecompress        | TRUE
   gEfiMdeModulePkgTokenSpaceGuid.PcdConOutGopSupport                   | TRUE
   gEfiMdeModulePkgTokenSpaceGuid.PcdPciBusHotplugDeviceSupport         | FALSE

[PcdsFixedAtBuild]
## BaseLib ##
  gEfiMdePkgTokenSpaceGuid.PcdMaximumUnicodeStringLength               | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdMaximumAsciiStringLength                 | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdMaximumLinkedListLength                  | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdSpinLockTimeout                          | 10000000

  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFdBaseAddress                      | $(FW_BASE_ADDRESS)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFirmwareFdSize                     | $(FW_SIZE)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFirmwareBlockSize                 | $(BLOCK_SIZE)

  gEfiMdeModulePkgTokenSpaceGuid.PcdStatusCodeMemorySize               | 1
  gEfiMdeModulePkgTokenSpaceGuid.PcdResetOnMemoryTypeInformationChange | FALSE
  gEfiMdePkgTokenSpaceGuid.PcdMaximumGuidedExtractHandler              | 0x10
  gEfiMdeModulePkgTokenSpaceGuid.PcdMaxVariableSize                    | 0x2000
  gEfiMdeModulePkgTokenSpaceGuid.PcdMaxHardwareErrorVariableSize       | 0x8000
  gEfiMdeModulePkgTokenSpaceGuid.PcdVpdBaseAddress                     | 0x0
  gEfiMdePkgTokenSpaceGuid.PcdPerformanceLibraryPropertyMask           | 0x1
  gEfiMdePkgTokenSpaceGuid.PcdReportStatusCodePropertyMask             | 0x07

  # Use MMIO for accessing Serial port registers.
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialUseMmio                      | TRUE
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialPciDeviceInfo                | {0xFF}
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialBaudRate                     | 115200
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialRegisterStride               | 1
  # UART0 APB clock after PLL bring-up.
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialClockRate                    | 125000000

  gEfiMdePkgTokenSpaceGuid.PcdDebugPrintErrorLevel                     | 0x8000004F

!if $(TARGET) == RELEASE
  gEfiMdePkgTokenSpaceGuid.PcdDebugPropertyMask                        | 0x23
!else
  gEfiMdePkgTokenSpaceGuid.PcdDebugPropertyMask                        | 0x2f
!endif

  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamBase                  | $(SEC_PEI_TEMP_RAM_BASE)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamSize                  | $(SEC_PEI_TEMP_RAM_SIZE)
  gUefiOvmfPkgTokenSpaceGuid.PcdDeviceTreeInitialBaseAddress           | $(DEVICE_TREE_RAM_BASE)

  gUefiCpuPkgTokenSpaceGuid.PcdLoongArchExceptionVectorBaseAddress     | gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamBase

  # Stable counter frequency (100MHz constant clock on 2K1000LA).
  gUefiCpuPkgTokenSpaceGuid.PcdCpuCoreCrystalClockFrequency             | 100000000

  # Default the BIOS UI to Simplified Chinese (user-switchable in the FrontPage).
  gEfiMdePkgTokenSpaceGuid.PcdUefiVariableDefaultPlatformLang        | "zh-Hans"
  gEfiMdePkgTokenSpaceGuid.PcdUefiVariableDefaultPlatformLangCodes   | "en-US;fr-FR;zh-Hans"

  gEfiMdeModulePkgTokenSpaceGuid.PcdBootManagerMenuFile                | { 0xdc, 0x5b, 0xc2, 0xee, 0xf2, 0x67, 0x95, 0x4d, 0xb1, 0xd5, 0xf8, 0x1b, 0x20, 0x39, 0xd1, 0x1d }

  # UEFI variable store lives in the SPI NOR behind the 4MB firmware image.
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageVariableBase64       | 0x1c370000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageVariableSize         | 0x40000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwWorkingBase64     | 0x1c3B0000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwWorkingSize       | 0x10000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwSpareBase64       | 0x1c3C0000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwSpareSize         | 0x40000

!if $(QEMU_FIT) == TRUE
  #
  # QEMU smoke build: the emulator only backs the first 1MB of the SPI NOR
  # with the firmware image and drops every write in the flash window, so no
  # variable store can ever be formatted there.  Park it in the 16MB DRAM hole
  # between the end of the low DDR window (LS2K1000_LOW_RAM_LIMIT, 0x0F000000)
  # and the start of the SoC MMIO window (0x10000000) instead, and let
  # LoongsonQemuNorFlashDeviceLib implement NOR semantics on that DRAM.  The
  # window is deliberately absent from the platform's resource HOBs, which is
  # what lets VirtNorFlashDxe's gDS->AddMemorySpace() for it succeed.
  #
  gLoongson2K1000TokenSpaceGuid.PcdLoongsonSpiNorBaseAddress           | 0x0F000000
  gLoongson2K1000TokenSpaceGuid.PcdLoongsonSpiNorVarStoreOffset        | 0x0
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageVariableBase64       | 0x0F000000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwWorkingBase64     | 0x0F040000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwSpareBase64       | 0x0F050000

  #
  # QEMU_FIT also drops SetupBrowserDxe/DisplayEngineDxe, so
  # gEfiFormBrowser2ProtocolGuid is never installed.  BmRepairAllControllers()
  # -- called from EfiBootManagerBoot() on every boot attempt -- asserts on that
  # lookup, and ZeroGuid is the documented way to skip driver health handling.
  #
  gEfiMdeModulePkgTokenSpaceGuid.PcdDriverHealthConfigureForm | {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}
!endif

  gEfiMdeModulePkgTokenSpaceGuid.PcdNullPointerDetectionPropertyMask   | 1

  ## Default Terminal Type
!if $(TTY_TERMINAL) == TRUE
  gEfiMdePkgTokenSpaceGuid.PcdDefaultTerminalType                      | 4
  gUefiOvmfPkgTokenSpaceGuid.PcdTerminalTypeGuidBuffer                 | {0x80, 0x6d, 0x91, 0x7d, 0xb1, 0x5b, 0x8c, 0x45, 0xa4, 0x8f, 0xe2, 0x5f, 0xdd, 0x51, 0xef, 0x94}
!else
  gEfiMdePkgTokenSpaceGuid.PcdDefaultTerminalType                      | 1
!endif

[PcdsDynamicDefault]
  gEfiMdeModulePkgTokenSpaceGuid.PcdEmuVariableNvStoreReserved         | 0
  gEfiMdeModulePkgTokenSpaceGuid.PcdPciDisableBusEnumeration           | FALSE
  gEfiMdeModulePkgTokenSpaceGuid.PcdVideoHorizontalResolution          | 1024
  gEfiMdeModulePkgTokenSpaceGuid.PcdVideoVerticalResolution            | 768
  gEfiMdePkgTokenSpaceGuid.PcdPlatformBootTimeOut                      | 3

  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupVideoHorizontalResolution     | 1024
  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupVideoVerticalResolution       | 768

  #
  # Console auto-sizing: 0 selects the largest text mode of the active GOP
  # mode, so the BIOS UI fills the screen at any resolution (same values as
  # OvmfPkg/Include/Dsc/OvmfDisplayPcds.dsc.inc).
  #
  gEfiMdeModulePkgTokenSpaceGuid.PcdConOutColumn                        | 0
  gEfiMdeModulePkgTokenSpaceGuid.PcdConOutRow                           | 0
  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupConOutColumn                   | 0
  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupConOutRow                      | 0

  #
  # Loongson setup theme: inverted selection, lightgray field text,
  # gold subtitles (matches the boot splash palette).
  #
  gEfiMdeModulePkgTokenSpaceGuid.PcdBrowserFieldTextColor               | 0x07
  gEfiMdeModulePkgTokenSpaceGuid.PcdBrowserFieldTextHighlightColor      | 0x00
  gEfiMdeModulePkgTokenSpaceGuid.PcdBrowserFieldBackgroundHighlightColor| 0x07
  gEfiMdeModulePkgTokenSpaceGuid.PcdBrowserSubtitleTextColor            | 0x0E

  gEfiMdePkgTokenSpaceGuid.PcdPciIoTranslation                         | 0x0

[PcdsPatchableInModule.common]
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialRegisterBase|0x0

################################################################################
#
# Components Section
#
################################################################################
[Components]

  #
  # SEC Phase modules
  #
  Platform/Loongson/Loongson2K1000Pkg/Sec/SecMain.inf

  #
  # PEI Phase modules
  #
  MdeModulePkg/Core/Pei/PeiMain.inf
  MdeModulePkg/Universal/PCD/Pei/Pcd.inf  {
    <LibraryClasses>
      PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }
  MdePkg/Library/PeiExtractGuidedSectionLib/PeiExtractGuidedSectionLib.inf
  MdeModulePkg/Core/DxeIplPeim/DxeIpl.inf {
    <LibraryClasses>
      NULL|MdeModulePkg/Library/LzmaCustomDecompressLib/LzmaCustomDecompressLib.inf
  }

  Platform/Loongson/Loongson2K1000Pkg/PlatformPei/PlatformPei.inf {
    <LibraryClasses>
      PcdLib|MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  }

  #
  # DXE Phase modules
  #
  MdeModulePkg/Core/Dxe/DxeMain.inf {
    <LibraryClasses>
      NULL                             | MdeModulePkg/Library/LzmaCustomDecompressLib/LzmaCustomDecompressLib.inf
      DevicePathLib                    | MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
      ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  }

  MdeModulePkg/Universal/ReportStatusCodeRouter/RuntimeDxe/ReportStatusCodeRouterRuntimeDxe.inf
  MdeModulePkg/Universal/StatusCodeHandler/RuntimeDxe/StatusCodeHandlerRuntimeDxe.inf
  MdeModulePkg/Universal/PCD/Dxe/Pcd.inf  {
   <LibraryClasses>
      PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }

  MdeModulePkg/Core/RuntimeDxe/RuntimeDxe.inf
  UefiCpuPkg/CpuDxe/CpuDxe.inf {
    <LibraryClasses>
      CpuMmuLib | UefiCpuPkg/Library/CpuMmuLib/CpuMmuLib.inf
  }
  MdeModulePkg/Universal/WatchdogTimerDxe/WatchdogTimer.inf
  MdeModulePkg/Universal/MonotonicCounterRuntimeDxe/MonotonicCounterRuntimeDxe.inf
  MdeModulePkg/Universal/CapsuleRuntimeDxe/CapsuleRuntimeDxe.inf
  MdeModulePkg/Universal/SecurityStubDxe/SecurityStubDxe.inf
  OvmfPkg/LoongArchVirt/Drivers/StableTimerDxe/TimerDxe.inf
  MdeModulePkg/Universal/ResetSystemRuntimeDxe/ResetSystemRuntimeDxe.inf
  MdeModulePkg/Universal/Metronome/Metronome.inf
  EmbeddedPkg/RealTimeClockRuntimeDxe/RealTimeClockRuntimeDxe.inf

  #
  # Variable
  #
  OvmfPkg/VirtNorFlashDxe/VirtNorFlashDxe.inf
  MdeModulePkg/Universal/FaultTolerantWriteDxe/FaultTolerantWriteDxe.inf {
    <LibraryClasses>
      NULL|EmbeddedPkg/Library/NvVarStoreFormattedLib/NvVarStoreFormattedLib.inf
  }
  MdeModulePkg/Universal/Variable/RuntimeDxe/VariableRuntimeDxe.inf {
    <LibraryClasses>
      NULL|MdeModulePkg/Library/VarCheckUefiLib/VarCheckUefiLib.inf
      NULL|EmbeddedPkg/Library/NvVarStoreFormattedLib/NvVarStoreFormattedLib.inf
      BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  }

  #
  # PCI
  #
  UefiCpuPkg/CpuMmio2Dxe/CpuMmio2Dxe.inf
  EmbeddedPkg/Drivers/FdtClientDxe/FdtClientDxe.inf
  MdeModulePkg/Bus/Pci/PciHostBridgeDxe/PciHostBridgeDxe.inf
  MdeModulePkg/Bus/Pci/PciBusDxe/PciBusDxe.inf

  #
  # Storage over PCI (SATA / NVMe behind the internal PCIe complex)
  #
  MdeModulePkg/Bus/Pci/SataControllerDxe/SataControllerDxe.inf
  MdeModulePkg/Bus/Ata/AtaBusDxe/AtaBusDxe.inf
  MdeModulePkg/Bus/Ata/AtaAtapiPassThru/AtaAtapiPassThru.inf
  MdeModulePkg/Bus/Pci/NvmExpressDxe/NvmExpressDxe.inf

  #
  # USB (EHCI / OHCI live on the internal PCI bus on 2K1000LA)
  #
  MdeModulePkg/Bus/Pci/XhciDxe/XhciDxe.inf
  MdeModulePkg/Bus/Pci/EhciDxe/EhciDxe.inf
  MdeModulePkg/Bus/Usb/UsbBusDxe/UsbBusDxe.inf
  MdeModulePkg/Bus/Usb/UsbKbDxe/UsbKbDxe.inf
  MdeModulePkg/Bus/Usb/UsbMassStorageDxe/UsbMassStorageDxe.inf

  #
  # File system
  #
  MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf
  MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf
  MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf
  FatPkg/EnhancedFatDxe/Fat.inf
  MdeModulePkg/Universal/Disk/UdfDxe/UdfDxe.inf

  #
  # BDS
  #
  MdeModulePkg/Universal/DevicePathDxe/DevicePathDxe.inf {
    <LibraryClasses>
      DevicePathLib                    | MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
      PcdLib                           | MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }
  MdeModulePkg/Universal/HiiDatabaseDxe/HiiDatabaseDxe.inf
  MdeModulePkg/Universal/DisplayEngineDxe/DisplayEngineDxe.inf
  MdeModulePkg/Universal/SetupBrowserDxe/SetupBrowserDxe.inf
  MdeModulePkg/Universal/BdsDxe/BdsDxe.inf
  MdeModulePkg/Logo/LogoDxe.inf

  MdeModulePkg/Application/BootManagerMenuApp/BootManagerMenuApp.inf

  #
  # Graphical (LVGL) setup center replaces the text UiApp setup front page.
  #
  LvglPkg/Application/LvglSetupApp/LvglSetupApp.inf

  #
  # Console
  #
  Platform/Loongson/Loongson2K1000Pkg/LoongsonDisplayDxe/LoongsonDisplayDxe.inf
  Platform/Loongson/Loongson2K1000Pkg/LoongsonOverclockDxe/LoongsonOverclockDxe.inf

  #
  # Console
  #
  MdeModulePkg/Universal/Console/ConPlatformDxe/ConPlatformDxe.inf
  MdeModulePkg/Universal/Console/ConSplitterDxe/ConSplitterDxe.inf
  MdeModulePkg/Universal/Console/GraphicsConsoleDxe/GraphicsConsoleDxe.inf
  MdeModulePkg/Universal/Console/TerminalDxe/TerminalDxe.inf
  MdeModulePkg/Universal/PrintDxe/PrintDxe.inf
  MdeModulePkg/Universal/SerialDxe/SerialDxe.inf

  #
  # UEFI Shell
  #
  ShellPkg/Application/Shell/Shell.inf {
    <LibraryClasses>
      ShellCommandLib|ShellPkg/Library/UefiShellCommandLib/UefiShellCommandLib.inf
      NULL|ShellPkg/Library/UefiShellLevel2CommandsLib/UefiShellLevel2CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellLevel1CommandsLib/UefiShellLevel1CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellLevel3CommandsLib/UefiShellLevel3CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellDriver1CommandsLib/UefiShellDriver1CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellInstall1CommandsLib/UefiShellInstall1CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellAcpiViewCommandLib/UefiShellAcpiViewCommandLib.inf
      # network command libs dropped: NetLib needs a NIC stack we do not ship yet
      BcfgCommandLib|ShellPkg/Library/UefiShellBcfgCommandLib/UefiShellBcfgCommandLib.inf
      PcdLib|MdePkg/Library/DxePcdLib/DxePcdLib.inf
    <PcdsFixedAtBuild>
      #
      # ShellLibConstructor() returns EFI_NOT_FOUND unless either shell protocol
      # already exists or auto-initialisation is off.  When the Shell runs as a
      # boot option it installs those protocols itself, i.e. strictly after its
      # library constructors, so with the default (TRUE) the Shell aborts in
      # ASSERT_EFI_ERROR before reaching ShellAppMain().
      #
      gEfiShellPkgTokenSpaceGuid.PcdShellLibAutoInitialize|FALSE
  }
  ShellPkg/DynamicCommand/DpDynamicCommand/DpDynamicCommand.inf {
    <PcdsFixedAtBuild>
      gEfiShellPkgTokenSpaceGuid.PcdShellLibAutoInitialize|FALSE
  }
