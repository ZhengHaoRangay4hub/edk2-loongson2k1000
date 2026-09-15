DEFINE BLOCK_SIZE                 = 0x1000

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
