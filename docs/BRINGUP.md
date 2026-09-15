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

## 镜像版本一览

| 版本 | commit | 整片镜像 MD5 | 要点 | 真机结果 |
|---|---|---|---|---|
| v2 | 6a54de7 | `9516dfc2...fcf3` | 原生串口库 | 零输出 |
| v3 | d144ab2 | `f59544a6...4adb` | SEC 顺序 + SPI 分频 | （并入 v4） |
| v4 | 921d853 | `04828616...a675` | 控制台切 TTL+镜像 | （并入 v5） |
| v5 | 0456af1 | `5fd0fe45...54fd` | 四路输出 | **复位循环** |
| v6 | ca04c90 | `ffdedf63...9423` | DA=1 + 串口收敛 | 待验证 |
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
