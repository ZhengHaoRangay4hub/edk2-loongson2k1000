# 真机调试过程记录（bring-up log）

按时间顺序记录把 EDK II 从「QEMU 能跑」带到「真机教育派」的每一步：现象、定位、
修改、结论。每一节对应仓库里的一次（或一组）提交，镜像 MD5 可用于对照手头的产物。

反向阅读也成立：从现象（串口无声 / 复位灯闪 / HDMI 黑）出发，能在本文件里找到
当时的原因与修法。

---

## 背景：为什么真机和 QEMU 表现不同

移植最初在 QEMU（`OvmfPkg/LoongArchVirt`）上验证：图形 BIOS、中文 LVGL 设置中心、
超频页、OpenWrt 启动全部工作。刷到教育派真机后**串口零输出、HDMI 黑屏**。
后续全部调试都在回答同一个问题：真机和 QEMU 差在哪。

关键差异（后来逐条证实）：

| | QEMU | 真机（教育派） |
|---|---|---|
| 串口定位 | FDT（QEMU 生成的设备树） | 无 FDT 可用（见 v2） |
| 地址映射 | 加载器映射整个地址空间 | 启动 ROM 只映射 NOR 前 256KB（见 v6） |
| UART 实例 | 只有一个 virtio/16550 | 12 个 UART，引脚复用决定哪些活着（见 v5/v6） |

---

## v1（commit 02515f0..b195a10 之前）——「零输出」的最初形态

**现象**：刷入后串口（RS232，教育派 59/60 脚）一个字节都没有；HDMI 黑屏。

**当时已知**：
- 镜像本身完整（CH341A 写入后回读 MD5 一致）；
- 用 STM32 桥短接 DB9 做回环，桥本身 32KB 连续流零丢失——**读取链路是好的**；
- 教育派 59 脚能量到 −5.14V（RS232 空闲 mark），60 脚 −5.41V——**接线方向正确**。

---

## v2（commit 6a54de7）——串口库不依赖设备树

**定位**：`SerialPortLib` 用的是 OvmfPkg 的 **FDT 版 16550 库**。它先查 CSR KS1，
再从 `PcdDeviceTreeInitialBaseAddress` 指向的设备树里解析 `stdout-path`。真机上两者
皆空 → `GetSerialRegisterBase()` **返回 0**，且不回退：

```c
if (RETURN_ERROR (FdtSerialGetConsolePort (Base, &SerialConsoleAddress)))
  return (UINTN)0;          // ← 之后所有 DEBUG() 写到地址 0
```

所有 PEI/DXE 的 `DEBUG()` 输出写到地址 0 并在"地址 5"轮询一个永远不就绪的 LSR。

**修改**：新增 `Library/Loongson2KSerialPortLib`，直接用 SoC 固定 MMIO 地址驱动
UART0（`0x1fe20000`，时钟 125MHz，分频 68 = `125M/(16×115200)`），不依赖 FDT 与 KS1；
`PlatformHookLib` 换成 Null 实现。QEMU 目标不受影响（它用独立的 DSC，
串口在 `0x1fe001e0`，继续用 FDT 库）。

**产物**：`UEFI_4MB_ls2k1000la_v2.bin`，MD5 `9516dfc227d9947f0d61d4193c46fcf3`。

**结果**：真机仍然零输出 → 说明问题比"PEI 之后没打印"更早，SEC 本身就没跑到打印。

---

## 逆向原厂 PMON（无代码修改，方法论记录）

用户要求对出厂固件做逆向对比。备份镜像 `W25Q32_dump_20260915_115813.bin`
（MD5 `d1d3da6bcea4067bb5b67f54e1f3415d`，两次复读一致）。

工具链：本机 capstone 5 无 LoongArch 后端 → 升级 capstone 6.0.0a9 ✓。
逆向过程中所有指令编码都用**出厂二进制的真实字节**交叉校准（校准过程本身揪出了
自制编码器的 3 处错误）。

**逆向确认与我们的移植一致的**（不需要改）：

- UART0 `0x1fe20000`；早期分频 `0x36`=54（PLL 前）、PLL 后 `0x44`=68；8N1；FCR=`0x47`
- 内存映射 `0x200000+0xee00000` / `0x90000000+0x70000000`（与出厂内嵌 DTB 完全一致）
- `watchdog_close`（清 `0x1fe00500` 与 `+0x10` 的 bit3）逐字节相同
- APB BAR 配置代码（`0xfe00001010 = 0x1fe20000`）等价

**逆向发现的两个真实差异**（→ v3）：

1. **顺序**：PMON 是「SPI 提速 → **APB BAR** → 看门狗 → **UART 初始化** → 打印」；
   我们是「**UART 初始化 → 打印 banner** → … → **APB BAR**」。调试串口挂在 APB BAR
   之后——banner 写进了尚未路由的地址，全部丢失。
2. **SPI 读时钟分频**：出厂二进制写 `0x27`；我们写的 `0x17` 只是 PMON 源码里
   `BOOT_SPI_FREQ` 未定义时的默认值。

另发现 PMON 从不直接在 NOR 上执行：`start.S` 把自身代码拷进 **256KB 锁定缓存**
（`LOCK_CACHE_SIZE = 0x40000`）再跳进去。当时未意识到这是伏笔（→ v6）。

---

## v3（commit d144ab2）——SEC 启动顺序对齐 PMON

**修改**：
1. `PreMemInit()` 改为 PMON 的顺序：SPI 提速 → APB BAR → 看门狗 → UART 初始化 → 打印；
2. SPI 分频 `0x17` → `0x27`。

**产物**：`UEFI_4MB_v3.bin`，MD5 `f59544a6be922591b73b21456be24adb`。

（此版未单独上机验证——与 TTL 切换合并成了 v4。）

---

## v4（commit 921d853）——控制台切到 TTL 串口

用户要求改用 TTL。教育派共 3 路 LVTTL + 1 路 RS232；当时无法确认引脚复用状态，
所以做成**主口 UART3（TTL，8/10）+ 镜像 UART0（RS232）**双路输出。
DTB 增加 `uart3` 节点、`stdout-path` 指向 TTL 口。

**接线**（教育派排针）：**8 = TXD3，10 = RXD3，9 = GND**；CH340 电平跳线拨 **3.3V**。
（手册 8/10 两行都印成 `UART3_TXD`，系笔误；8=发/10=收，符合 53/54、55/56 的成对规律。）

**产物**：`UEFI_4MB_v4.bin`，MD5 `048286165aa1b328930142025ba8a675`。

---

## v5（commit 0456af1）——四路串口输出（含一次错误决策）

用户提出"不止一个 TTL 串口"。改为**四路全输出**（UART0/3/4/5）+ 四路输入轮询；
镜像口采用有上限的等待（防未挂时钟的 UART 永不就绪把固件卡死）。

**产物**：`UEFI_4MB_v5.bin`，MD5 `5fd0fe4574ba87f8c530ae7f60a854fd`。
烧写记录：备份 MD5 `27ffcbd7778a91cbad83cec949f65756`（上一版），写入回读一致 ✓。

**上机结果**：**复位灯持续闪烁 + HDMI 黑** —— 复位循环。

---

## v6（commit ca04c90）——修复复位循环

### 根因一（结构性，v1 起就存在）：SEC 开分页却无页表

- `CRMD=0xb0` → PG=1、DA=0（分页翻译）；
- 真机启动 ROM 只把 NOR **前 256KB** 拷进片上 SRAM 并映射；
- 固件卷布局（对 v6 产物解析 FFS 得到）：

  | 文件 | 偏移 | 说明 |
  |---|---|---|
  | SEC | 0x000FE8-0x013014 | ✓ 256KB 内 |
  | PEI_CORE | 0x013FE8-0x02A074 | ✓ |
  | **压缩 DXEFV** | **0x0467E0-0x154396** | ✗ 288KB 起 |
  | DTB 目的地址 | 低地址 DRAM | ✗ 无映射 |
  | PEI 临时栈 | DRAM | ✗ |

- 第一次越界访问 → **TLB 异常** → EBASE 尚未设置 → 跳到垃圾地址 → 外部看门狗复位 → 循环。
  QEMU 无此问题因为其加载器映射了整个地址空间。
- 伏笔的印证：PMON 的 `start.S` 明写 "copy flash code to scache"（拷进 256KB 锁定缓存
  再跳进去），配合 `LOCK_CACHE_SIZE = 0x40000`——它从不依赖 256KB 之外的取指映射。

**修改**：`CRMD` `0xb0` → `0xb8`（**DA=1 直接寻址**，优先级高于 PG）。SEC 全阶段
直接物理访问、不查 TLB；后续阶段照常建页表。已在产物中反汇编核实
（SEC 入口 `ori $t0, $zero, 0xb8` ✓）。

### 根因二（v5 引入）：串口打到了未启用的 UART

查《龙芯 2K1000LA 处理器用户手册》（233 页）：

- 表 15-1：UART 基址 = BAR + (UART 号 << 8) → UART0/3/4/5 = `0x1fe20000/300/400/500`；
- 5.2 节：`uart0_enable` **默认 0x1 = 4 线模式 =「uart0 + uart3」**；
- 表 2-22/2-39：UART4/UART5 仅在 4×2 模式下存在。

即默认只有 **UART0 + UART3** 活着；v5 的四路输出有两路在打未复用、未挂时钟的串口。

**修改**：收敛为 UART0（RS232，59/60，主口）+ UART3（TTL，8/10，镜像）。
另：`GmacAndGeneralCfg()` 中 `SYSCONF(0x420) |= 0x1f49` 会破坏 `uart0_enable`，
但该函数未被调用（死代码），记录在案。

**产物**：`UEFI_4MB_v6.bin`，MD5 `ffdedf63200887a7798606f8f1679423`（固件卷
`36295842fae9906b8c6a868dd04f68a1`）。

**上机预期**：复位灯不再闪；串口输出 `Loongson2K1000LA EDK2 SEC booting...` 起
的 SEC/DDR 日志；DDR 顺利则 HDMI 出 logo 与设置中心。

---

## v8 ——HDMI 黑屏根因修复（DVO 引脚输出 + I2C1 使能）

**现象（v7 上机）**：良好供电下正常进 Boot（上电闪一下），HDMI 全程黑屏。

**根因（出厂二进制实锤）**：逆向出厂 PMON 备份，0x15e4 处 `0x1fe00430 |= 0x30012`
（pcie0/1 + **DVO0/DVO1 引脚输出使能 0x12**），0x1604 处 `0x1fe00420 |= 0x3fd19`
（含 i2c0/i2c1 使能）。这两处完整写入只存在于 `GmacAndGeneralCfg()`——而该函数
**从未被调用（死代码）**；`PcieEarlyConf()` 只 OR 了 `0x30000`，DVO 引脚没开，
SII9022A 收不到像素时钟；I2C1 使能位也可能缺失导致 9022A 初始化失败。
（逆向注意：capstone 6.0.0 对部分 `lu52i.d` 编码解码失败会静默截断反汇编流，
关键序列需手工解码核对。）

**修改**：
1. `PcieEarlyConf()`：`SYSCONF(0x430) |= 0x30000` → `|= 0x30012`；
2. `UartPinMuxInit()`：追加 `Value |= 0x3FD10u`（出厂上位使能位，低 4 位保持 0x3）；
3. `LoongsonDisplayDxe`：GOP 句柄初始化 `Handle = NULL`（原为未初始化栈值）；
4. `LoongsonDisplayDxe`：帧缓冲改 `AllocateMaxAddress = 0x0EFFFFFF`
   （对齐 PMON 低窗 0x05000000 的已验证行为）；
5. `LoongsonDisplayDxe`：GOP Blt 去掉 R/B 互换——PMON `FILL_32BIT_X888RGB`
   原样存 `0x00RRGGBB`（`VIDEO_FB_LITTLE_ENDIAN` 未定义，`SWAP32` 是恒等），
   与 GOP 声明的 `PixelBlueGreenRedReserved8BitPerColor` 及 BltPixel 布局一致，
   原 swap 会让 UEFI 侧绘制内容红蓝颠倒；顺带补上 `EfiBltVideoFill` 缺失的
   cache flush，并把 `EfiBltBufferToVideo` 的 flush 范围修正为按 stride 跨行
   （原 `Width*4*Height` 连续区间在部分区域 blt 时漏刷）。

**上机预期**：HDMI 出发光龙 logo 与设置中心。判读：串口有
`SII9022A not found on I2C1` → 查 `0x1fe00420`；有 `GOP ready` 但黑 → 查 `0x1fe00430`；
画面红蓝互换 → 回查 Blt/PMON 像素序。

---

## QEMU `ls2k` 闭环烟测 —— 上机前先证明固件本身能跑

**为什么做**：到 v8 为止，每次判断"固件到底行不行"都要烧一次真机，而真机只有
RS232 一路输出（HDMI 还黑，P5），一次上机成本很高。QEMU 的 `ls2k` 机器建模了
2K1000LA 的 CPU / DDR / PCI / 串口，可以把**同一份 `UEFI.fd`** 从 SEC 一路带到
BDS —— 反馈快、可反复重跑，用来把"刷上去看运气"换成"先在模拟器里跑通"。

**板级参数的来源**：内存映射（`0x200000+0xee00000` / `0x90000000+0x70000000`）、
UART0 分频（PLL 前 54 / 后 68）、`0x1fe00420` 与 `0x1fe00430` 两处使能位，都来自
逆向出来的出厂 PMON（见上文 v3 / v8 两节），与 QEMU 的建模逐项交叉核对过。

**QEMU `ls2k` 的两个硬限制**（决定了这个镜像要怎么出）：

| 限制 | 后果 | 处理 |
|---|---|---|
| NOR 只读窗口只有前 1MB（`0x1c000000-0x1c0fffff`，`romd`），窗口之外读回 0、写入丢弃 | `DxeIpl` 解压 `FVMAIN_COMPACT` 时越过 1MB 会被截断 | 压缩后必须 < 1MB：当前用量 811,040 B（卷容量 `0x370000`，22%） |
| flash 窗口的写入被丢弃 | 变量存储永远格式化失败，`gEdkiiNvVarStoreFormattedGuid` 无人安装 → DxeCore 断言 | `-D QEMU_FIT=TRUE` 用 `LoongsonQemuNorFlashDeviceLib` 在 DRAM 上模拟 NOR 语义，变量区搬到低 DDR 空洞 `0x0F000000` |

**跑通这条路径时修掉的缺陷**：P6（BDS 不自动启动 Shell）、P7
（`PcdShellLibAutoInitialize` 挂错组件，Shell 一启动即 ASSERT —— **真机同样中招**）、
P8（QEMU_FIT 缺 `gEfiFormBrowser2ProtocolGuid`），以及 RTC / PCI root bridge
两处断言。全部根因见 [STATUS.md](STATUS.md)。

**结果**：

```
BdsDxe: loading Boot0000 "EFI Internal Shell" from Fv(5D19A5B3-...)/FvFile(7C04A583-...)
UEFI Interactive Shell v2.2
EDK II
UEFI v2.70 (EDK II, 0x00010000)
Mapping table
map: No mapping found.
Press ESC in 2 seconds to skip startup.nsh or any other key to continue.
Shell>
```

同一镜像在 `QMEM=2048` 与 `QMEM=1024` 下都到达 `Shell>`（变量区在 `0x0F000000`，
两种内存下都在低窗口中）。

**这条路径覆盖不到什么**（别误读结论）：**出厂** 3.1 QEMU 的 `ls2k` 不建模
DC / SII9022A / I2C，**HDMI 通路（P5）在那里无法验证**；它证明的是
「SEC → PEI → DXE → BDS → 控制台 → Shell」这条软件链路在真实固件镜像上成立。

> 后续进展（2026-09-16 深夜）：正在把 `ls2k` 机器移植到 **QEMU 8.2**（`foxsen/qemu-up`
> 的 `ls2k1000` 分支）并**补建模缺失外设**——`hw/display/sii9022.c`（SII9022A HDMI
> 发送器）已挂到 I2C1 @ `0x39`，另有 `ls2k_apb.c` / `ls2k_pci_stub.c` 及一批逐 fault
> 补的寄存器。固件在新 QEMU 上已从「46 字节串口」推进到 PEI，当前卡在双核 host
> SIGSEGV。细节见 [QEMU-PORT.md](QEMU-PORT.md)，接手入口见 [HANDOVER.md](HANDOVER.md)。

---

## 镜像版本一览

| 版本 | commit | 整片镜像 MD5 | 要点 | 真机结果 |
|---|---|---|---|---|
| v2 | 6a54de7 | `9516dfc2...fcf3` | 原生串口库 | 零输出 |
| v3 | d144ab2 | `f59544a6...4adb` | SEC 顺序 + SPI 分频 | （并入 v4） |
| v4 | 921d853 | `04828616...a675` | 控制台切 TTL+镜像 | （并入 v5） |
| v5 | 0456af1 | `5fd0fe45...54fd` | 四路输出 | **复位循环** |
| v6 | ca04c90 | `ffdedf63...9423` | DA=1 + 串口收敛 | （并入 v7） |
| v7 | c76951b | `3b76cc79...c607` | UART3 引脚复用 | **启动正常**，HDMI 黑 |
| v8 | （本提交） | 见 CI 产物 | DVO/I2C1 使能 + GOP 修复 | 待验证 |

整片镜像 = 新 `UEFI.fd`（0x0-0x370000）+ 保留变量区（0x370000-0x400000）。
原厂 PMON 备份：MD5 `d1d3da6bcea4067bb5b67f54e1f3415d`（恢复用，务必保留）。

## 烧写与回读

```bash
cd ~/Downloads/CH341A
./flash_v6.sh        # 备份→复读校验→写入→整片回读比对，全自动
```

## 下一步（若 v6 仍有问题）

- 串口有输出但停在某一行的：
  - 停在时钟阶段（`Soft CLK SEL adjust`）→ 核对 PLL 参数与 PMON 的差异；
  - 停在 `Start Init Memory` → DDR 参数表（`loongson_mc2_param.S`）与本机颗粒不符，
    需按出厂 PMON 的 AUTO_DDR_CONFIG 路径重核；
- 完全无输出且仍复位循环 → 刷阶梯探针 `PROBE_nor_window_test.bin`
  （MD5 `27b2c9c67a9ec808149287c80c2426e8`，5 级阶梯沿低窗口逐级外跳，
  打印到第几级＝低窗口取指真实上限）；
- 串口通、卡 DXE → 接着查设备枚举日志（PCIe/NVMe/USB）与 HDMI 通路
  （DC PLL、SII9022A 的 I2C 时序）。

---

## v8（待上机）——真机镜像（含 P5 显示修复）

| 项 | 值 |
|---|---|
| 整片镜像 | `~/Downloads/ls2k-new-v8/UEFI_4MB_v8.bin` |
| **MD5** | `eeb876f5ddb4eec415178b1003b93261` |
| 固件卷 MD5 | `c78f0687707b56d39971be8a34cb97b4` |
| 变量区 | 沿用板上 v7 的变量区（0x370000-0x400000） |
| 内容 | P5 修复（DVO 引脚输出 + I2C1 使能启用）+ GOP Blt 修复 + QEMU 闭环期间的全部真机侧修订 |

构建来源：工作区（含未提交的 QEMU 支持改动，与 QEMU 闭环所用源码一致）。
**上机判读**：HDMI 出龙 logo + 设置中心 → P5 闭环；`SII9022A not found on I2C1` → 回查
0x1fe00420 实值；`GOP ready` 仍黑 → 回查 0x1fe00430 的 DVO 位。

QEMU 侧同日达成闭环（SEC→Shell>，截图非黑），过程与配方见 QEMU-PORT.md。

---

## v9（已刷入待验证）——Flash 进度日志（黑匣子）

| 项 | 值 |
|---|---|
| 整片镜像 | `~/Downloads/ls2k-new-v9/UEFI_4MB_v9.bin` |
| **MD5** | `035cc3138ee0170be003f1bba89e623f` |
| 固件卷 MD5 | `c6eaac973b902aa106af2cff65d4ae0e`（0x360000） |
| 烧录记录 | 写入 VERIFIED、整片回读一致（2026-09-18 17:03） |

**新增能力**：固件把 26 个启动里程碑写进 NOR 的 `0x360000-0x370000`，
所以**没有串口也能知道跑到哪一步**——上电后取下芯片用 CH341A 读、跑
`tools/read_bootlog.sh` 即出结论。详见 [BOOTLOG.md](BOOTLOG.md)。

**布局变化**：FV 从 0x370000 缩到 0x360000（实际占用 1.40 MB），腾出 64KB 作日志区；
变量区仍在 0x370000 不变。

**QEMU 验证**：窗口扩到 4MB（真机芯片大小）、去掉本地总线 flash 对 1MB 以上的遮蔽后，
同款固件在 QEMU 里正确写出并可解码全部 SEC+PEI 里程碑 ✓；解码器另用合成用例覆盖
DXE/BDS 事件码 ✓（板级镜像在 QEMU 里卡在 DxeIpl 解压 10.4MB 卷，是模拟器速度问题）。

**上机判读**：取下芯片读日志——若显示到 `0x30 BDS` 且 HDMI 亮 = 全通；停在
`0x0B` = DDR；停在 `0x2B/0x2D` = 显示通路；连日志头都没有 = 极早期或编程通路问题。

---

## v11（待刷）——把 flash 日志摘出启动路径，蜂鸣器改成扫频

前面两次上机都是**一声都没有**，这一版针对这两处根因各动一次手。

### 一、flash 日志从启动路径编译掉（`BOOTLOG_FLASH_ENABLE=0`）

`LoongsonBootLogBoot()` 挂在 SEC 的**第一条**指令后面，而它做的事是写 SPI 控制器的
`SPSR`/`SPER`/`SPCR`/`PARAM2`——**CPU 自己的取指正走在这个控制器上**。这条路径从加进来
起就没有产出过一个可读字节（`0x360000` 的日志区始终是空的），却在每次上电最先执行，
是"连第 1 声都没有"的头号嫌疑：一旦它把取指通路弄坏，后面的 `PreMemInit`、蜂鸣器
一个都到不了。

所以这一版把 SPI 原语与 `LogWrite` 整段用 `#if BOOTLOG_FLASH_ENABLE` 关掉，两个 API
变成 4 字节的 `ret`（`LoongsonBootLogBoot`/`LoongsonBootLogEvent` 的符号大小都是 4，
已从 `SecMain.debug` 复核）。代码留在树里，等运行在 DRAM 的阶段再接回来——
那时写 flash 不再动自己的取指通路。

### 二、蜂鸣器：只在**已经听到过**的频段里扫频

软件方波的音高取决于这段代码多快能翻转 GPIO，而 SEC 在不带 cache 的启动窗口里跑，
每次取指都是一次总线往返——**这个耗时从外部推不准**。前两次正是猜它猜错的：

| 版本 | 参数 | 结果 |
|---|---|---|
| 早先 | 半周期 0x08 | 听到 1 声 |
| v10 | 半周期 0x03 | 一声都没有（太快，落进听不见的频段） |
| 早先扫频试验 | 0x40/0x100/0x400/0x1000 | **四声都听见了**（都偏低） |

v11 据此把蜂鸣声做成**扫频**：半周期按 `0x40 → 0x80 → 0x100 → 0x200` 每 8 个半周期
换一档，四档全部取自"板上确实响过"的取值。听感是抖音、发沙，但**每一档都在能听见的
范围内**，不会整声落空。延时常量用移位算出（`0x40 << ((Half/8) & 3)`）而不是查表——
查表是一次只读数据访问，而这里唯一确定可取的只有代码本身。

判读（`Start.S` 里 `LoongsonBootBeep(N)` 的调用点）：

| 听到 | 含义 |
|---|---|
| 1 声 | SEC 跑起来了，SoC 窗口/SEC 早期初始化通过 |
| 2 声 | UART 初始化完成（控制台活着） |
| 3 声 | 时钟/PLL 设定完成 |
| 4 声 | **DDR 初始化完成**（内存起来了） |
| 5 声 | SEC 结束，交棒 PEI |
| 长鸣 | 进了设置菜单 |

### 三、这一版同时带着的两处修复（v10 起）

- `PciePhyWrite()` 的等待改成有界（`Guard=100000`）：原样照抄 PMON 的"等 PHY done 位"
  在这块板上永远等不到，固件就停在**第 1 声之后、第 2 声之前**——正好对上"1 声就没有了"。
- DDR 参数表 192 项与出厂 PMON 逐字节对齐，`$s1` 用出厂值 `0xc0a18404`（我们原先错用
  源码默认的 `0xf0a31004`）。

### 四、镜像与验证

| 项 | 值 |
|---|---|
| 真机固件卷 | `~/Downloads/CH341A/uefi_beep3.fd`，983,040 B（0xF0000，1MB 窗口内） |
| **MD5** | `3373086bec86d7a5e2a2fc56669397b7` |
| 构建 | `/root/ls2k.sh build -D QEMU_FIT=TRUE -D BOARD_MIN=TRUE` |
| QEMU 闭环 | 同源码另加 `-D PREMEM_STACK_TOP=0x90040000`，QEMU 8.2 上 18 s 到 `Shell>`、串口 59,588 B、`GOP ready (1024x768-32)`、DC 寄存器 `0x60001240` 有值 ✓ |
| 烧录脚本 | `~/Downloads/CH341A/flash_beep3.sh <镜像>`（先读→比 MD5→写→回读→比 MD5） |

**烧录记录（2026-09-19 18:13）**：

| 步骤 | 结果 |
|---|---|
| 刷前读芯片（前 1MB） | MD5 `85416fae14b2b299432964c2ec4a332a`——**板上是上一版 EDK II**，不是 PMON |
| 写入 | `Erase/write done from 0 to fffff`（只写 boot1m 区） |
| 回读比对 | 前 983,040 B 与镜像**逐字节一致** ✓；`0xF0000-0x100000` 为擦除态 `0xFF` ✓；1MB 以上未被写 ✓ |

**踩坑（写下来免得再犯）**：flashrom 的 layout 模式（`-l 布局 -i 区域 -w 镜像`）**要求镜像是整片大小**，
喂给它 960 KB 的固件卷会直接报 `Image size (983040 B) doesn't match the expected size (4194304 B)`；
`-r` 读回来也是整片大小的文件。所以 `flash_beep3.sh` 现在会自动把镜像补 `0xFF` 到 4 MB 再写，
比对时也只比固件卷那一段（拿补齐后的 4 MB 整片去比回读，会把 1MB 以上的旧内容也比进去，
得出假的"不一致"）。另外之前那次 `LIBUSB_ERROR_ACCESS` 是 macOS 上 USB 驱动抢占的**偶发**问题，
与 CH341A 的 TTL/SPI 模式无关——适配器一直就是 SPI 模式（实测可直接烧）。
