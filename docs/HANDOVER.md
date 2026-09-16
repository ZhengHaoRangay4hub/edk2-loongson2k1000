# 交接文档 — LS2K1000LA 教育派 EDK II 移植

> 交接时间：2026-09-16 深夜。**读这份文件就能接着干。**
> 目标背景见 [QEMU-PORT.md](QEMU-PORT.md)（进行中的 QEMU 建模任务）、
> [STATUS.md](STATUS.md)（问题索引 P1–P8）、[BRINGUP.md](BRINGUP.md)（上机时间线）。

---

## 0. 一句话现状

**2026-09-17：QEMU 闭环达成 ✅**（SEC→PEI→DXE→BDS→`Shell>`，龙 logo 1024×768 截图非黑，
SII9022A 找到；SIGSEGV 根因=IOCSR 地址空间未建，已修复证实；配方
`build -D QEMU_FIT=TRUE -D PREMEM_STACK_TOP=0x90040000`，详见 QEMU-PORT.md 3.4）。
真机 v7 可启动；v8 真机镜像已产出（`~/Downloads/ls2k-new-v8/UEFI_4MB_v8.bin`，
MD5 `eeb876f5ddb4eec415178b1003b93261`，含 P5 修复，待烧写验证 HDMI）。
注意：工作区把 SEC 的 CRMD 从 0xb8 修订为 **0xa8**（DA=1,PG=0）——QEMU 实测 0xb8 的
DA+PG 组合会导致取指异常；0xa8 在真机上属未验证状态，若 v8 上机异常可回退 0xb8 对照。

---

## 1. 环境怎么进去

```bash
# 宿主 Docker CLI 不在 PATH 里，先加
export PATH=/Applications/Docker.app/Contents/Resources/bin:$PATH

# 容器：ls2kq4（跑新 QEMU）/ ls2kq3 / ls2kq
docker exec -it ls2kq4 bash
```

容器是 **x86_64 Debian 跑在 Apple Silicon 上**（`binfmt_misc` + `/usr/bin/qemu-x86_64`
user-mode 翻译）。这带来两个后果，**务必记住**：

1. 子进程**不能** `gdb` attach / `strace`（`ptrace: Function not implemented`）；
2. 但宿主进程崩了会由外层 qemu-user **写出 core 文件**（见第 5 节），并且容器里
   **有 `/usr/bin/gdb`（13.1）**，可以离线分析 core。上一轮误判成「无法取证」，别再走弯路。

宿主 ↔ 容器路径：

| 宿主 | 容器 | 内容 |
|---|---|---|
| `~/Downloads/ls2k-qemu` | `/qemu` | QEMU 源码/构建/固件/脚本/输出 |
| `~/Documents/sovints/ls2k1000la-edk2/repo` | `/repo` | EDK II 固件源码 |
| `~/Documents/sovints/ls2k1000la-edk2/refs` | `/refs` | 参考资料 |

代理与国内源**已配好，不用再设**：

```
apt : http://host.docker.internal:10808
env : http_proxy/https_proxy = http://host.docker.internal:10809
```

---

## 2. 关键路径速查

| 用途 | 路径 |
|---|---|
| 新 QEMU（本轮对象） | `/qemu/qemu-inst/bin/qemu-system-loongarch64`（8.2） |
| 出厂 QEMU（回退基线） | `/qemu/qemu/bin/qemu-system-loongarch64`（3.1，**只读，别动**） |
| QEMU 源码 | `/qemu/qemu-src`（`foxsen/qemu-up` / `ls2k1000` 分支，HEAD `56ee772cd`） |
| QEMU 构建目录 | `/qemu/qemu-build`（out-of-tree，`ninja`） |
| 本轮机器代码 | `hw/loongarch/2k1000.c`（+ 新文件 `ls2k_apb.c`、`ls2k_pci_stub.c`） |
| 固件镜像 | `/qemu/fw/uefi_qfit15.fd`（3,604,480 B = `0x370000`） |
| 固件源码 | `/repo/Platform/Loongson/Loongson2K1000Pkg/` |
| 闭环测试脚本 | `/qemu/qdisp8.sh`（标准）、`/qemu/qmon.py`、`/qemu/ppm2png.py` |
| 测试输出 | `/qemu/out/`（`s_*.log` 串口 / `d_*.log` guest 错误 / `shot_*.ppm`） |
| 出厂 PMON 备份（**恢复用，绝不可丢**） | 宿主 `~/Downloads/CH341A/W25Q32_dump_20260915_115813.bin`，MD5 `d1d3da6bcea4067bb5b67f54e1f3415d` |

---

## 3. 常用命令（可直接复制）

### 3.1 编译 QEMU 并安装

```bash
docker exec ls2kq4 bash -lc 'cd /qemu/qemu-build && ninja -j8 && ninja install'
```

### 3.2 标准闭环测试（`/qemu/qdisp8.sh` 做的事）

```bash
docker exec ls2kq4 bash -lc '/qemu/qdisp8.sh q82 600'
```

脚本内部：拷 `uefi_qfit15.fd` 到 `/tmp/q82.bin` 并 `truncate -s 16M` → 起 QEMU
（`-M ls2k,graphics=on -m 2048 -display none -drive if=pflash,... -serial file:... -d unimp,guest_errors`）
→ 轮询等 `Shell>` → 抓 `info pci` / `xp /8wx 0x60001240` → `screendump` → 退出。

### 3.3 手工最小复现（本轮用得最多的形态）

```bash
docker exec ls2kq4 bash -lc '
Q=/qemu/qemu-inst/bin/qemu-system-loongarch64
cp /qemu/fw/uefi_qfit15.fd /tmp/t.bin && truncate -s 16M /tmp/t.bin
timeout 90 $Q -M ls2k,graphics=on -m 2048 -display none \
  -serial file:/qemu/out/s_t.log \
  -drive if=pflash,format=raw,file=/tmp/t.bin \
  -d guest_errors -D /qemu/out/d_t.log
echo "rc=$?"; stat -c%s /qemu/out/s_t.log'
```

### 3.4 看结果 / 清理

```bash
tail -c 1200 /qemu/out/s_t.log                  # 串口尾部
grep -a -m3 'do_raise_exception' /qemu/out/d_t.log   # 首个异常点
ls -la /qemu/out/*.core                          # 有没有 core
```

---

## 4. 已知的坑（踩过的，别再踩）

| 坑 | 说明 / 正确做法 |
|---|---|
| `pkill -f qemu-system-loongarch64` **会把自己也杀掉** | 容器里曾因此 exit 143。用 **`pkill qemu-system`**（按 comm 名匹配）。 |
| 容器里有 7 个残留僵尸 qemu | 每次开测前先 `pkill qemu-system`，否则内存吃紧、日志串场。 |
| `-d int` / `-d cpu` 日志**爆炸** | guest 跑飞后 PC=0 死循环刷屏，曾出现 **223 MB**（`-d int`）和 **1 GB**（`-d cpu`）。用 `-d int,guest_errors` + `grep -m3` 取首行后**立刻删文件**。 |
| 8.2 对未映射访问**抛地址错**，3.1 静默返回全 1 | 这决定了故障现象：8.2 上会 `EXCCODE_ADEM` → `EENTRY=0` → PC 跳 0 → `unknown opcode ... 0x0` 死循环。**别把「PC 跳 0」当成固件的 bug。** |
| 未映射访问的日志**成对**出现 | `Invalid write at addr <绝对物理地址>, size 4` 与 `Invalid write at addr <区域内偏移>, size 8, region '(null)'`。用**绝对地址**那条。 |
| 单核跑（`-smp 1`）会因 `mycpu_dev[1] == NULL` 崩 | 2K1000LA 是双核，机器已设 `mc->default_cpus = 2`。别再用单核的结论。 |
| core 与二进制**版本不一致** | core 是 14:38 的，`qemu-inst` 里的二进制是 14:39 重装的 → 符号可能对不上。**复现时要保留同一份二进制。** |
| NOR 只读窗口只有前 1 MB | `0x1c000000-0x1c0fffff`，窗口外读回 0、**写入丢弃**。所以 `QEMU_FIT` 构建必须用（压缩后 < 1 MB，当前 811,040 B）。 |
| 变量存储不能放 flash | QEMU 丢弃 flash 写入 → 用 `-D QEMU_FIT=TRUE`，变量区搬到低 DDR 空洞 `0x0F000000`。 |

---

## 5. 当前唯一阻塞 + 已到手的取证材料

**阻塞**：默认（2 核）+ 真固件时，**串口 0 字节**、宿主 SIGSEGV；`-smp 1` 时跑到
`WakeUpAP: func 0x1C0349F0, ExchangeInfo 0x820E8` 后崩。stderr 出现**两次**
`qemu: uncaught target signal 11 (Segmentation fault) - core dumped`
（该字符串来自外层 qemu-user，不在我们的 QEMU 里 → 两个 vCPU 线程都崩了）。

**已到手**：

```
/qemu/out/qemu_qemu-system-loongarch64_20260916-143808_27331.core   3.6 GB
/usr/bin/gdb  (GNU gdb 13.1)      # 读 core 不需要 ptrace，可用
/qemu/out/gdbcore.txt             # 已经跑过一次 "info threads" + "thread apply all bt"
```

**下一步的第一件事**：用**同一份二进制**复现并保留 core，然后

```bash
gdb -batch -nx \
    -ex 'info threads' \
    -ex 'thread apply all bt' \
    -ex 'p $_siginfo' \
    /qemu/qemu-inst/bin/qemu-system-loongarch64 <core>
```

再把 `0x555555...` 形式的帧地址减掉 **PIE 基址 `0x555555554000`**，用
`addr2line -f -C -e <bin> <offset>` 落到函数。

**首选假设（判定性实验最省事）**：`env->address_space_iocsr` 为 NULL。
`target/loongarch/tcg/iocsr_helper.c` 的 `helper_iocsrrd_*` / `iocsrwr_*` 直接
`address_space_ld*/st*(env->address_space_iocsr, ...)`，而这个指针**只有**
`hw/loongarch/ls2k.c:575` / `virt.c:576` 那种 LAMS 风格机器才会赋值；
`hw/loongarch/2k1000.c` **没有** `system_iocsr` / `as_iocsr` / `iocsr_mem`。
→ 在 `iocsr_helper.c` 里临时加一句 `if (!env->address_space_iocsr) return 0;`
（写侧直接 return），若崩溃消失即确诊。

---

## 6. 待办清单（按顺序）

| # | 任务 | 判据 |
|---|---|---|
| 1 | 删掉 `2k1000.c` 里 **6 处 `LS2KMARK`** fprintf（702/822/825/852/880/1244 行），重新 `ninja -j8 && ninja install` | `grep LS2KMARK` 无结果，且重编通过 |
| 2 | 定位并修掉双核 SIGSEGV（第 5 节） | 2 核下串口不再 0 字节，无 `uncaught target signal 11` |
| 3 | 推进到 `Shell>` | 串口出现 `UEFI Interactive Shell v2.2` / `Shell>` |
| 4 | 内存对照 | `QMEM=2048` 与 `QMEM=1024` 均到 `Shell>` |
| 5 | 与出厂 3.1 QEMU 对照 `-smp 2` | 判断是 8.2 移植缺陷还是固件 AP 路径问题 |
| 6 | **HDMI 闭环**（本轮的真正目标） | SII9022A 在 I2C1 `0x39` 有 trace（`0xc7`/`0x1e`/`0x1a`/`0x1b-0x1d`）；DC 寄存器 `0x1fe01240` 系列落位；`screendump` 非黑（`ppm2png.py` 统计）；串口无 `SII9022A not found on I2C1` |
| 7 | 回写文档 | 订正 `STATUS.md`/`BRINGUP.md` 的「QEMU 不建模 DC/SII9022A/I2C」旧结论（BRINGUP.md 245-247 行），补记 8.2 移植与外设建模 |

---

## 7. 不要做的事

- **不要**碰出厂 PMON 备份 `W25Q32_dump_20260915_115813.bin`（唯一恢复手段）。
- **不要**动 `/qemu/qemu/bin/` 下的 3.1 出厂 QEMU（它是回退基线，改不了也不该改）。
- **不要**用 `pkill -f qemu-system-loongarch64`（自杀）。
- **不要**在跑飞后继续挂着 `-d int`/`-d cpu` 让它写日志（会吃满磁盘）。
- **不要**用 `-smp 1` 的旧结论去看新问题（那是 `mycpu_dev[1] == NULL`，已修）。
- **不要**把 8.2 上的「PC 跳 0 / unknown opcode 0x0」当成固件缺陷（那是未映射访问的必然结果）。

---

## 8. 相关文档

| 文件 | 内容 |
|---|---|
| [QEMU-PORT.md](QEMU-PORT.md) | 进行中：QEMU 3.1→8.2 移植、逐 fault 外设建模清单、5 步排查法 |
| [STATUS.md](STATUS.md) | 问题索引 P1–P8（真机 + QEMU 闭环发现的全部缺陷） |
| [BRINGUP.md](BRINGUP.md) | v1–v8 上机时间线、镜像 MD5、烧写流程 |
| [FLASHING.md](FLASHING.md) | 烧写说明 |
| 宿主 `LS2K1000LA移植-问题与分析总录.md` | 顶层汇总（与 STATUS.md 同源） |