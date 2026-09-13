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

GitHub Actions（`.github/workflows/build.yml`）使用
`gcc-loongarch64-linux-gnu`（Ubuntu 24.04，GCC13/binutils2.40+，满足
LoongArch 需求）交叉编译，`-t GCC -a LOONGARCH64`。本地构建步骤相同：
把本包复制进 edk2 源码树 `Platform/Loongson/` 后执行

```sh
export GCC_LOONGARCH64_PREFIX=loongarch64-linux-gnu-
make -C BaseTools && source edksetup.sh BaseTools
dtc -I dts -O dtb -i Platform/Loongson/Loongson2K1000Pkg/Dts \
    -o Platform/Loongson/Loongson2K1000Pkg/Dts/ls2k1000-la.dtb \
    Platform/Loongson/Loongson2K1000Pkg/Dts/ls2k1000-la.dts
build -b RELEASE -t GCC -a LOONGARCH64 -p Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.dsc
```

## 许可

移植新增代码遵循 BSD-2-Clause-Patent（与 edk2 一致）；移植的 PMON 汇编
遵循其原始 BSD 授权（见文件头）。
