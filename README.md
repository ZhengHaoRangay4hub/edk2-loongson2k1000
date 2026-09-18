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
- **BIOS 界面分辨率自适应**：控制台不再锁定 80×25。四个控制台 PCD
  （`PcdConOutColumn/Row`、`PcdSetupConOutColumn/Row`）设为 0（与 OVMF
  `OvmfDisplayPcds.dsc.inc` 同款），启动时 BDS 自动选择当前分辨率下最大的
  文本模式；同时 `PlatformBm` 让图形控制台独占 ConOut（ConSplitterDxe 会对
  所有 ConOut 设备取文本模式交集，串口终端的固定 80×25/80×50/100×31 会把
  BIOS 界面限制成屏幕中间的小方块）。串口仍输出 DEBUG 日志（不经过 ConOut）。
  效果：1024×768 下界面满屏 128×40（见
  [docs/img/setup-fullscreen.png](docs/img/setup-fullscreen.png)，对比旧版
  居中 640×480 小框），任何分辨率自动适配；纯串口（无显卡）环境保持原样。
- **开机 Logo**：自制发光"龙"启动画面（`assets/logo.bmp`，1024×512，
  Setup 控制台 1024×768），CI 构建时替换上游默认 Logo，
  见 [docs/img/boot-splash.png](docs/img/boot-splash.png)。
- **厂商风格 Setup 主题**：fork EDK2 的 `CustomizedDisplayLib`（厂商定制
  BIOS 界面的官方机制）为 `LoongsonSetupThemeLib`：深蓝底色 + 金色
  "LOONGSON 2K1000LA" FrontPage 横幅 + 反色选中 + 青色帮助栏，
  见 [docs/img/setup-theme.png](docs/img/setup-theme.png)；QEMU 与
  教育派两套固件同享该主题。
- **HDMI 点亮（教育派）**：`LoongsonDisplayDxe` 驱动片上显示控制器
  （PCI 0:6:0，双 DVO 管道 1024x768-32@60，像素 PLL 按分辨率搜索），
  经 I2C1(0x1fe21800) 初始化 SII9022A HDMI 发送器（PMON 9022a.c 序列），
  分配扫描out帧buffer并发布 GOP，同时把启动 Logo 刷上屏；接入
  GraphicsConsoleDxe 后固件文字控制台同步出现在 HDMI。序列移植自
  PMON `dc.c`/`9022a.c`/`i2c.c`；**编译验证通过，实机点灯待教育派
  上电确认**（QEMU 无法模拟 2K1000LA 的 DC）。
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
- **QEMU `ls2k` 闭环烟测**：把教育派那份 `UEFI.fd` 直接喂给
  `qemu-system-loongarch64 -M ls2k`，SEC → PEI → DXE → BDS 全链跑通并落到
  交互式 `Shell>` —— 上机前先在模拟器里确认固件本身能跑。两个约束：
  QEMU 只把 NOR 前 1MB 映射成只读窗口（`DxeIpl` 解压的 LZMA 流必须落在里面），
  且 flash 窗口的写入会被丢弃，所以要用 `-D QEMU_FIT=TRUE` 构建（变量存储改到
  低 DDR 空洞 `0x0F000000`）。**这条路径不覆盖 DC/SII9022A**，HDMI 通路只能在
  真机上验证。
- **真机**：v7 在良好供电下启动正常（上电闪一下、进入 Boot）；HDMI 仍黑屏，
  根因与修复见 [docs/STATUS.md](docs/STATUS.md) 的 P5。首次上电请按
  FLASHING.md 备份并保留串口日志。

## 许可

移植新增代码遵循 BSD-2-Clause-Patent（与 edk2 一致）；移植的 PMON 汇编
遵循其原始 BSD 授权（见文件头）。

## 图形化 BIOS 设置中心：LVGL（移植自上游 YangGangUEFI/LvglPkg）

[Sets up] 集成了上游原版 [YangGangUEFI/LvglPkg](https://github.com/YangGangUEFI/LvglPkg)
（LVGL 在 UEFI 环境的官方移植包），并在其上构建了**全新的图形化固件设置中心**：

- **现代前端风格**：深色渐变背景、圆角卡片、金色强调色、侧边栏导航、
  焦点高亮（非 Demo 的简陋界面）。
- **全中文界面**：自 Noto Sans SC（SIL OFL）生成专用点阵字体（正文 16px /
  标题 24px），LVGL 符号图标经内置字体回退，无缺字。
- **常用设置齐全**（普通电脑 BIOS 都有的项）：
  - 系统信息：处理器型号/主频/架构、内存容量、固件版本、显示输出
  - **性能与超频**：800 / 900 / 1000 / 1100 / 1200 MHz 五档 CPU 主频，
    选择后立即写入 `LoongsonOcCfg` 变量，下次启动由
    `LoongsonOverclockDxe` 应用到 CPU PLL；含风险提示
  - 启动设置：列出全部启动项，选中即设为“下次启动”（写 BootNext）
  - 显示与语言：当前分辨率、自适应策略、主题、界面语言
  - 关于本机：固件/图形库信息与操作提示
- **入口**：启动菜单的 `EFI Firmware Setup`（取代原文本 UiApp 首页）；
  固件同时内置上游 Demo 应用 `UefiDashboard` / `LvglDemoApp`。

截图：[系统信息](docs/img/lvgl-setup-system.png) ·
[性能与超频](docs/img/lvgl-setup-overclock.png) ·
[显示与语言](docs/img/lvgl-setup-display.png)

### 构建与集成说明

- `LvglPkg/LvglLib` 已适配 LoongArch64（架构门控、freestanding 头文件 shim、
  `-Werror` 抑制），随固件构建。
- 上游包本身不含 HII 表单渲染器；本仓库的图形化设置界面即上述
  `LvglSetupApp`（自定义 UI + EFI 变量读写）。
- 上游两个已知问题已在本仓库修复并注明：`LvglDemoApp` 与 `UefiDashboard`
  的 `FILE_GUID` 冲突、`AsciiSPrint` 中 `%s`/`%a` 的 CHAR16/CHAR8 语义差异
  导致中文串乱码。

## USB3 / 存储 / 闪存布局

- **USB3**：板载 ASM1042（PCIe→USB3）走标准 XHCI 驱动，已编入教育派固件，
  与 QEMU 回归固件同一实现（QEMU 下已验证）。
- **存储启动**：USB（EHCI/XHCI + USB 大容量存储）、SATA/AHCI、NVMe。
- **闪存布局**：固件卷 `0x000000..0x370000`，UEFI 变量区
  `0x370000..0x400000`，两者不重叠；刷写与恢复步骤见
  [docs/FLASHING.md](docs/FLASHING.md)。

## PMON 参数对照（设置中心第 5 页）

设置中心内「PMON 参数」页把可调项与固定项列清楚，避免误解：

| 项目 | 状态 |
|---|---|
| CPU 频率 | **可调** 800–1200 MHz（启动时写入 CPU PLL，公式与 PMON `ClkSetting.S` 一致） |
| 启动顺序 | **可调**（BootNext，见「启动设置」页） |
| CPU 电压 | 固定：板级电源决定，PMON 全树无软件调压代码 |
| DDR 频率 | 固定 400 MHz（编译期常量；PMON 同为编译期，改动需重新训练内存） |
| GPU / 显示 / 网口时钟 | 编译期常量（与 PMON `ClkSetting.S` 同源） |
| 串口速率 | 固定 115200 8N1 |

## CI：增量编译缓存

GitHub Actions 现在带三层缓存，避免每次从零编译（实测 5–7 分钟 → 约 1.5 分钟）：

1. `edk2` 源码树 + `Build/` 产物（按 DEBUG/RELEASE 分开），命中后
   `git fetch` 增量更新；
2. 龙芯官方 LoongArch64 交叉工具链；
3. `tools/ci_incremental.py`：用内容哈希比对上次构建，**未改动的文件把
   mtime 归一化为旧时间**（因此不会被重编），改动/新增的保持新时间（重编），
   让 make 的时间戳规则与真实变更一致；QEMU 目标的补丁由幂等脚本
   `tools/patch_qemu_target.py` 完成（内容未变则不落盘，避免触发全量重建）。

## 真机调试记录

- **[docs/STATUS.md](docs/STATUS.md)** —— 按问题组织：每个故障的根因、修复与速查表（串口/引脚复用/供电/启动窗口）。
- **[docs/BRINGUP.md](docs/BRINGUP.md)** —— 按时间线：每一版的现象、定位、修改与结论，含全部镜像 MD5。
- **[docs/BOOTLOG.md](docs/BOOTLOG.md)** —— Flash 进度日志：没有串口时，读芯片就能知道固件跑到哪一步。
- 诊断工具：[tools/read_bootlog.sh](tools/read_bootlog.sh)（读芯片 + 解码）、
  [tools/decode_bootlog.py](tools/decode_bootlog.py)、
  [tools/make_nor_probe.py](tools/make_nor_probe.py)（NOR 低窗口阶梯探针生成器）。
