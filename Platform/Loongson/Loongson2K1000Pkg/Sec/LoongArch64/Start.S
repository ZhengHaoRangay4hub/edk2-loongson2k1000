#------------------------------------------------------------------------------
#
# SEC entry for Loongson 2K1000LA (education board / LS2K1000LA).
#
# Forked from OvmfPkg/LoongArchVirt/Sec/LoongArch64/Start.S (BSD-2-Patent,
# Copyright (c) 2024 Loongson Technology Corporation Limited) and adapted for
# real hardware: DRAM is not initialized at reset, so the SEC stage first
# programs the SoC, PLLs and the DDR3 memory controller using the assembly
# ported from Loongson PMON (pmon-ls2k1000la).
#
# SPDX-License-Identifier: BSD-2-Clause-Patent
#
#  @par Glossary:
#    - CSR - CPU Status Register
#------------------------------------------------------------------------------
#ifndef __ASSEMBLY__
#define __ASSEMBLY__
#endif

#include <Library/BaseMemoryLib.h>
#include <Register/LoongArch64/Csr.h>
#include <Protocol/DebugSupport.h>
#include <Library/LoongsonBootLog.h>

#define BOOTCORE_ID  0

/*
 * Pre-DRAM stack: the top of the 256 KB of scache PMON locks for its own early
 * stack.  The value is PMON's `stack = start + LOCK_CACHE_SIZE`
 * (refs/pmon/Targets/ls2k/ls2k/start.S:94) with
 * LOCK_CACHE_BASE = PHYS_TO_CACHED(0x90000000) and LOCK_CACHE_SIZE = 0x40000
 * (refs/pmon/Targets/ls2k/include/bonito.h:120-121): physical 0x90040000,
 * carried through the 0x9000 window, i.e. the last bytes of the region the two
 * stores below lock.  The alternative - the address v7 (commit c76951b), the
 * only image with a field record of booting on this board, used - is
 * 0x1c03fff8, inside the 1 MB boot window, which the manual (10.2, table 10-1,
 * printed p.103) describes as a read-only mapping of the SPI flash.
 *
 * Neither address is proven as a stack on this port.  PMON only stacks at
 * 0x90040000 after DRAM exists, and only after reading the whole region once
 * to confirm it is accessible (start.S:507-514); this port locks the region
 * before DRAM and pushes into it in the next instruction, so "the locked cache
 * cannot be used yet" and "the board hangs" look exactly alike from outside.
 * That is what the probe in _ModuleEntryPoint (search for "Pre-DRAM stack
 * probe") separates before the first C call: 3 beeps if the address the stack
 * will use writes and reads back, 4 if it does not, then 5 or 6 for
 * 0x1c03fff8.  Keep this address until the probe answers.
 *
 * QEMU is the mirror image: its ls2k machine builds 0x1c000000-0x1c0fffff as
 * read-only RAM, so writes there are dropped and the first `bl`/`ret` flies
 * off.  The emulator smoke test therefore overrides this at build time
 * (`build -D QEMU_FIT=TRUE -D BOARD_MIN=TRUE -D PREMEM_STACK_TOP=0x90040000
 * -D BOOT_CRMD=0xa8`; see fdf.inc and the DSC), so one source tree produces
 * both the board image and an emulator image.  Neither value has ever run on
 * the other side.
 */
#ifndef PREMEM_STACK_TOP
#define PREMEM_STACK_TOP  0x9000000090040000
#endif

/*
 * CRMD value written at reset (the reasoning is at the csrwr below).  It comes
 * from the build - Loongson2K1000Pkg.fdf.inc defines it and the DSC passes it
 * through PP_FLAGS, exactly like PREMEM_STACK_TOP - so one source tree produces
 * both the board image and the emulator image.  The fallback here is on purpose
 * the board value: this image goes into a chip and a wrong choice there is
 * silent, while a wrong choice for the emulator fails loudly and immediately on
 * the development machine.
 */
#ifndef BOOT_CRMD
#define BOOT_CRMD  0xb8
#endif

/* Direct mapping windows, standard convention:
 *   DMW0 0x8000000000000000 : PLV0-3, MAT0 (strongly-ordered uncached)
 *   DMW1 0x9000000000000000 : PLV0-3, MAT1 (coherent cached)
 *
 * This is the mirror of PMON's assignment (PMON: 0x8000 uncached / 0x9000
 * cached - refs/pmon/sys/arch/loongarch/include/cpu.h:55-56 and
 * Targets/ls2k/ls2k/start.S:118-121); both are self-consistent as long as
 * PHYS_TO_* and the windows agree, which they do - MMIO must land in MAT0
 * whichever VSEG carries it.
 *
 * Deliberately untouched while the entry is bisected:
 *   - v7 (c76951b), the only image with a field record of booting on this
 *     board, carries these two immediates byte for byte, so they are not what
 *     made the current image silent.
 *   - QEMU cannot evaluate them: with CRMD.DA=1 it returns before the DMW
 *     table is consulted (target/loongarch/tcg/tlb_helper.c:195-203) and it
 *     models no cache attribute, so a QEMU pass says nothing about them.
 *   - Flipping them (0x8000 uncached / 0x9000 cached, as PMON and Linux do) is
 *     all or nothing: UNCACHED() in Sec/PreMem/LoongsonPreMem.c,
 *     PHYS_TO_UNCACHED() in Sec/PreMem/PmonDefs.h, Library/
 *     LoongsonBootLogLib/LoongsonBootLogLib.c and the PCIe window constants
 *     all hard-code the 0x9000 alias, so a half-done flip turns every MMIO
 *     access into a cached one.  Change every one of them in one commit.     */
#define DMW0_UNCACHED  (0x8000000000000000 | 0xf)
#define DMW1_CACHED    (0x9000000000000000 | 0x1f)

#define CSR_DMW0  0x180
#define CSR_DMW1  0x181
#define CSR_CRMD  0x0

ASM_GLOBAL ASM_PFX(_ModuleEntryPoint)
ASM_PFX(_ModuleEntryPoint):
	/*
	 * Very first instruction: a click, before the interrupt CSRs, before the
	 * DMWs, before the CRMD value - before anything this port added.
	 *
	 * Everything audible so far ran through code paths that differ from this
	 * one in exactly those first few instructions.  The field-proven stub
	 * (tools/stub_beep.S) never executed them: the boot ROM handed control
	 * straight to offset 0xF00, so it inherited the ROM's own direct-mapping
	 * windows and used 0x8000_0000_... for MMIO.  This port instead installed
	 * its own DMWs and addressed MMIO through 0x9000_0000_..., a window QEMU
	 * tolerates (it masks to 48 bits and never consults the DMWs) and the
	 * board has never been shown to route.
	 *
	 * So this block is the same experiment the stub ran, moved to where the
	 * firmware actually starts: open the APB window, then drive GPIO39, all
	 * through 0x8000_0000_....  Hearing it means the image runs, the window
	 * is right, and the fault is further in.  Hearing nothing at all means
	 * the failure is not in the firmware's logic but in how it is entered.
	 */
	li.d	$t5, 0x800000fe00001000		/* PCIe APB BAR */
	li.d	$t6, 0x800000001fe20000
	st.w	$t6, $t5, 0x10
	ld.w	$t6, $t5, 0x04
	ori	$t6, $t6, 0x2
	st.w	$t6, $t5, 0x04			/* APB window open */

	/*
	 * Release the external watchdog next, before anything here that takes
	 * time.  PMON's watchdog_close() is its first GPIO action and it follows
	 * the APB window writes immediately (refs/pmon/Targets/ls2k/ls2k/start.S:
	 * 125-131) - before its beeps, before the SPI access, before the clocks.
	 * GPIO3 low releases the feeder; clear bit 3 of 0x1fe00500 (direction)
	 * and of 0x1fe00510 (data), exactly as PMON does.  PreMemInit() runs the
	 * same sequence again later, which is idempotent.
	 */
	li.d	$t0, 0x800000001fe00500
	li.w	$t2, ~0x8
	ld.w	$t3, $t0, 0
	and	$t3, $t3, $t2
	st.w	$t3, $t0, 0
	ld.w	$t3, $t0, 0x10
	and	$t3, $t3, $t2
	st.w	$t3, $t0, 0x10

	li.w	$a0, 1				/* ONE beep: this is the "reset path is alive" mark */
	bl	LoongsonBeepRaw

	/*
	 * Earliest exception catcher: point EENTRY at code that beeps and stops.
	 *
	 * Until now the SEC stage had no exception vector at all - SetExceptionBaseAddress
	 * runs much later and aims at 0x10000, which is DRAM and does not exist yet.
	 * Any fault before that therefore jumped to 0 and the board simply went quiet,
	 * which is why "hung" and "flew off on an exception" have looked identical
	 * through every attempt so far.  PMON installs its vector at reset for the same
	 * reason (start.S:150-151), into the flash window rather than DRAM.
	 *
	 * On LoongArch every exception enters at EENTRY, so one long buzz here catches
	 * all of them - a different sound from the progress beeps on purpose.
	 *
	 * The target must be the 4KB-aligned PreMemExceptionVector table: the
	 * hardware forms the entry as "EENTRY page | offset" (see the comment at
	 * the second write below), so the old EarlyExceptionCatch target - never
	 * page-aligned - could never be reached by any exception and silently
	 * routed faults to unrelated code at the page base instead.
	 */
	la.pcrel $t0, PreMemExceptionVector
	csrwr	$t0, 0xc

	/* Disable global interrupt */
	bl	DisableInterrupts

	/* Disable all local interrupt */
	li.w	$a0, 0x1FFF
	bl	DisableLocalInterrupts

	/*
	 * PMON's reset-head CSRs, before its direct-mapping windows
	 * (refs/pmon/Targets/ls2k/ls2k/start.S:110-116 and :156-158):
	 *
	 *   CSR 0x200 bit16 - count with the performance counter, not CP0
	 *   CSR 0x80  bit9  - open auto flush SFB
	 *   CSR 0xc1  bit3  - PMON's comment says "enable llexc"; its meaning on
	 *                     this part is in no document in this tree, so this is
	 *                     the one write here that can be dropped on its own if
	 *                     the next image behaves worse
	 *
	 * Nothing in this firmware wrote any of the three (an instruction scan of
	 * the whole image finds no csrxchg with these numbers), and the 0x80 bit
	 * is the only cache-side initialisation PMON does at reset that this port
	 * had skipped - it is a store-buffer/cache control bit, which is exactly
	 * where the current failure hypothesis lives.
	 */
	li.w	$t0, (0x1 << 16)
	csrxchg	$t0, $t0, 0x200
	li.w	$t0, (0x1 << 9)
	csrxchg	$t0, $t0, 0x80
	li.w	$t0, (0x1 << 3)
	csrxchg	$zero, $t0, 0xc1

	/*
	 * Pre-DRAM exception vector.
	 *
	 * PMON installs a vector that speaks before it touches anything
	 * (start.S:147-158: it clears ECFG[18:16], points EENTRY and TLBRENTRY at
	 * 0x1c001000 and its handler prints "CPU Trigger exception!"), while this
	 * firmware installed nothing until DRAM existed and the EDK2 vector could
	 * be copied.  Before that point a fault and a hang were both silence,
	 * which is why every silent image so far has been undiagnosable.
	 *
	 * The hardware forms the entry as "EENTRY page | 2^(ECFG.VS+2) x ecode",
	 * so VS selects the spacing.  VS = 0 - the reset value, and the one PMON
	 * restores - makes it 4 bytes: one branch per slot, and the table in
	 * PreMemExceptionVector therefore covers every exception code (0..63) and
	 * every interrupt slot (64..79).  The address is PC-relative, so it
	 * carries whatever segment this code is running in and suits either CRMD
	 * candidate below.  TLBRENTRY gets the same page, as in PMON.
	 *
	 * The vector is replaced by the EDK2 one (copied to
	 * PcdLoongArchExceptionVectorBaseAddress) once DRAM is up.
	 */
	li.d	$t0, (0x7 << 16)
	csrxchg	$zero, $t0, 0x4			/* ECFG[18:16] = 0: 4-byte slots */
	la.pcrel $t0, PreMemExceptionVector
	csrwr	$t0, 0xc			/* EENTRY   */
	csrwr	$t0, 0x88			/* TLBRENTRY */

	/* Direct mapping windows + direct address mode with cached attribute */
	li.d	$t0, DMW0_UNCACHED
	csrwr	$t0, CSR_DMW0
	li.d	$t0, DMW1_CACHED
	csrwr	$t0, CSR_DMW1
	/*
	 * CRMD: DA=1 (direct address - this phase has no page tables and runs from
	 * the raw 0x1c000000 window, VSEG 0), DATF/DATM cached.  The value comes
	 * from the build; the two candidates differ in one bit, PG:
	 *
	 *   0xb8 (DA=1, PG=1) is the field-proven one.  Every image with a record
	 *        of starting on this board used it: v6 left a reset loop by going
	 *        0xb0 -> 0xb8 and v7 - the last image known to reach BDS - carries
	 *        this byte (commit c76951b, "li.w $t0, 0xb8" in its Start.S).  0xa8
	 *        has never run on the board.
	 *   0xa8 (DA=1, PG=0) is what the emulator needs.  QEMU short-circuits only
	 *        on `DA && !PG` (target/loongarch/tcg/tlb_helper.c:195-203, then
	 *        masks to 48 bits); with PG=1 it walks the DMW/TLB path instead, no
	 *        window covers VSEG 0, and the fetch returns 0x5555 filler from
	 *        0x1c002030 although the memory there holds the correct `bl`.  That
	 *        is a modelling difference, not a statement about the hardware.
	 *
	 * Build switch: Loongson2K1000Pkg.fdf.inc defines BOOT_CRMD and the DSC
	 * passes it through PP_FLAGS, exactly like PREMEM_STACK_TOP.  See the note
	 * there for which value the default is and why.
	 *
	 * Later phases install their own page tables as usual.
	 */
	/*
	 * CRMD in place - the v7 form, the only value with a field boot behind it.
	 *
	 * v24 tried PMON's two-step (jump to the cached alias, then write) but got
	 * the offset wrong: `bl 2f; 2: addi.d $t0,$ra,0` makes $ra point at the
	 * addi.d itself, so the jirl jumped straight back to it - an infinite loop,
	 * and the board went fully silent right after the entry beep.  PMON uses
	 * ra+0xc to land on its ori; but its whole dance exists because it writes
	 * 0xb0 (DA=0, PG=1), where the DMWs must already cover the PC.  With DA=1
	 * (0xb8) the fetch truncates to the same physical address anyway - which is
	 * exactly what the v7 boot proved - so the simple in-place write is both
	 * correct and the least machinery this early.
	 */
	ori	$t0, $zero, BOOT_CRMD
	csrwr	$t0, CSR_CRMD

	/* Read physical cpu number id */
	bl	GetApicId
	li.d	$t0, BOOTCORE_ID
	bne	$a0, $t0, SlaveMain

	/*
	 * BSP: park the stack in the boot window (see the note on
	 * PREMEM_STACK_TOP), then run the pre-memory SoC/PLL/DDR bring-up.
	 */
	or	$s0, $zero, $zero	/* memdebug rodata base delta */

	li.w	$a0, 2				/* two beeps: APB window open + GPIO alive */
	bl	LoongsonBeepRaw

	/*
	 * Pre-DRAM RAM: lock 256 KB of scache and stack at its top, like PMON.
	 *
	 * 0x1c040000 - the address used until now - sits inside the boot window,
	 * which the manual (§10.2, p.103) documents as a read-only mapping of the
	 * SPI flash, and PMON never places a stack there.  Its own layout (printed
	 * by the shipped firmware itself, baseline log line 848: "lock scache
	 * 90000000 - 90040000") is a locked scache at physical 0x90000000 with the
	 * stack at 0x9000000090040000.  The two register writes below are byte
	 * identical to PMON start.S:479-482.
	 *
	 * v18 tried this address and heard nothing - but every v17-v21 image also
	 * carried CRMD=0xa8 (the emulator value, see the BOOT_CRMD note), so that
	 * test was never clean.  With 0xb8 restored above, this gets its first real
	 * trial.  PMON locks after DDR; the lock registers are not DDR-dependent,
	 * and the touch walk right after (PMON start.S:507-514, "ensure locked
	 * cache address accessible") makes sure every line is resident before the
	 * first C prologue pushes to it.
	 */
	li.d	$t0, 0x800000001fe00200
	li.d	$t1, ~(0x40000 - 1)
	st.d	$t1, $t0, 0x40			/* size mask: 256 KB */
	li.d	$t1, 0x8000000090000000		/* base 0x90000000 + enable */
	st.d	$t1, $t0, 0x0

	/* Touch walk: read every line once so the lock actually holds it. */
	li.d	$t0, 0x9000000090000000
	li.d	$t1, 0x9000000090040000
1:
	ld.d	$zero, $t0, 0
	addi.d	$t0, $t0, 0x40
	bne	$t1, $t0, 1b

	li.d	$sp, PREMEM_STACK_TOP
	addi.d	$sp, $sp, -0x8

	/*
	 * Pre-DRAM stack probe: write, read back, restore, and report the result
	 * with the buzzer - a stack that no storage backs and a SoC that hangs are
	 * the same thing from outside, which is silence.
	 *
	 * The address above is PMON's own (see the PREMEM_STACK_TOP note), but the
	 * combination - 256 KB of scache locked before DRAM exists and used as a
	 * stack at once - has never run on this board, and PMON itself only stacks
	 * there after DDR init and after it has read the whole region once
	 * (start.S:507-514).  The firmware's first access through the new stack is
	 * PreMemInit's prologue (`st.d $ra,$sp,0x28`), so if the region is not
	 * backed by storage the first C call dies silently.
	 *
	 * Beeps heard after the two above:
	 *
	 *   3 beeps = the address the stack will use writes and reads back
	 *   4 beeps = it does not - the stack region is not backed by memory
	 *   (long gap)
	 *   5 beeps = 0x1c03fff8, the v7 board value inside the boot window,
	 *             writes and reads back
	 *   6 beeps = it does not - the boot window is read-only, as documented
	 *
	 * Silence after the two above, with the board hung here, means the write
	 * to the stack address never completed at all: that is the failure this
	 * probe exists to catch, and it is a different answer from "4 beeps".
	 *
	 * The probe writes $sp itself rather than PREMEM_STACK_TOP: the locked
	 * region is [0x90000000, 0x90040000) and the first push lands at
	 * 0x9003fff8, while the top value 0x90040000 is already past the window
	 * and belongs to the PCIe memory area.  Both addresses keep their original
	 * contents (read, write, read back, write the original back).
	 *
	 * LoongsonBeepRaw is pure assembly with no stack frame and no calls
	 * (Library/LoongsonBootLogLib/LoongsonBeepPmon.S), so calling it cannot be
	 * what fails here; everything else in this block is plain ld/st.
	 */
	or	$t5, $sp, $zero			/* the address the first push will use */
	ld.d	$t7, $t5, 0
	li.d	$t6, 0x0123456789abcdef
	st.d	$t6, $t5, 0
	ld.d	$t8, $t5, 0
	st.d	$t7, $t5, 0
	li.w	$a0, 4
	bne	$t8, $t6, 1f
	li.w	$a0, 3
1:
	bl	LoongsonBeepRaw

	li.w	$t4, 0x400000			/* long gap: keep the two results apart */
2:
	addi.w	$t4, $t4, -1
	bnez	$t4, 2b

	li.d	$t5, 0x1c03fff8
	ld.d	$t7, $t5, 0
	li.d	$t6, 0x0123456789abcdef
	st.d	$t6, $t5, 0
	ld.d	$t8, $t5, 0
	st.d	$t7, $t5, 0
	li.w	$a0, 6
	bne	$t8, $t6, 3f
	li.w	$a0, 5
3:
	bl	LoongsonBeepRaw

	/*
	 * Boot progress log.  Every milestone is recorded in the SPI NOR so a
	 * board with no usable serial console can still be diagnosed by reading
	 * the chip with a programmer (tools/decode_bootlog.py).
	 */
	bl	LoongsonBootLogBoot
	li.w	$a0, BOOTLOG_SEC_ENTRY
	li.d	$a1, 0
	bl	LoongsonBootLogEvent

	bl	PreMemInit		/* C: early UART + SoC early init */

	li.w	$a0, BOOTLOG_SEC_CLK_BEGIN
	li.d	$a1, 0
	bl	LoongsonBootLogEvent
	bl	ClkSettingAsm		/* asm: CPU/DDR/GPU PLLs (PMON port) */

	li.d	$a0, 3			/* audible: clock/PLL bring-up done */
	bl	LoongsonBootBeep

	li.w	$a0, BOOTLOG_SEC_CLK_DONE
	li.d	$a1, 0
	bl	LoongsonBootLogEvent

	li.w	$a0, BOOTLOG_SEC_DDR_BEGIN
	li.d	$a1, 0
	bl	LoongsonBootLogEvent
	bl	DdrEntryAsm		/* asm: DDR3 init + leveling (PMON port),
					   leaves memory size in $s2 */

	li.d	$a0, 4			/* audible: DRAM is up */
	bl	LoongsonBootBeep

	li.w	$a0, BOOTLOG_SEC_DDR_DONE
	move	$a1, $s2		/* memory size reported by the DDR code */
	bl	LoongsonBootLogEvent

	/* DRAM is up: switch the stack to the permanent temporary RAM. */
	li.d	$sp, FixedPcdGet64(PcdOvmfSecPeiTempRamBase) + FixedPcdGet32(PcdOvmfSecPeiTempRamSize)
	addi.d	$sp, $sp, -0x8

	li.w	$a0, BOOTLOG_SEC_TO_PEI
	li.d	$a1, 0
	bl	LoongsonBootLogEvent

	/* Publish the device tree for the FDT based library classes.
	   PostMemInit records the outcome in the boot log itself. */
	bl	PostMemInit

	li.d	$a0, 5			/* audible: SEC finished, PEI next */
	bl	LoongsonBootBeep

	/* Load the exception vector base address */
	li.d	$s0, FixedPcdGet64(PcdLoongArchExceptionVectorBaseAddress)

	/* Construct SEC and PEI step exception environment */
	la.pcrel $a1, ExceptionEntryStart
	la.pcrel $t0, ExceptionEntryEnd
	sub.d	$a2, $t0, $a1
	li.w	$t0, (MAX_LOONGARCH_EXCEPTION +  MAX_LOONGARCH_INTERRUPT) * 512
	bgeu	$a2, $t0, DeadLoop
	move	$a0, $s0
	bl	CopyMem

	/* Configure BSP reset ebase */
	move	$a0, $s0
	bl	SetExceptionBaseAddress

	/* Call the common SEC startup (hands off to the PEI core). */
	li.d	$a0, FixedPcdGet64(PcdOvmfFdBaseAddress)	# FW base
	addi.d	$a1, $sp, 0x8
	bl	SecCoreStartupWithStack
# End of _ModuleEntryPoint

#------------------------------------------------------------------------------
# Secondary core parking (from upstream OvmfPkg/LoongArchVirt Start.S).
#------------------------------------------------------------------------------
ASM_PFX(ClearMailBox):
	/* Clear mailbox */
	li.d	$t1, LOONGARCH_IOCSR_MBUF3
	iocsrwr.d $zero, $t1
	li.d	$t1, LOONGARCH_IOCSR_MBUF2
	iocsrwr.d $zero, $t1
	li.d	$t1, LOONGARCH_IOCSR_MBUF1
	iocsrwr.d $zero, $t1
	li.d	$t1, LOONGARCH_IOCSR_MBUF0
	iocsrwr.d $zero, $t1
	jirl	$zero, $ra, 0
# End of ClearMailBox

ASM_PFX(EnableIPI):
	/* Enable IPI interrupt */
	li.w	$t1, BIT12
	csrxchg	$t1, $t1, LOONGARCH_CSR_ECFG

	li.w	$t2, 0xFFFFFFFFU
	li.d	$t1, LOONGARCH_IOCSR_IPI_EN
	iocsrwr.w $t2, $t1
	jirl	$zero, $ra, 0
# End of EnableIPI

ASM_PFX(GetApicId):
	csrrd	$a0, LOONGARCH_CSR_CPUID
	andi	$a0, $a0, 0x3ff
	jirl	$zero, $ra, 0
# End of GetApicId

ASM_PFX(ApInitStack):
	li.d	$t1, SIZE_1KB
	csrrd	$t0, LOONGARCH_CSR_TMID
	mul.d	$t1, $t0, $t1
	li.d	$t2, FixedPcdGet32(PcdCpuMaxLogicalProcessorNumber)
	bgeu	$t0, $t2, DeadLoop
	li.d	$t0, FixedPcdGet64(PcdOvmfSecPeiTempRamBase) + FixedPcdGet32(PcdOvmfSecPeiTempRamSize) - SIZE_64KB
	sub.d	$sp, $t0, $t1
	addi.d	$sp, $sp, -0x8
	jirl	$zero, $ra, 0
# End of ApInitStack

ASM_PFX(SlaveMain):
	/* Set AP exception handle */
	la.pcrel $a0, ApException
	bl	SetExceptionBaseAddress

	/* Clean up local mail box and open INT */
	bl	ClearMailBox
	bl	EnableIPI
	bl	EnableInterrupts

WaitForWake:
	/* Wait for wakeup */
	bl	CpuSleep
	b	WaitForWake
# End of SlaveMain

.align 12
ASM_PFX(ApException):
	csrrd	$t0, LOONGARCH_CSR_ESTAT
	srli.d	$t0, $t0, 12
	andi	$t0, $t0, 0x1
	beqz	$t0, DeadLoop

	li.d	$t0, LOONGARCH_IOCSR_IPI_STATUS
	iocsrrd.w $t1, $t0
	li.d	$t0, LOONGARCH_IOCSR_IPI_CLEAR
	iocsrwr.w $t1, $t0

	/* Read mail buf and jump to specified entry */
	li.d	$t1, LOONGARCH_IOCSR_MBUF0
	iocsrrd.d $t0, $t1
	beqz	$t0, OutOfException
	csrwr	$t0, LOONGARCH_CSR_ERA
	li.d	$t0, LOONGARCH_IOCSR_MBUF3
	iocsrrd.d $a1, $t0
	bl	ClearMailBox
	beqz	$a1, NoParameterCall

	//
	// If the parameters are not NULL, then calling happened in FW ENV.
	// Set the EBASE to be the same as BSP.
	//
	li.d	$a0, FixedPcdGet64(PcdLoongArchExceptionVectorBaseAddress)
	bl	SetExceptionBaseAddress

	bl	ApInitStack
	bl	GetApicId
	b	OutOfException
NoParameterCall:
	li.w	$t0, BIT2 // IE
	csrxchg	$zero, $t0, LOONGARCH_CSR_PRMD // Clean PIE

OutOfException:
	ertn
# End of ApException


#------------------------------------------------------------------------------
# Early exception catcher: one long buzz, then park.
#
# Reached only if something faulted before the real vector table is installed.
# A long tone (0x400 half periods, eight times a progress beep) so it cannot be
# mistaken for the boot-progress beeps.  No stack, no calls.
#------------------------------------------------------------------------------
EarlyExceptionCatch:
	li.d	$t0, 0x800000001fe00504
	li.w	$t1, 0x80
	ld.w	$t2, $t0, 0
	or	$t2, $t2, $t1
	xor	$t2, $t2, $t1
	st.w	$t2, $t0, 0			# direction: output
	li.d	$t0, 0x800000001fe00514
	li.w	$t3, 0x400
1:
	li.w	$t4, 0x8000
2:
	addi.w	$t4, $t4, -1
	bnez	$t4, 2b
	ld.w	$t2, $t0, 0
	or	$t2, $t2, $t1
	st.w	$t2, $t0, 0			# high
	li.w	$t4, 0x8000
3:
	addi.w	$t4, $t4, -1
	bnez	$t4, 3b
	ld.w	$t2, $t0, 0
	or	$t2, $t2, $t1
	xor	$t2, $t2, $t1
	st.w	$t2, $t0, 0			# low
	addi.w	$t3, $t3, -1
	bnez	$t3, 1b
4:
	b	4b

ASM_PFX(DeadLoop):
	b	DeadLoop
# End of DeadLoop

#------------------------------------------------------------------------------
# Pre-DRAM exception vector, installed by the EENTRY/TLBRENTRY writes in
# _ModuleEntryPoint.  It is reached for any exception or interrupt taken before
# the EDK2 vector replaces it, and it says so on the buzzer instead of going
# silent: a fault taken with a broken stack, or with DRAM still absent, becomes
# audible instead of being indistinguishable from a hang.
#------------------------------------------------------------------------------
	.align 12
ASM_PFX(PreMemExceptionVector):
	/*
	 * One slot per entry offset, 4 bytes each (ECFG.VS = 0): covers all
	 * exception codes 0..63 and the interrupt slots 64..79.
	 */
	.rept 80
	b	PreMemExceptionHandler
	.endr

PreMemExceptionHandler:
	/*
	 * Two beeps, then spin.  GPIO39 as bit 7 of the high word, in the
	 * registers the entry beep and LoongsonBeepRaw already proved, with the
	 * same 0x2000 half period; no stack and no calls, so it also runs for a
	 * fault taken with a broken stack pointer.  Nothing else is touched - no
	 * UART, no APB window, no attempt to resume: the point is to be heard.
	 *
	 * Two beeps are deliberately neither the entry's one nor the BSP's two:
	 * hearing them after an otherwise silent boot means an exception was
	 * taken, and CSR.ESTAT/ERA (readable on a debugger, or by the EDK2 vector
	 * once it is installed) say which one.
	 */
	li.d	$t0, 0x800000001fe00504		/* GPIO39 direction, cleared = output */
	li.d	$t1, 0x800000001fe00514		/* GPIO39 data */
	li.w	$t2, 0x80
	ld.w	$t3, $t0, 0
	or	$t3, $t3, $t2
	xor	$t3, $t3, $t2
	st.w	$t3, $t0, 0
	li.w	$t4, 2
4:
	ld.w	$t3, $t1, 0
	or	$t3, $t3, $t2
	st.w	$t3, $t1, 0			/* high */
	li.w	$t5, 0x2000
5:
	addi.w	$t5, $t5, -1
	bnez	$t5, 5b
	ld.w	$t3, $t1, 0
	or	$t3, $t3, $t2
	xor	$t3, $t3, $t2
	st.w	$t3, $t1, 0			/* low */
	li.w	$t5, 0x2000
6:
	addi.w	$t5, $t5, -1
	bnez	$t5, 6b
	addi.w	$t4, $t4, -1
	bnez	$t4, 4b

7:
	b	7b
# End of PreMemExceptionVector
.end
