# 烧写与恢复（教育派 LS2K1000LA）

## 0. 备份（必做）

用 SPI 烧录器（CH341A，约 20 元）夹住 NOR 芯片整片读出备份；
或在仍能进入 PMON 时（开机按 C）用 PMON 的读/写 flash 命令备份。

## 1. 烧写 EDK II 固件（替换 PMON）

- 方式 A（PMON 可用时）：`load` 下载 UEFI.fd 到内存后用 PMON 的 flash 命令
  写入 NOR 起始 4MB。
- 方式 B（烧录器）：CH341A + clip 夹住 NOR，写入 `UEFI.fd` 到偏移 0。
  UEFI 变量区（NOR 偏移 0x400000-0x490000）首刷无需处理，固件首次启动会格式化。

## 2. 恢复

烧录器写回步骤 0 的备份镜像即可回到 PMON。

## 3. 启动 OpenWrt

将 OpenWrt 24.10 `loongarch64/generic` 的 `ext4-combined-efi.img.gz`
写入 U 盘，插板载 USB 口；上电进 UEFI 后选择 U 盘中的
`\EFI\BOOT\BOOTLOONGARCH64.EFI`（默认自动引导）。
