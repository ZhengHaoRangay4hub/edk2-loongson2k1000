DEFINE BLOCK_SIZE                 = 0x1000

#
# QEMU fit-out.  The ls2k machine memory-maps only the first 1 MB of the SPI
# NOR at the reset window (0x1c000000); everything past 0x1c0fffff reads back
# as zero.  A full-feature build puts about 1.4 MB of content in front of the
# DXE volume, so DxeIpl truncates the LZMA stream and fails to load DXE core.
# Building with -D QEMU_FIT=TRUE drops the drivers that the emulator cannot
# exercise anyway, which brings the whole image below 1 MB and lets the DXE
# phase be boot-tested.  Real firmware builds leave this FALSE.
#
!ifndef QEMU_FIT
  DEFINE QEMU_FIT                  = FALSE
!endif

#
# Pre-DRAM stack top used by Sec/LoongArch64/Start.S.  The board default sits at
# the top of the writable 256 KB window the boot ROM maps over the front of the
# SPI NOR image.  QEMU's ls2k machine maps that window as read-only ROM, so the
# QEMU smoke test overrides it (build -D PREMEM_STACK_TOP=0x90040000); see the
# comment in Start.S for why 0x90040000 is the right stand-in.
#
!ifndef PREMEM_STACK_TOP
  DEFINE PREMEM_STACK_TOP         = 0x1c040000
!endif

############################################################################
# FW total: 4MB of SPI NOR starting at the LoongArch reset vector window
DEFINE FW_BASE_ADDRESS            = 0x1c000000
DEFINE FW_BLOCKS                  = 0x400
DEFINE FW_SIZE                    = 0x400000

#
# Firmware volume occupies the front of the 4MB image; the UEFI variable
# store sits in the last 0x90000 bytes (0x370000..0x400000) so that variable
# writes can never overwrite the firmware volume itself:
#   0x000000..0x370000  FVMAIN_COMPACT (about 1.4MB used today)
#   0x370000..0x3B0000  variable store
#   0x3B0000..0x3C0000  FTW working block
#   0x3C0000..0x400000  FTW spare block
#
DEFINE FVMAIN_SIZE                = 0x370000

#Set Memory layout (inside the 2MB firmware-reserve area of low RAM)
DEFINE SEC_PEI_TEMP_RAM_BASE      = 0x10000
DEFINE SEC_PEI_TEMP_RAM_SIZE      = 0x80000
DEFINE DEVICE_TREE_RAM_BASE       = 0x100000
