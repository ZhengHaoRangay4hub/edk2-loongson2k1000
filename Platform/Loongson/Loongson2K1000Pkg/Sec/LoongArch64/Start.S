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
 * Pre-DRAM stack, at the very top of the 256 KB window that the boot ROM maps
 * over the front of the SPI NOR image (LOCK_CACHE_SIZE = 0x40000 in PMON).
 * That window is writable RAM, so a stack parked at 0x1c040000 grows down into
 * it.  PMON does exactly this: `stack = start + LOCK_CACHE_SIZE` with PMON
 * linked at 0x900000001c000000 but loaded at 0x800000001c000000, which puts
 * the live SP at physical 0x1c040000.
 *
 * QEMU's ls2k machine models 0x1c000000-0x1c0fffff as a read-only SPI ROM, so
 * writes there are dropped and the first `bl`/`ret` flies off.  The QEMU smoke
 * test therefore overrides this at build time (`build -D PREMEM_STACK_TOP=...`,
 * see the DSC) with 0x90040000 - the early stack address hardcoded by the
 * vendor u-boot (0x9000000090040000) - so one source tree produces both the
 * board image and a QEMU-runnable image.
 */
#ifndef PREMEM_STACK_TOP
#define PREMEM_STACK_TOP  0x1c040000
#endif

/* Direct mapping windows, standard convention:
 *   DMW0 0x9000000000000000 : PLV0-3, MAT0 (strongly-ordered uncached)
 *   DMW1 0x8000000000000000 : PLV0-3, MAT1 (coherent cached)
 *
 * This is the mirror of PMON's assignment (PMON: 0x8000 uncached / 0x9000
 * cached); both are self-consistent as long as PHYS_TO_* and the windows agree,
 * which they do - MMIO must land in MAT0 whichever VSEG carries it.         */
#define DMW0_UNCACHED  (0x9000000000000000 | 0xf)
#define DMW1_CACHED    (0x8000000000000000 | 0x1f)

#define CSR_DMW0  0x180
#define CSR_DMW1  0x181
#define CSR_CRMD  0x0

ASM_GLOBAL ASM_PFX(_ModuleEntryPoint)
ASM_PFX(_ModuleEntryPoint):
	/* Disable global interrupt */
	bl	DisableInterrupts

	/* Disable all local interrupt */
	li.w	$a0, 0x1FFF
	bl	DisableLocalInterrupts

	/* Direct mapping windows + direct address mode with cached attribute */
	li.d	$t0, DMW0_UNCACHED
	csrwr	$t0, CSR_DMW0
	li.d	$t0, DMW1_CACHED
	csrwr	$t0, CSR_DMW1
	/*
	 * CRMD = 0xa8: DATF/DATM cached, DA=1 (direct address), PG=0.
	 *
	 * DA has priority over PG on paper, but the pair DA=1/PG=1 is not a legal
	 * encoding: QEMU's ls2k run proves it - with 0xb8 the CPU fetches 0x5555
	 * filler from 0x1c002030 while the memory there holds the correct
	 * `bl 0x1c0020ec`, so the fetch never reaches the instruction.  The
	 * previous 0xb8 read like "DA wins, paging is harmless"; 0xa8 keeps the
	 * direct-address property without asserting paging at the same time.  The
	 * SEC phase runs from the raw 0x1c000000 window (VSEG 0) and has no page
	 * tables, so it needs DA - and PMON never sets DA and PG together either.
	 *
	 * Later phases install their own page tables as usual.
	 */
	li.w	$t0, 0xa8
	csrwr	$t0, CSR_CRMD

	/* Read physical cpu number id */
	bl	GetApicId
	li.d	$t0, BOOTCORE_ID
	bne	$a0, $t0, SlaveMain

	/*
	 * BSP: park the stack in the on-chip SRAM overlay (no DRAM yet),
	 * then run the pre-memory SoC/PLL/DDR bring-up.
	 */
	or	$s0, $zero, $zero	/* memdebug rodata base delta */

	/*
	 * "The reset path is alive."
	 *
	 * Three slow clicks, driven straight from assembly with no stack and no
	 * calls, before anything in the C environment can fail.  Every audible
	 * attempt so far went through a C function whose pitch depended on an
	 * instruction fetch cost that cannot be known from outside -- SEC runs
	 * uncached from the boot window -- and the board answered with silence,
	 * which leaves "the buzzer is mistuned" and "nothing ever ran" looking
	 * exactly alike.
	 *
	 * This separates the two.  The clicks are slow enough that a piezo element
	 * answers with an audible tick whatever the real loop cost is: the high
	 * time is 0x4000 iterations, milliseconds if an iteration is cheap and a
	 * second or two if it is not.  Hearing them means the reset path runs,
	 * GPIO39 still drives the buzzer, and the fault is further down.  Hearing
	 * nothing means the problem is not the tune.
	 *
	 * PMON drives the same pin the same way (BEEP_GPIO 39, direction bit in
	 * 0x1fe00504, data in 0x1fe00514, bit 7 of the high word) and does it
	 * before it configures the APB BAR, which is why this can sit here.
	 */
	li.d	$t0, 0x900000001fe00500
	li.w	$t1, 0x80
	ld.w	$t2, $t0, 4
	or	$t2, $t2, $t1
	xor	$t2, $t2, $t1
	st.w	$t2, $t0, 4		/* GPIO39: the cleared bit means output */

	li.w	$t3, 3
77:
	ld.w	$t2, $t0, 0x14
	or	$t2, $t2, $t1
	st.w	$t2, $t0, 0x14		/* high */
	li.w	$t4, 0x4000
78:
	addi.w	$t4, $t4, -1
	bnez	$t4, 78b
	ld.w	$t2, $t0, 0x14
	or	$t2, $t2, $t1
	xor	$t2, $t2, $t1
	st.w	$t2, $t0, 0x14		/* low */
	li.w	$t4, 0x8000
79:
	addi.w	$t4, $t4, -1
	bnez	$t4, 79b
	addi.w	$t3, $t3, -1
	bnez	$t3, 77b

	li.d	$sp, PREMEM_STACK_TOP
	addi.d	$sp, $sp, -0x8

	/*
	 * Boot progress log.  Every milestone is recorded in the SPI NOR so a
	 * board with no usable serial console can still be diagnosed by reading
	 * the chip with a programmer (tools/decode_bootlog.py).
	 */
	bl	LoongsonBootLogBoot
	li.w	$a0, BOOTLOG_SEC_ENTRY
	li.d	$a1, 0
	bl	LoongsonBootLogEvent

	/*
	 * Mark 0x3F0000: the reset path ran, the direct mapping windows work, and
	 * the controller accepted a command-engine erase.  It is the very first
	 * durable evidence this board can produce, and it needs no console, no
	 * display and no ear -- read the chip back and look at the sector.
	 */
	li.d	$a0, 0x3F0000
	li.d	$a1, 0xa1
	bl	LoongsonBootMark

	bl	PreMemInit		/* C: early UART + SoC early init */

	li.w	$a0, BOOTLOG_SEC_CLK_BEGIN
	li.d	$a1, 0
	bl	LoongsonBootLogEvent
	bl	ClkSettingAsm		/* asm: CPU/DDR/GPU PLLs (PMON port) */

	li.d	$a0, 3			/* audible: clock/PLL bring-up done */
	bl	LoongsonBootBeep

	/* Mark 0x3C0000: the PLLs took the new settings and execution continued. */
	li.d	$a0, 0x3C0000
	li.d	$a1, 0xa4
	bl	LoongsonBootMark

	li.w	$a0, BOOTLOG_SEC_CLK_DONE
	li.d	$a1, 0
	bl	LoongsonBootLogEvent

	li.w	$a0, BOOTLOG_SEC_DDR_BEGIN
	li.d	$a1, 0
	bl	LoongsonBootLogEvent
	bl	DdrEntryAsm		/* asm: DDR3 init + leveling (PMON port),
					   leaves memory size in $s2 */

	/* Mark 0x3B0000: DRAM is up. */
	li.d	$a0, 0x3B0000
	li.d	$a1, 0xa5
	bl	LoongsonBootMark

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

ASM_PFX(DeadLoop):
	b	DeadLoop
# End of DeadLoop
.end
