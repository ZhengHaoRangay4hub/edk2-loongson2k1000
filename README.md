# ls2k1000la-edk2 — EDK II 固件移植：龙芯教育派（LS2K1000LA）

这是一个**从复位向量开始的全量 EDK II（UEFI）固件移植**，目标硬件为
龙芯教育派 LA（LS2K1000LA 双核 LA264，2GB DDR3，教育竞赛板）。

不依赖 PMON / U-Boot：SEC 阶段在片上直接完成看门狗关闭、SoC 早期初始化、
PLL 编程与 DDR3 控制器初始化（初始化序列移植自龙芯 PMON
[pmon-ls2k1000la](https://github.com/loongson-community/pmon-ls2k1000la)，
BSD 许可），随后进入标准 PEI → DXE → BDS 流程。

## 构建产物

| 文件 | 用途 |
|---|---|
| `UEFI.fd`（4MB） | 教育派 SPI NOR 固件，烧写在 NOR 起始处（0x1c000000 窗口） |
| `QEMU_EFI.fd` | 上游 `OvmfPkg/LoongArchVirt` 同工具链构建，用于 QEMU 引导链回归测试 |
| `ls2k1000-la.dtb` | 嵌入固件的设备树（主线内核绑定风格） |

## 平台支持清单

- **SEC**：DMW 窗口、CRMD、片上 SRAM 栈（0x1c000000+256K，与 PMON 相同）、
  16550 串口（0x1fe20000 @115200）、看门狗关闭、SPI NOR 提速、
  PCIe PHY/六端口配置、SATA 时钟、GMAC1 引脚复用、CPU 800MHz / DDR 400MHz PLL、
  LSMC DDR3 初始化 + leveling（PMON 汇编原样移植）
- **多核**：AP 核泊车（IOCSR IPI/MBUF），PEI MpInitLib 唤醒
- **变量**：SPI NOR 内 UEFI 变量存储（0x1c040000 起，硬件 SPI 命令擦写）
- **存储**：PCIe 内部总线上的 EHCI/OHCI（USB 盘启动）、AHCI SATA、NVMe；
  NOR XIP 区 BlockIo
- **PCI**：龙芯压缩式 ECAM（`0xFE00000000 + bus<<21 + dev<<11 + fn<<8`）
- **RTC**：片上 `ls2k1000-rtc`
- **复位/关机**：PMC syscon（0x1fe27000）
- **设备树**：固件内嵌 DTB，通过 EFI configuration table 交给 EFISTUB 内核
  （OpenWrt 24.10 loongarch64 EFI 镜像可直接引导）
- **控制台**：串口 TTY 终端 + UEFI Shell + UiApp 启动菜单

## 烧写与恢复

见 [docs/FLASHING.md](docs/FLASHING.md)。**务必先备份整颗 SPI NOR**；
固件替换 PMON 后，恢复需要 SPI 烧录器（CH341A 等）。

## 已知限制

- HDMI/LCD 显示（DC/GPU）未驱动，仅串口控制台
- GMAC 网络启动（PXE/SNP）未实现
- RTC 寄存器布局按 LS7A/ls2x 家族假设，实机时间若异常不影响启动
- 第一次上电调试建议保留 PMON 备份镜像

## 构建方式

GitHub Actions（`.github/workflows/build.yml`）使用龙芯官方交叉工具链
[build-tools 2024.08.08](https://github.com/loongson/build-tools/releases)
（gcc 14.2 / binutils 2.43，满足 edk2 主线 LoongArch 的
`-mno-relax` 需求）交叉编译，`-t GCC -a LOONGARCH64`。每次 push 自动构建
RELEASE + DEBUG 双目标，并在同一流水线里构建上游
`OvmfPkg/LoongArchVirt`（QEMU）作回归对照。

本地构建步骤相同：把本包复制进 edk2 源码树 `Platform/Loongson/` 后执行

```sh
export GCC_LOONGARCH64_PREFIX=loongarch64-unknown-linux-gnu-
make -C BaseTools && source edksetup.sh BaseTools
D=Platform/Loongson/Loongson2K1000Pkg/Dts
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I $D/include $D/ls2k1000-la.dts | \
  dtc -I dts -O dtb -o $D/ls2k1000-la.dtb -
# PMON 的跨文件汇编聚合必须先内联（EDK2 的 Trim 工具会丢弃非顶层文件内容）
python3 tools/merge_asm_includes.py \
  Platform/Loongson/Loongson2K1000Pkg/Sec/PreMem/DdrEntry.S \
  > Platform/Loongson/Loongson2K1000Pkg/Sec/PreMem/DdrEntry.merged.S
mv Platform/Loongson/Loongson2K1000Pkg/Sec/PreMem/DdrEntry.merged.S \
  Platform/Loongson/Loongson2K1000Pkg/Sec/PreMem/DdrEntry.S
build -b RELEASE -t GCC -a LOONGARCH64 -p Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.dsc
```

## 验证状态

- **CI 编译**：RELEASE/DEBUG 双目标绿灯（含 LoongArchVirt QEMU 对照构建）。
- **QEMU 引导链**（`scripts/test-qemu-virt.sh`，macOS/Linux 均可）：
  SEC → PEI → DXE → BDS 全链跑通，BDS 正常报告无可引导设备并进入
  Boot Manager；UiApp 设置界面（FrontPage / Device Manager / Boot
  Manager / Boot Maintenance Manager / 语言选择）经串口终端完整渲染。
- **开机 Logo**：自制发光"龙"启动画面（`assets/logo.bmp`，1024×512，
  Setup 控制台 1024×768），CI 构建时替换上游默认 Logo，
  见 [docs/img/boot-splash.png](docs/img/boot-splash.png)。
- **OpenWrt 24.10.1 实机引导验证**（loongarch64/generic 官方镜像，
  无需任何修改）：

  ```sh
  qemu-system-loongarch64 -m 1G -M virt -smp 2 -cpu la464 \
    -drive if=pflash,format=raw,file=QEMU_EFI.fd,readonly=on \
    -drive if=pflash,format=raw,file=vars.fd \
    -drive file=openwrt-24.10.1-loongarch64-generic-generic-ext4-combined-efi.img,if=none,id=nvme1,format=raw \
    -device nvme,drive=nvme1,serial=1634 \
    -device ramfb -device qemu-xhci -device usb-kbd -serial stdio
  ```

  链路：固件 BDS 发现 NVMe → `EFI/BOOT/BOOTLOONGARCH64.EFI`(GRUB)
  → EFI stub 内核 → mount_root → procd → `root@OpenWrt:~#`。
  官方 generic 内核未内置 virtio-blk，但内置 nvme，因此磁盘必须走
  `-device nvme`；实机效果见 [docs/img/openwrt-console.png](docs/img/openwrt-console.png)。
- **真机**：DDR3 初始化/leveling 序列按 PMON 原样移植且编译通过，
  但**尚未在实体教育派上点灯验证**——首次上电请按 FLASHING.md 备份并
  保留串口日志。

## 许可

移植新增代码遵循 BSD-2-Clause-Patent（与 edk2 一致）；移植的 PMON 汇编
遵循其原始 BSD 授权（见文件头）。
