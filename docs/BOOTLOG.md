# Flash 进度日志（黑匣子）

> 目的：**没有串口也能知道固件走到哪一步。**
> 每次上电后把芯片取下来用 CH341A 读一遍，就能看到固件跑到哪个里程碑、带什么参数。

## 1. 怎么用（三步）

```bash
# 1) 板子上电（日志会累积"自上次擦除以来走到的最远一步"）
# 2) 断电，把 NOR 芯片夹到 CH341A 上（模式跳线在 SPI 位）
# 3) 读出来并解码：
~/Documents/sovints/ls2k1000la-edk2/repo/tools/read_bootlog.sh
```

输出示例（一次真实运行，QEMU 里同款固件）：

```
boot log at file offset 0x0 (format v1)
write-only log: shows the furthest progress since the region was erased

  0x01  info   SEC entry (reset vector reached us)
  0x02  info   SEC spi flash speedup done
  0x03  info   SEC APB window opened
  0x04  info   SEC uart pin mux set [uart0_enable = 0x9]
  ...
  0x0d  info   SEC device tree copied [11723 bytes]
  0x0e  info   SEC handing over to PEI
  0x10  info   PEI core entry
  0x11  info   PEI low RAM described [238 MB]
  0x12  info   PEI high RAM described [1792 MB]
  0x13  info   PEI device tree relocated [0xffd000]

  -> last milestone reached: PEI device tree relocated
```

**最后一行就是结论**：固件停在那里或之后。

也可以只解码已有的 dump：

```bash
python3 tools/decode_bootlog.py chip.bin          # 4MB 整片 或 64KB 日志区
python3 tools/decode_bootlog.py chip.bin --hex    # 附带原始字节
```

## 2. 布局与语义

| NOR 偏移 | 内容 |
|---|---|
| `0x000000-0x360000` | 固件卷 FV |
| **`0x360000-0x370000`** | **进度日志（16 字节头 + 每个事件码 4 字节槽位）** |
| `0x370000-0x3B0000` | UEFI 变量存储 |
| `0x3B0000-0x3C0000` | 变量 FTW 工作区 |
| `0x3C0000-0x400000` | 变量 FTW 备用区 |

- **头部**：`"BLOG"` + 版本号；写入即代表固件至少跑到了第一个里程碑。
- **槽位**：`offset = 0x360000 + 16 + 事件码 × 4`，3 字节小端参数 + 1 字节标记 `0x5A`。
- **只写不读、不擦除**：固件从不擦除这个区域，也不回读它——每次启动把相同的字节写进相同的槽位
  （NOR 只能 1→0，重复写同值是空操作），所以日志**累积"自上次刷写/擦除以来达到的最远进度"**。
  想看一次干净的单次启动记录，用编程器把这 64KB 擦掉即可（或重新刷固件，镜像里该区是 0xFF）。

## 3. 为什么这样设计（踩过的坑）

1. **不能依赖窗口读**。`0x1c000000` 的 XIP 窗口只有**前 1 MB** 是 SPI 芯片；再往上启动
   绑带把本地总线 flash 映射进来（这块板没装），读回 0、写入丢弃。日志区在 3.375 MB 处，
   所以固件侧一律**不读** flash，事件直接写各自固定的槽位。
2. **不能擦除**。4KB 扇区擦除会让芯片忙几十毫秒，而此刻 CPU 还在从同一片 flash 取指——
   风险太大。改为"只编程、不擦除"，配合固定槽位天然去重。
3. **不能有全局变量**。SEC 在 NOR 上 XIP 执行，`.data/.bss` 落在 flash 里、写进去就丢，
   所以库里一点状态都不存。
4. **标记字节必须显式**。擦除态是 `0xFF`，而 QEMU 的 flash 模型对镜像范围外返回 `0x00`——
   两个"空"值不同，只靠"非 0xFF"或"非 0x00"判定都会误判，所以用 `0x5A` 做标记。
5. **超过 24 位的值要编码**：`BAR0` 存 `>>12`（解码显示 `0x…000`），分辨率存
   `width<<12 | height`（两者各不超过 12 位）。

## 4. 事件码表

见 `platform/Loongson/Loongson2K1000Pkg/Include/Library/LoongsonBootLog.h`，与
`tools/decode_bootlog.py` 的 `EVENTS` 字典一一对应。分四段：

| 段 | 事件 |
|---|---|
| `0x01-0x0E` | SEC：入口、SPI 提速、APB 窗口、引脚复用、看门狗、串口、PCIe、SoC 完成、时钟起止、DDR 起止、DTB、交棒 PEI |
| `0x10-0x14` | PEI：入口、低/高内存、FDT 重定位、完成 |
| `0x20-0x2D` | DXE：显示驱动入口、DC BAR0、BAR0 回退、SII9022A 找到/未找到、GOP 就绪/失败 |
| `0x30-0x32` | BDS：入口、启动尝试、Shell |
| `0xE0-0xE2` | 错误：断言、CPU 异常、hang |

## 5. 失败判读

| 现象 | 含义 |
|---|---|
| 日志头都没写（全 `0xFF`） | 固件没跑到第一个里程碑，或 flash 编程通路失败 |
| 停在 `0x04` 之前 | 极早期（SPI/APB 配置）就挂了 |
| 停在 `0x09/0x0A` | 时钟 PLL 阶段 |
| 停在 `0x0B` | DDR 初始化（最常见，参数与颗粒不符） |
| 停在 `0x0D`（`[NOT FOUND]`） | 固件卷里没找到设备树 |
| 停在 `0x11/0x12` | PEI 内存描述 |
| 停在 `0x20-0x2D` | 显示通路（`0x2B` = I2C1 上没找到 SII9022A；`0x2D` = GOP 安装失败） |
| 到 `0x30` 且 HDMI 亮 | 全通 |

## 6. 相关提交

- `Library/LoongsonBootLogLib` —— 库本体（SPI 编程原语 + 固定槽位写入）
- `Include/Library/LoongsonBootLog.h` —— 事件码
- 插桩点：`Sec/LoongArch64/Start.S`、`Sec/PreMem/LoongsonPreMem.c`、
  `PlatformPei/Platform.c`、`PlatformPei/MemDetect.c`、
  `LoongsonDisplayDxe/LoongsonDisplayDxe.c`、`Library/PlatformBootManagerLib/PlatformBm.c`
- `tools/decode_bootlog.py`、`tools/read_bootlog.sh`
- 布局：`Loongson2K1000Pkg.fdf.inc` 的 `FVMAIN_SIZE = 0x360000`
