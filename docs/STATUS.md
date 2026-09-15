# LS2K1000LA 教育派 EDK II 移植：问题与分析总录

> 状态截至 2026-09-15（二更）：**v7 真机验证通过启动**（良好供电下正常进 Boot），
> 但 **HDMI 黑屏**；根因已用出厂二进制实锤定位（见 P5），修复方案已定，待出 v8。
> 按时间线的版本记录见 [BRINGUP.md](BRINGUP.md)；本文按"问题"组织，便于从故障现象反查根因与修法。

---

## 1. 项目概况

| 项 | 内容 |
|---|---|
| 目标 | 全量 EDK II（UEFI）移植到龙芯 2K1000LA 教育派，替换原厂 PMON |
| 构建 | GitHub Actions（增量缓存，~1.5 min/轮），双目标：真机 `Loongson2K1000Pkg` + QEMU 回归 `OvmfPkg/LoongArchVirt` |
| QEMU 侧已验证 | 图形 BIOS、中文 LVGL 设置中心（超频/启动/PMON 参数页）、OpenWrt 24.10 启动 |
| 真机侧现状 | v1–v6 无输出/复位循环（根因见 P1–P4）→ **v7 启动正常**；剩余 **HDMI 黑屏**（根因见 P5，待 v8） |
| 闪存 | W25Q32 4MB：FV 0x0–0x370000，变量区 0x370000–0x400000 |
| 调试通道 | RS232 调试口（59/60）为唯一出厂输出；LVTTL 需固件开引脚复用（v7 起） |

---

## 2. 问题清单（按发现顺序）

### P1 真机串口零输出（v1–v4）

**现象**：QEMU 一切正常；刷入真机后 RS232（59/60）一个字节都没有，HDMI 黑屏。
读取链路已排除嫌疑：STM32 桥 32KB 连续流零丢失；59 脚 −5.14V（mark 空闲）说明接线正确。

**根因是三层叠加**，逐版剥开：

| 层 | 根因 | 修复 | 版本 |
|---|---|---|---|
| ① | `SerialPortLib` 用 OvmfPkg 的 FDT 版 16550 库；真机无 FDT 时 `GetSerialRegisterBase()` **返回 0 不回退**，全部 `DEBUG()` 写地址 0 | 换成原生 `Loongson2KSerialPortLib`（直连 `0x1fe20000`，不依赖 FDT/KS1） | v2 |
| ② | `PreMemInit()` **先初始化 UART 打 banner、后配 APB BAR**；调试串口挂在 APB BAR 之后，banner 写进未路由地址全丢（逆向出厂 PMON 发现其顺序为 SPI→APB BAR→看门狗→UART） | 对齐 PMON 顺序 | v3 |
| ③ | SPI 读时钟分频写了源码默认值 `0x17`，出厂二进制实际为 `0x27` | 对齐 `0x27` | v3 |

**方法论**：capstone 6.0.0a9 逆向出厂 PMON，指令编码全部用真实字节交叉校准；
提取出厂内嵌 DTB 与我们的逐项对比。逆向同时确认以下**一致无需改**：UART 寄存器序列
（分频 54→68、8N1、FCR=0x47）、内存映射（0x200000+0xee00000 / 0x90000000+0x70000000）、
`watchdog_close`、APB BAR 配置代码。

### P2 复位循环：复位灯闪烁/常亮（v5–v6）

**现象**：v5 起复位灯持续闪烁，v6 变常亮；HDMI 黑、串口无声。

**根因 A（结构性）**：SEC 在 `CRMD=0xb0`（分页开、无自有页表）下运行，而真机启动 ROM
只把 NOR 前 **256KB** 拷入片上 SRAM 并映射。固件卷 FFS 解析证明越界访问不可避免：

| 访问对象 | 位置 | 结果 |
|---|---|---|
| SEC / PEI_CORE | ≤0x2A074 | 256KB 内 ✓ |
| 压缩 DXEFV | 0x467E0–0x154396（≈288KB 起） | ✗ |
| DTB 拷贝目的 / PEI 临时栈 | 低地址 DRAM | ✗ 无映射 |

第一次越界访问 → TLB 异常 → EBASE 未设 → 跳垃圾地址 → 外部看门狗复位 → 循环。
QEMU 无此问题的原因：其加载器映射整个地址空间。
**旁证**：PMON 的 start.S 明写 "copy flash code to scache"（拷入 256KB 锁定缓存再跳入），
`LOCK_CACHE_SIZE=0x40000`——原厂引导从不依赖 256KB 之外的取指映射。

**修复**：`CRMD 0xb0 → 0xb8`（DA=1 直接寻址优先于 PG），SEC 全阶段直接物理访问；
后续阶段照常建页表。已反汇编核实编入（v6）。

**根因 B（v5 引入）**：四路串口输出中的 UART4/5（53/54、55/56）默认**未复用**（见 P3），
对未挂时钟的控制器做 MMIO 加剧了不稳定。v6 收敛为 UART0+UART3。

### P3 LVTTL 引脚无输出（贯穿全程，v7 定论)

**现象/疑问**：TTL 串口（8/10、53/54、55/56）始终没有调试输出；板卡手册 8/10 两行
都印 `UART3_TXD`（笔误）。

**数据手册（2K1000LA 处理器用户手册）证据链**：

1. 表 15-1：UART 基址 = BAR + (UART 号 << 8)，BAR=0x1fe20000 → UART0/3/4/5 =
   0x1fe20000/300/400/500；
2. 寄存器 `0x1fe00420`（通用配置 0）`uart0_enable[3:0]` **缺省 0x1 = 4'b0001 =
   "8 线模式（仅 uart0）"**；4'b0011=uart0+uart3；4'b1111=uart0+3+4+5；
   位映射自洽（bit1/2/3 = UART3/4/5 的引脚）；
3. 出厂 PMON 二进制实际对该寄存器 `|= 0x3fd19`（源码注释值 0x1f49 与二进制不符！）
   ——只打开了 uart0 与 uart5 的**引脚**，且从未初始化 uart5 控制器。

**结论**：**出厂状态下没有任何 LVTTL 脚输出调试信息**；唯一输出是 UART0 → 板载 RS232
收发器 → 59/60 脚。缺 M.2 硬盘**不会**导致复位（PMON 无此逻辑；蜂鸣点也在存储枚举之前）。

**修复**（v7）：`UartPinMuxInit()` 在 APB BAR 之后、串口初始化之前，读改写
`0x1fe00420` 将低 4 位置为 `0x3`（uart0+uart3，4 线模式）。已反汇编核实编入。

### P4 供电不足（真正的第一因，最后确认）

**现象转折点**：把**原厂 PMON 完整烧回**后，板子同样复位循环，且蜂鸣器连续"滴滴滴"。

**分析**：PMON 每次开机只在 `locate:` 处响**一声**（`beep_on`→延时→`beep_off`，GPIO39），
位置在关看门狗之后、DDR/PLL 初始化之前。连续蜂鸣 = 反复重启，且每次都死在蜂鸣之后、
恰是**DDR/PLL 拉电流的瞬间**。出厂固件也如此 → 问题不在固件 → 指向供电。
板卡手册要求 **5V≥2A Type-C 且需快充线**；实际供电不足 → 电流尖峰掉压 → 复位循环。

**用户已实测确认：换合格供电后问题消失。** 这也解释了 v1–v6 所有"无输出"为何
连对照实验都做不成——**板子可能从未在良好供电下启动过任何固件**。

**教训（记录在案）**：今后任何"刷完没反应"，先用原厂固件做对照，并第一时间核对
供电规格；固件侧排除法应在确认基础设施（供电/时钟/复位）正常之后进行。

### P5 HDMI 黑屏（v7，根因已实锤）

**现象**：v7 在良好供电下烧入后，机器确实启动（上电闪一下、进入 Boot），
但 HDMI 始终黑屏——**显示链路全程没有点亮**。

**定位方法**：全代码审查 + 对出厂 PMON 备份二进制做定向反汇编
（capstone 6.0.0；注意其对 `lu52i.d` 有解码缺陷，自动扫描会静默中断，关键指令需手工解码）。

**铁证**（出厂备份 `W25Q32_dump_20260915_115813.bin`，文件偏移 0x15e4 起）：

```
0x15e0: ld.w    $a2, $t0, 0        ; 读 [0x1fe00430]
0x15e4: lu12i.w $t1, 0x30          ; t1 = 0x30000
0x15e8: ori     $t1, $t1, 0x12     ; t1 = 0x30012
0x15ec: or      $a2, $a2, $t1      ; a2 |= 0x30012
0x15f0: st.w    $a2, $t0, 0        ; 写回 0x1fe00430 ← pcie0/1 + DVO0/DVO1 引脚输出使能
0x15f4: lu12i.w $t0, 0x1fe00
0x15f8: ori     $t0, $t0, 0x420
0x15fc: lu52i.d $t0, $t0, 0x800    ; t0 = 0x800000001fe00420
0x1600: ld.w    $a2, $t0, 0        ; 读 [0x1fe00420]
0x1604: lu12i.w $t1, 0x3f
0x1608: ori     $t1, $t1, 0xd19    ; t1 = 0x3fd19
0x160c: or      $a2, $a2, $t1
0x1610: st.w    $a2, $t0, 0        ; 写回 0x1fe00420 ← i2c0/i2c1 等外设使能
```

**根因**：`LoongsonPreMem.c` 里唯一携带这两处完整写入的 `GmacAndGeneralCfg()`
**从未被调用（死代码）**。实际执行的初始化序列缺了：

1. **`0x1fe00430` 的 `0x12` 位（DVO0/DVO1 引脚输出使能）**——`PcieEarlyConf()`
   只 OR 了 `0x30000`（pcie0/pcie1）。DVO 引脚不开，DC 配得再对，像素数据也到不了
   SII9022A。**第一杀手。**
2. **`0x1fe00420` 的上位使能位**（出厂实测值 `0x3fd19`，含源码注释所称 i2c0/i2c1
   使能）——`UartPinMuxInit()` 只把低 4 位改为 `0x3`。若 i2c1 使能位复位默认不为 1，
   SII9022A 的 I2C 初始化失败，芯片停在掉电状态，TMDS 无输出。

**已逐项排除嫌疑的环节**（与 PMON 一致或等效）：I2C 底层时序/分频、9022A 寄存器
序列（0xc7/0x1b-0x1d/0x1e/0x1a）、DC pipe 全部寄存器与时序参数、像素 PLL 搜索算法、
SEC 五路 PLL（SYS/DDR/DC/PIX0/PIX1）、DSC/FDF 编入与 DEPEX（PciEnumerationComplete）、
OverclockDxe（只碰 CPU PLL 0x1fe00480）、PCI 主机桥窗口与 DTS 自洽性。

**修复方案（→ v8）**：

| # | 位置 | 改动 |
|---|---|---|
| 1 | `PcieEarlyConf()` | `SYSCONF(0x430) |= 0x30000` 改为 `|= 0x30012`（补 DVO0/DVO1 引脚输出） |
| 2 | `UartPinMuxInit()` | 追加 `Value |= 0x3FD10u`（出厂 0x3fd19 去掉低 4 位；低 4 位保持 0x3，不动 uart 复用） |
| 3 | `LoongsonDisplayDxe.c` | `EFI_HANDLE Handle;` → `Handle = NULL;`（未初始化句柄传给 InstallMultipleProtocolInterfaces，可能致 GOP 安装失败/异常） |
| 4 | `LoongsonDisplayDxe.c` | 帧缓冲改用 `AllocateMaxAddress = 0x0EFFFFFF`（对齐 PMON 低窗 0x05000000 行为，排除 DC DMA 够不到 0x90000000+ 高窗的风险） |

**v8 刷机后判读**：串口出现 `SII9022A not found on I2C1` → I2C1 使能位仍不对；
出现 `GOP ready` 但仍黑 → 复核 DVO 位；两者补齐后预期直接出发光龙 logo。

---

## 3. 当前状态与待验证项（v7 → v8）

**v7 = v2 + v3 + v6 + 引脚复用修复**，已烧入并整片回读校验
（整片 MD5 `3b76cc79d9184ff9b932613671bec607`）。

**v7 真机结果**：良好供电下**启动正常**（上电闪一下、进入 Boot）✅；
**HDMI 黑屏** ❌ —— 根因已定位为 P5（DVO 引脚输出/I2C1 使能所在函数是死代码），
修复方案见 P5 表格，待出 v8 验证。

**v8 刷机后判读**：

| 症状 | 结论/下一步 |
|---|---|
| HDMI 出 logo + 设置中心 | P5 闭环，移植主体完成 |
| 串口有 `SII9022A not found on I2C1` | I2C1 使能位仍不对 → 回查 `0x1fe00420` 实值 |
| 串口有 `GOP ready` 但仍黑 | DVO 位未生效 → 回查 `0x1fe00430` 实值 |
| 串口卡在 DXE | 查 PCIe/NVMe/USB 枚举日志 |

---

## 4. 资产清单

| 资产 | 位置 / MD5 |
|---|---|
| 原厂 PMON 备份（恢复用，务必保留） | `~/Downloads/CH341A/W25Q32_dump_20260915_115813.bin`，`d1d3da6bcea4067bb5b67f54e1f3415d` |
| v7 整片镜像（当前板上内容） | `~/Downloads/ls2k-new-v7/UEFI_4MB_v7.bin`，`3b76cc79d9184ff9b932613671bec607` |
| 各版镜像 v2–v6 | `~/Downloads/ls2k-new*/`，MD5 见 BRINGUP.md |
| 阶梯探针（低窗口取指诊断） | `~/Downloads/ls2k-new/PROBE_nor_window_test.bin`，`27b2c9c67a9ec808149287c80c2426e8` |
| 烧录脚本（备份→复读校验→写→回读比对） | `~/Downloads/CH341A/flash_v*.sh`、`flash_pmon_restore.sh` |
| 串口抓取工具（支持 CH340/STM32 桥） | `stm32-rs232-bridge/capture.py` |
| 出厂固件逆向工具（探针生成器） | `tools/make_nor_probe.py` |
| 2K1000LA 处理器用户手册 | 中科大镜像（233 页 PDF，引脚复用/寄存器依据） |

## 5. 关键硬件事实（速查）

- **调试串口**：UART0 @ `0x1fe20000` → RS232 收发器 → 排针 59(TXD)/60(RXD)，GND 57/58；
  PMON 早期分频 54（PLL 前）→ 68（PLL 后，125MHz APB）；8N1；FCR=0x47
- **TTL 口**：UART3 @ `0x1fe20300` → 排针 8(TX)/10(RX)/9(GND)（手册 8/10 双印 TXD 为笔误）；
  需 `uart0_enable=0x3` 才接通引脚（v7 起固件自开）
- **UART4/5**：53/54、55/56；需 `uart0_enable=0xF`（2 线全开），默认死
- **引脚复用寄存器**：`0x1fe00420`（通用配置 0）；出厂 PMON 实际写 `|= 0x3fd19`
- **通用配置 2**：`0x1fe00430`；出厂 PMON 实际写 `|= 0x30012`（pcie0/pcie1 +
  **DVO0/DVO1 引脚输出使能 `0x12`**——HDMI 通路必需，出厂二进制 0x15e4 处实锤）
- **蜂鸣器**：GPIO39，PMON 每次开机一声；连续响 = 反复重启的指纹
- **供电**：5V ≥2A Type-C，**必须快充线**；不足则 DDR/PLL 电流尖峰引发复位循环
- **启动窗口**：启动 ROM 仅映射 NOR 前 256KB（拷入片上 SRAM）；固件不可依赖之外的取指
  （我们的方案：SEC 用 DA=1 直址；PMON 的方案：拷入 256KB 锁定缓存执行）
- **EJTAG**：从 CPU 引出但未焊连接器；官方 `la_dbg_tool_usb` 支持 2K1000LA，
  开源替代 pico-loongson-ejtag（RP2040）
