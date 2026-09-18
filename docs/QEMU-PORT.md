# QEMU `ls2k` 机器：3.1 → 8.2 移植与外设建模（进行中）

> 本文件记录**「把 QEMU 缺的外设建模出来，再在模拟器里闭环」**这条线的进行中工作。
> 真机侧的问题索引见 [STATUS.md](STATUS.md)，镜像/上机时间线见 [BRINGUP.md](BRINGUP.md)。
> **2026-09-17：闭环达成 ✅** 同一份 UEFI.fd 在新 QEMU 上从 SEC 一路跑到 `Shell>`，
> SII9022A 在 I2C1@0x39 被找到，screendump 输出 1024×768 龙 logo 开机画面（非黑 100%）。
> 第 5 节的 SIGSEGV 根因（IOCSR 地址空间未建 → `env->address_space_iocsr == NULL`
> 解引用）已被修复证实——修复后双核不再崩、`-smp 1` 能过 `WakeUpAP`。
> DC 寄存器块已按固件实际寻址方式别名到两个平面窗口（见第 3.4 节）。

---

## 1. 为什么要做这件事

原厂 QEMU 是个 3.1 时代的**静态二进制**（`/qemu/qemu/bin/qemu-system-loongarch64`），
`ls2k` 机器写死在里面：改不动、加不了外设。而 HDMI 通路（DC + SII9022A + I2C1）
在它里面**根本不存在**，所以 P5（HDMI 黑屏）这条路在模拟器里没法验证——
每判断一次「固件到底行不行」就得烧一次真机。

目标：把固件实际访问、而 QEMU 没建模的寄存器/外设逐个补上，让**同一份 `UEFI.fd`**
在模拟器里从 SEC 一路跑到 `Shell>`，并且把 HDMI 通路也跑起来。

（原始要求原文：「通过 PMON 和相关资料找到的 HDMI 模拟和其他外设模拟。
你拿 Qemu 把没有的都建模出来，然后在 qemu 里进行闭环测试」。）

---

## 2. 环境与路径

| 项 | 值 |
|---|---|
| 出厂 QEMU（回退基线） | `/qemu/qemu/bin/qemu-system-loongarch64`（3.1-era，静态） |
| 新 QEMU（本轮工作对象） | `/qemu/qemu-inst/bin/qemu-system-loongarch64`（8.2） |
| QEMU 源码 | `/qemu/qemu-src`，`foxsen/qemu-up` 的 `ls2k1000` 分支，HEAD `56ee772cd tmp` |
| 构建目录 | `/qemu/qemu-build`（out-of-tree，`ninja`） |
| 固件镜像（QEMU_FIT） | `/qemu/fw/uefi_qfit15.fd`，3,604,480 B = `0x370000` |
| 测试脚本 | `/qemu/qdisp8.sh`（标准闭环脚本）、`/qemu/qmon.py`、`/qemu/ppm2png.py` |
| 输出目录 | `/qemu/out/`（`s_*.log` 串口、`d_*.log` guest 错误、`shot_*.ppm` 截图） |

**容器**：`ls2kq4`。注意它是个 **x86_64 Debian 镜像跑在 Apple Silicon 上**，
经 `binfmt_misc` 用 `/usr/bin/qemu-x86_64`（user-mode）翻译执行 —— 这条事实决定了
第 5 节的取证手段（无 ptrace，但有 core 文件）。

宿主 ↔ 容器挂载（`docker inspect ls2kq4`）：

| 宿主 | 容器 |
|---|---|
| `~/Downloads/ls2k-qemu` | `/qemu` |
| `~/Documents/sovints/ls2k1000la-edk2/repo` | `/repo` |
| `~/Documents/sovints/ls2k1000la-edk2/refs` | `/refs` |
| `~/Downloads/ls2k-qemu/fake_cpuinfo` | `/proc/cpuinfo`（绕过构建脚本的 CPU 检查） |

代理（国内源 + 本机代理，已配好）：

```
apt : http://host.docker.internal:10808
env : http_proxy/https_proxy = http://host.docker.internal:10809
      no_proxy 含 mirrors.tuna.tsinghua.edu.cn
```

宿主 Docker CLI 不在 PATH：

```bash
export PATH=/Applications/Docker.app/Contents/Resources/bin:$PATH
```

---

## 3. 已落地的改动

### 3.1 前序（把 2k1000 机器从 3.1 API 迁到 8.2 + 补整机设备）

`git status` 可见，共 **21 个已跟踪文件被修改 + 3 个新文件**：

| 文件 | 作用 |
|---|---|
| `hw/loongarch/2k1000.c` | 机器主体（改动最大，485 行） |
| `hw/loongarch/ls2k_apb.c` **(新)** | 无上游模型的 APB 外设（含 SPI 控制器/flash 窗口） |
| `hw/loongarch/ls2k_pci_stub.c` **(新)** | `pciram`、`pci-synopgmac` 两个片上 PCI 功能 |
| `include/hw/loongarch/2k1000.h` **(新)** | 机器头文件 |
| `hw/pci-host/ls2k.c`、`include/hw/pci-host/ls2k.h` | PCI 主机桥（8.2 API） |
| `hw/display/sii9022.c`、`hw/display/ls_fb.c`、`ls_fb_template.h` | **SII9022A HDMI 发送器** + LS 帧缓冲 |
| `hw/i2c/ls_i2c.c`、`hw/i2c/meson.build` | LS I2C 控制器 |
| `hw/dma/ls_dma.c`、`hw/dma/Kconfig` | LS DMA |
| `hw/block/ls_nand.c` | LS NAND |
| `hw/sd/ls_mmci.c`、`ls_mmci.h` | LS SD/MMC |
| `hw/ide/ls2k-ahci.c`、`include/hw/ide/ahci.h` | LS AHCI |
| `hw/ssi/ssi.c`、`include/hw/ssi/ssi.h` | SSI 补丁（spi-flash `addr` 属性等） |
| `target/loongarch/cpu.c` | LoongArch CPU 侧适配 |
| `hw/loongarch/Kconfig`、`meson.build`、`hw/pci-host/Kconfig` | 构建接线 |

`hw/loongarch/2k1000.c` 里**已在位**的、与 HDMI 直接相关的建模：

```c
/* I2C1 @ APBBASE+0x1800，教育派在此挂 SII9022A @ 0x39 */
i2c_slave_create_simple(bus, "sii9022", 0x39);
```

（`hw/loongarch/2k1000.c` 中 APBBASE=`0x1fe20000`、CFGBASE=`0x1fe00000`、
GPUBASE=`0xd0000000`。）

### 3.2 本轮：逐 fault 补寄存器/外设

方法：`-d guest_errors` 拿到**第一个未映射访问** → `-d int,guest_errors` 拿异常点
`ERA`/`BADI` → 反汇编定位指令 → 回固件源码查归属 → 建模 → 重跑。

| # | fault 地址 | 触发者（固件侧） | 建模做法 |
|---|---|---|---|
| A | `0x1fe00420`、`0x428-0x43f` | `UartPinMuxInit()` 读改写引脚复用 | `pinmux_regs[8]` 静态组，reset `0x1`；`SIMPLE_OPS(CFGBASE+0x420, 0x20)` |
| B | 6 路 16550 | 控制台镜像到 UART0+UART3，其余 LCR 亦被写 | `serial_mm_init()` **无条件**建 6 个（`serial_hd(N)` 可为 NULL） |
| C | `0x1fe00580` | PCIe 信号测试图案 / PHY 窗口 | 建 `0x580-0x5bf` RAM 区；`0x594` 固定返回 `0x4`（`PciePhyWrite()` 在此死等 bit2，否则**卡在显示之前**） |
| D | `0x11000054` | `PciePortConf()` 清 link width/speed | `0x10000000`、`0x11000000` 各建 4 KiB RAM，优先级 2 覆盖 `iomem_submem` |
| E | `0x1fe004b8` | PIX0 PLL 的 L2 分频（`ClkSetting.S` 的 `st.d`） | `SIMPLE_OPS` 宽度 `8 → 0x10`（依据 DTS：`clock-controller` 每 PLL 块 0x10） |
| F | `0x1fe00180` | SEC DDR 阶段的 L2 X-bar 配置 | 建 `0x1fe00000+0x200`（L2 xbar）、`0x1fe20180+0x80`（chipcfg）、`0x3ff00000+0x3000`（scache/L1XBAR） |
| G | —（非 fault） | AP 唤醒会写第二核的 IPI mailbox | `mc->default_cpus = 2`（2K1000LA 是双核；`ls2k_set_cpuirq()` 用 `irq/4` 当核号，单核时 `mycpu_dev[1]` 为 NULL） |

> **8.2 与 3.1 的关键行为差异**（这是这一整轮 fault 的来源）：
> 8.2 对**未映射地址**的访问会触发地址错异常（`reason: rejected` → `EXCCODE_ADEM`，
> 日志 `do_raise_exception: 72 (Address error for Memory access)`），而
> `EENTRY = 0` → PC 跳 0 → `Error: unknown opcode. 0000000000000000: 0x0` 死循环。
> 3.1 的分支对未映射访问**静默返回全 1**，所以什么都不会发生。
> 每次 fault 的日志**成对出现**：
> `Invalid write at addr <绝对物理地址>, size 4` +
> `Invalid write at addr <区域内偏移>, size 8, region '(null)'`
> —— 后者是 `memory_region_dispatch_write` 的 region 相对偏移，可反推 region 基址。

### 3.4 显示闭环与冒烟测试配方（2026-09-17）

- **IOCSR**：`2k1000.c` 现在创建 IOCSR 地址空间并挂上游 `loongarch_ipi`，
  给每个 CPU 赋 `env->address_space_iocsr`（SIGSEGV 根因修复）。
- **DC 平面窗口**：`LoongsonDisplayDxe` 在 PCI BAR 分配之前就通过平面地址驱动 DC
  （0x60000000 根桥 MMIO 基址 / 0x1f010000 内部总线译码）。把 `pci_ls_fb` 的寄存器块
  以 priority 1 别名到这两个窗口后，固件的写操作直接落到模型上，
  QEMU graphic console 也因此显示固件配置的 1024×768 模式（screendump 非黑）。
- **冒烟测试构建配方（缺一不可）**：
  ```
  /root/ls2k.sh build -D QEMU_FIT=TRUE -D PREMEM_STACK_TOP=0x90040000
  ```
  只传 QEMU_FIT 不传 PREMEM_STACK_TOP 时，SEC 栈仍落在 QEMU 只读 ROM 窗口的
  板级默认位置，固件会卡死在 DxeIpl（表现为串口停在 Install PPI 后不再推进）。
- 临时 LS2KMARK 打印已全部删除。

### 3.5 boot flash 窗口与本地总线别名（2026-09-18）

机器原先只映射 SPI flash 的**前 1 MB**（`0x1c000000-0x1c0fffff`），1 MB 以上被
`lioflash`/`lioflash1`（CFI 本地总线 flash，本板未装配）的别名覆盖，表现为
"窗口外读回 0、写入丢弃"。日志区放在 3.375 MB 处，所以：

- `spi-flash` 的 `size` 由 `0x100000` 改为 `0x400000`（与板上 W25Q32 一致）；
- `lioflash` 别名的安装与重装（GPIO 绑带寄存器写入路径）**取消**——这块板从 SPI 启动、
  没有本地总线 flash，窗口应当完整显示 SPI 芯片。

顺带解决了"1 MB 窗口导致 QEMU_FIT 必须压缩固件"的根因：真机镜像（1.40 MB）现在
在 QEMU 里也能被读取（板级镜像仍卡在 DxeIpl 解压 10.4 MB 卷，是模拟器速度问题）。

### 3.3 临时调试标记（**收尾时必须删除**）

`hw/loongarch/2k1000.c` 中现有 6 处 `fprintf(stderr, "LS2KMARK ...")`：

```
702:  LS2KMARK cpu %d
822:  LS2KMARK ram+flash done
825:  LS2KMARK pcibus done
852:  LS2KMARK intc0 done
880:  LS2KMARK uarts done
1244: LS2KMARK init done
```

---

## 4. 里程碑：新 QEMU 上固件已经跑到 PEI

imgs: `/qemu/fw/uefi_qfit15.fd`，2 GB 内存，`-M ls2k`：

```
Loongson2K1000LA EDK2 SEC booting... [v8b]
SoC early init done
Soft CLK SEL adjust begin
50010c85 / MEM :10010c87 / DC :10010c87 / PIX0 :00010001 / PIX1 :00010001
Start Init Memory, wait a while......
NODE 0 MEMORY CONFIG BEGIN
The MC param is: <0x320 dump>
run to wait dram init ok!3
MC0 Config DONE
...
ConfigureMemoryManagementUnit 156 VirtualBase 10000000 VirtualEnd 20000000 Attributes 1 .
ConfigureMemoryManagementUnit 156 VirtualBase FE00000000 VirtualEnd FE20000000 Attributes 1 .
ConfigureMemoryManagementUnit 206 Enable MMU Start PageBassAddress EFFC000.
WakeUpAP: func 0x1C0349F0, ExchangeInfo 0x820E8
```

对照起点：上一轮该镜像在新 QEMU 上只有 **46 字节**串口输出。
现在 **25351 字节**，`guest_errors` 里**已无未映射访问**。

参考日志：`/qemu/out/s_n9.log`（25351 B）、`/qemu/out/d_n9.log`。

---

## 5. 当前唯一阻塞：双核 host SIGSEGV

### 现象

| 配置 | 结果 |
|---|---|
| `-smp 1` + 真固件 | 串口 25351 B，停在 `WakeUpAP: func 0x1C0349F0, ExchangeInfo 0x820E8` 后 **host SIGSEGV** |
| 默认（2 核）+ 真固件 | **串口 0 字节**即崩；`-serial stdio` 同样 0 字节 |
| 空 flash + 2 核 | 稳定跑 15 s，无崩 |

stderr 出现**两次**：

```
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
```

这串话**不在**我们的 `qemu-system-loongarch64` 里（`strings | grep -c` = 0），
它来自外层 `qemu-x86_64`（user-mode 翻译层）—— 说明**宿主进程**真的收到了 SIGSEGV，
且**两个 vCPU 线程都崩了**。

### 已排除

- **不是跨 vCPU 竞争**：`-accel tcg,thread=single` 同样崩。
- **不是机器模型本身**：空 flash + 2 核可稳定运行。
- **不是 `loongarch_cpu_set_irq()` 越界**：`N_IRQS = 13`、`IRQ_IPI = 12`，
  函数内有 `if (irq < 0 || irq >= N_IRQS) return;`，且 `qdev_get_gpio_in(cpu, 2..5)` 合法。
- （上一轮的结论）单核崩溃是 `mycpu_dev[1] == NULL`，已由 `default_cpus = 2` 修掉，
  但随即暴露出这第二个、不同的崩溃。

### 当前的取证结论（本轮新发现，**重要**）

**有 core 文件，而且容器里有 gdb**（这两条之前被误判为「不可用」）：

```
/qemu/out/qemu_qemu-system-loongarch64_20260916-143808_27331.core   3.6 GB
/usr/bin/gdb  (GNU gdb 13.1)
```

`gdb -batch -ex "info threads" -ex "thread apply all bt" <bin> <core>` 可跑通
（结果 `/qemu/out/gdbcore.txt`），5 个 LWP：

| LWP | 帧 0 | 说明 |
|---|---|---|
| 27331 | `0x0000ffff99a3e366` | 在 qemu-user 的 JIT 代码缓存里 |
| 27334 | `0x0000ffff99a43829` | 同上 |
| 27335 | `0x0000555555dac6aa` | 在 qemu-system 自身 text 里 |
| 27336 | `0x0000555555b83da8` | 同上 |
| 27337 | `0x0000ffff999c7f16` | JIT |

把 `0x555555...` 两个地址按 PIE 基址 `0x555555554000` 归一后查符号得到：

```
0x8566aa -> tcg_reg_alloc_op      tcg/tcg.c:4899
0x62fda8 -> address_space_map     system/physmem.c:3180
```

> ⚠️ 这两条**还不能下定论**：core 生成于 14:38:08，而 `qemu-inst` 里的二进制是
> 14:39（随后重装过），gdb 也报了 `warning: core file may not match specified
> executable file` —— 符号与现场可能对不上。下一步应先**用同一份二进制复现并
> 保留 core**，再用 gdb 取 `$_siginfo` / 故障线程的 `rip` + 寄存器，
> 最后用 `addr2line`（基址 `0x555555554000`）落到函数。

### 高度怀疑的方向

AP（CPU1）执行 `Sec/LoongArch64/Start.S` 的 `SlaveMain` 路径：
`SetExceptionBaseAddress` → `ClearMailBox`（`iocsrwr.d` MBUF3..0）→
`EnableIPI`（`csrxchg` ECFG BIT12 + `iocsrwr.w` IPI_EN）→
`WaitForWake: bl CpuSleep; b WaitForWake`，异常处理在 `ApException`
（`iocsrrd.w IPI_STATUS` / `iocsrwr.w IPI_CLEAR` / `iocsrrd.d` MBUF0/MBUF3）。

关键判据：`target/loongarch/tcg/iocsr_helper.c` 的 helper 直接
`address_space_ld*/st*(env->address_space_iocsr, ...)`，而
`env->address_space_iocsr` **只有在 `hw/loongarch/ls2k.c:575` / `virt.c:576` 那种
LAMS 风格机器里才被赋值**。本 `2k1000.c` 机器**没有** `system_iocsr` /
`as_iocsr`，也没有 `iocsr_mem` —— 若该指针为 NULL，第一次 IOCSR 访问就是
**NULL 解引用 → SIGSEGV**。这条能同时解释两个崩溃点：

- `-smp 1`：崩在 `WakeUpAP`（BSP 第一次写 IOCSR 邮箱）；
- 2 核：**更早**崩（AP 一进来 `ClearMailBox` 就写 IOCSR）。

**下一步验证**：在 `hw/loongarch/2k1000.c` 的 init 里建 IOCSR 地址空间并按
`ls2k.c` 的写法给每个 CPU 赋 `env->address_space_iocsr`（或把
`helper_iocsr*` 改成对未知地址安全忽略），然后重跑。

---

## 6. 方法论（下一轮直接复用）

1. `-d guest_errors` 拿**第一个**未映射访问（日志成对，用绝对地址那条）。
2. `-d int,guest_errors` 拿异常点 `ERA` / `BADI`。
   ⚠️ 跑飞后 PC=0 死循环会**爆日志**（曾一次跑出 223 MB、`-d cpu` 更早前有过 1 GB），
   必须 `grep -m3 do_raise_exception` 取首行后立刻清理。
3. 用 `BADI` 反汇编定位指令。例：`0x29c0218e` → bits[31:22]=`0b0010100111` → `st.d`，
   `rd`=bits[4:0]=14=`$t2`，`rj`=bits[9:5]=12=`$t0`，`si12`=bits[21:10]=8
   → `st.d $t2, $t0, 8`。
4. 回固件源码反查该地址属于哪个函数/宏（`Sec/PreMem/` 下的 `PmonDefs.h`、
   `ddr_dir/ddr_config_define.h`、`ClkSetting.S` 等）。
5. 建模 → `cd /qemu/qemu-build && ninja -j8 && ninja install` → 重跑。

---

## 7. 下一步（按优先级）

1. **删掉 6 处 `LS2KMARK`**（第 3.3 节），重新 `ninja -j8 && ninja install`。
2. **定死 SIGSEGV 根因**：
   - 复现时保留 core（同二进制），用 gdb 取故障线程 `rip`/`$sp` + `$_siginfo`；
   - 或直接在 `iocsr_helper.c` 里临时加 `if (!env->address_space_iocsr) return 0;`
     做**判定性实验** —— 若崩溃消失即可确认是 NULL 解引用。
3. 修掉后继续推进到 `Shell>`，再 `QMEM=1024/2048` 各跑一遍。
4. 对照实验：出厂 3.1 QEMU `-smp 2` 跑同一镜像，判断是 8.2 移植缺陷还是固件 AP 路径问题。
5. **HDMI 闭环**：
   - trace SII9022A 在 I2C1 @ `0x39` 的关键寄存器（`0xc7` / `0x1e` / `0x1a` / `0x1b-0x1d`）；
   - 确认 DC 寄存器落位（`0x1fe01240` 系列 / monitor `xp /8wx 0x60001240`）；
   - `screendump` 截图 → `ppm2png.py` 统计非黑像素；
   - 串口不应出现 `SII9022A not found on I2C1`。
6. 回写文档：订正 [STATUS.md](STATUS.md) / [BRINGUP.md](BRINGUP.md) 里
   「QEMU 不建模 DC / SII9022A / I2C，HDMI 通路无法验证」的旧结论
   （见 BRINGUP.md 第 245-247 行），补记本轮 8.2 移植与外设建模。