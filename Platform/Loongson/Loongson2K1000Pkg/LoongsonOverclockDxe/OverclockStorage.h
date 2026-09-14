/** @file
  Loongson overclocking page - shared storage definition (C + VFR).

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __LOONGSON_OVERCLOCK_STORAGE_H__
#define __LOONGSON_OVERCLOCK_STORAGE_H__

#include <Guid/ZeroGuid.h>

//
// CPU frequency selector (index into the option list).
// node_clock = 100MHz / L1_REFC(4) * L1_LOOPC / L1_DIV(1) / L2_DIV(2)
//            = 12.5 MHz * L1_LOOPC
//
#define OC_CPU_800    0x00   /* L1_LOOPC = 64  */
#define OC_CPU_900    0x01   /* L1_LOOPC = 72  */
#define OC_CPU_1000   0x02   /* L1_LOOPC = 80  (spec maximum) */
#define OC_CPU_1100   0x03   /* L1_LOOPC = 88  (overclock)    */
#define OC_CPU_1200   0x04   /* L1_LOOPC = 96  (overclock)    */

#define OC_CPU_DEFAULT  OC_CPU_1000

typedef struct {
  UINT8    CpuFreq;
} LOONGSON_OC_CONFIG;

#define LOONGSON_OC_VAR_GUID  { 0x7c8e1f2b, 0x4a3c, 0x4d4e, { 0x9d, 0x4e, 0x5f, 0x6a, 0x7b, 0x8c, 0x9d, 0x0e } }
#define LOONGSON_OC_VAR_NAME  L"LoongsonOcCfg"
#define LOONGSON_OC_VAR_ID    0x0001
#define LOONGSON_OC_FORMSET_GUID \
  { 0x53a51b92, 0x9c4e, 0x4a2f, { 0xb2, 0x7d, 0x61, 0x0c, 0x8e, 0x35, 0xf1, 0xa4 } }

#endif
