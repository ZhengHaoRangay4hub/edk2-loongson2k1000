/*************************
    Author: Chen xinke
    Funtion: detect all four(maximum) DIMM slots of MC1 and MC0 of one NODE and store the information in s1
    a5.0
    input:
    s1[31:16] MC1 slot1/0 MC0 slot1/0 SPD id
    output:
    s1[63:40] MC1 DIMM info
      [31: 8] MC0 DIMM info
*************************/
//------------------------
#define GET_MC1_SLOT1_ID srli.d a1, t1, 28; andi a1, a1, 0xf;
#define GET_MC1_SLOT0_ID srli.d a1, t1, 24; andi a1, a1, 0xf;
#define GET_MC0_SLOT1_ID srli.d a1, t1, 20; andi a1, a1, 0xf;
#define GET_MC0_SLOT0_ID srli.d a1, t1, 16; andi a1, a1, 0xf;
#ifdef  MULTI_I2C_BUS
#define GET_I2C_NODE_ID_a2 srli.d a2, t1, 4; andi a2, a2, 0x3;
#else
#define GET_I2C_NODE_ID_a2  ;
#endif
//------------------------
//#define DEBUG_PROBE_NODE_DIMM

LEAF(PROBE_NODE_DIMM)
/*************************
    use registers:
    a0, a1, a2, a3
    a4, a5
    t0: store MC1 DIMM infor during detect MC0 DIMM
    t1: store s1
    t3, t4: store DIMM infor temporary, should.d be reserved by PROBE_DIMM
    t5: by child.d PROBE_DIMM
    t6: temp variable
    t7: by child.d PROBE_DIMM
    t8: store ra

    child.d must reserve: t0, t1, t3, t8, s1
    i2cread must reserve: a0, t0, t1, t3, t5, t7, t8, s1
*************************/
    or    t8, ra, zero

    or    t1, s1, zero
    bl     i2cinit
    nop
#if 0  //for debug, give the SPD device id directly.
//scan the devices and display DIMM SPD values when the first device is detected.
    MM_PRINTSTR("\r\nDIMM SPD register dump:");
    li.d     a0, 0xa1;
    li.d     a1, 0x2;
    GET_I2C_NODE_ID_a2
    bl     i2cread;
    nop;
    li.d     t3, 0x80
    bltu    a4, t3, 2f
    nop
    li.d     a0, 0xa3;
    li.d     a1, 0x2;
    GET_I2C_NODE_ID_a2
    bl     i2cread;
    nop;
    li.d     t3, 0x80
    bltu    a4, t3, 2f
    nop
    li.d     a0, 0xa5;
    li.d     a1, 0x2;
    GET_I2C_NODE_ID_a2
    bl     i2cread;
    nop;
    li.d     t3, 0x80
    bltu    a4, t3, 2f
    nop
    li.d     a0, 0xa7;
    li.d     a1, 0x2;
    GET_I2C_NODE_ID_a2
    bl     i2cread;
    nop;
    li.d     t3, 0x80
    bltu    a4, t3, 2f
    nop
    b       3f
    nop
2:
    or    t3, a0, zero
    MM_PRINTSTR("\r\na0=0x");
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n");
    li.d     t0, 0x0; //used as counter
1:
    or    a0, t0, zero;
    bl     mm_hexserial
    nop
    MM_PRINTSTR(": ");
    or    a0, t3, zero
    or    a1, t0, zero;
    GET_I2C_NODE_ID_a2
    bl     i2cread;
    nop;
    or    a0, a4, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n");
    nop

    li.d     a1, 0x80
    addi.d  t0, 0x1;
    bne     t0, a1, 1b;
    nop
3:
    MM_PRINTSTR("\r\n^^^^^^^^^^^^^^^^^^^^^^^^^^^^\r\n");
#endif

    li.d     a1, 0xff
    and     t0, t1, a1
//-------------------------------------
10:

//detect MC1 if not define MC0_ONLY
    GET_MC0_ONLY
    bnez    a1, 11f
    nop
    //do auto probe DIMM
    MM_PRINTSTR("\r\nProbing DDR MC1 SLOT: ");
    MM_PRINTSTR("\r\nProbe MC1 slot 0.");
    li.d     a1, 0xff
    and     s1, s1, a1
    GET_MC1_SLOT0_ID
    li.d     a0, 0x8
    bgeu    a1, a0, 1f  //invalidate device id
    nop
    slli.d    a1, a1, 1
    ori     a0, a1, 0xa1
    bl     PROBE_DIMM;
    nop;
1:
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR(" s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
    //store slot 0 DIMM infor in t3
    or    t3, s1, zero

    MM_PRINTSTR("\r\nProbe MC1 slot 1.");
    li.d     a1, 0xff
    and     s1, s1, a1
    GET_MC1_SLOT1_ID
    li.d     a0, 0x8
    bgeu    a1, a0, 1f  //invalidate device id
    nop
    slli.d    a1, a1, 1
    ori     a0, a1, 0xa1
    bl     PROBE_DIMM;
    nop;
1:
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR(" s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
    //store slot 1 DIMM infor in t4
    or    t4, s1, zero

    //compare the two slot DIMM infor and merge the CS_MAP and MC1_MEMSIZE if necessary
    or    s1, t3, zero
    GET_SDRAM_TYPE
    beqz    a1, 1f
    nop
    or    s1, t4, zero
    GET_SDRAM_TYPE
    beqz    a1, 2f
    nop
    //both slot 0 and 1 has DIMM
    //step 1: compare the two DIMM type infor, if they differs, display errors
    xor     a1, t3, t4
    li.d     a0, 0xfff08000
    and     a1, a1, a0
    bnez    a1, 9f
    nop
    //step 2: if the two DIMM types are equal, merge the CS_MAP and MC1_MEMSIZE
    //1. Calculate new CS_MAP
    or    s1, t4, zero
    GET_MC_CS_MAP
    slli.d    a0, a1, 2
    or    s1, t3, zero
    GET_MC_CS_MAP
    or      t6, a0, a1
    slli.d    t6, t6, MC_CS_MAP_OFFSET    //store new MC_MAP in t6
    //2. merge MC1_MEMSIZE
    or    s1, t3, zero
    GET_DIMM_MEMSIZE
    or    a0, a1, zero
    or    s1, t4, zero
    GET_DIMM_MEMSIZE
    add.d   a1, a1, a0
    li.d     a0, MC_MEMSIZE_MASK //make sure a1 not exceed its range
    and     a1, a1, a0
    slli.d    a1, a1, MC0_MEMSIZE_OFFSET
    li.d     a0, MC_MEMSIZE_MASK
    slli.d    a0, a0, MC0_MEMSIZE_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
    //3. merge new MC_CS_MAP(in t6) to s1, do not affect other bits
    li.d     a0, 0xf
    slli.d    a0, a0, MC_CS_MAP_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, t6
    b       3f
    nop
9:  //two slot have different type DIMM, give ERROR message and use slot 0 only
    MM_PRINTSTR("MC0 has two different DIMM, please use same DIMM!!\r\n")
    MM_PRINTSTR("Currently system will use only slot 0!!\r\n")
    b       2f
    nop
2:  //no DIMM in slot 1 and slot 0 has DIMM
    or    s1, t3, zero
    b       4f
    nop
1:  //no DIMM in slot 0
    or    s1, t4, zero
    GET_SDRAM_TYPE
    beqz    a1, 1f
    nop
    //only slot 1 has DIMM, firstly shift the CS_MAP to upper 2 bit
    or    s1, t4, zero
    GET_MC_CS_MAP
    slli.d    a1, a1, (MC_CS_MAP_OFFSET + 2)
    li.d     a0, 0xf
    slli.d    a0, a0, MC_CS_MAP_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
    b       4f
    nop
4:  //move DIMM_MEMSIZE to MC0_MEMSIZE
    GET_DIMM_MEMSIZE
    slli.d    a1, a1, MC0_MEMSIZE_OFFSET
    li.d     a0, MC_MEMSIZE_MASK
    slli.d    a0, a0, MC0_MEMSIZE_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
    b       3f
    nop
1:  //no DIMM in slot 0 and 1
    MM_PRINTSTR("\r\nNO DIMM in MC1 slot.\r\n");
    b       11f
    nop
3:  //move MC1 DIMM info to t0 high 32 bit
    li.d     a0, 0xffffffff
    and     s1, s1, a0
    slli.d    a1, s1, 32
    or      a1, s1, a1
    li.d     a0, 0xffffff00000000ff
    and     s1, a1, a0
    or    t0, s1, zero
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR("\r\n T5 s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
    /* show value of t0 */
    MM_PRINTSTR("\r\n t0 = 0x");
    srli.d    a0, t0, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, t0, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
//-------------------------------------
11:
//detect MC0 if not define MC1_ONLY
    GET_MC1_ONLY
    bnez    a1, 12f
    nop
    //do auto probe DIMM
    MM_PRINTSTR("\r\nProbing DDR MC0 SLOT: ");
    MM_PRINTSTR("\r\nProbe MC0 slot 0.");
    li.d     a1, 0xff
    and     s1, s1, a1
    GET_MC0_SLOT0_ID
    li.d     a0, 0x8
    bgeu    a1, a0, 1f  //invalidate device id
    nop
    slli.d    a1, a1, 1
    ori     a0, a1, 0xa1
    bl     PROBE_DIMM;
    nop;
1:
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR(" s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
    //store slot 0 DIMM infor in t3
    or    t3, s1, zero

    MM_PRINTSTR("\r\nProbe MC0 slot 1.");
    li.d     a1, 0xff
    and     s1, s1, a1
    GET_MC0_SLOT1_ID
    li.d     a0, 0x8
    bgeu    a1, a0, 1f  //invalidate device id
    nop
    slli.d    a1, a1, 1
    ori     a0, a1, 0xa1
    bl     PROBE_DIMM;
    nop;
1:
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR(" s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
    //store slot 1 DIMM infor in t4
    or    t4, s1, zero

    //compare the two slot DIMM infor and merge the CS_MAP and MC0_MEMSIZE if necessary
    or    s1, t3, zero
    GET_SDRAM_TYPE
    beqz    a1, 1f
    nop
    or    s1, t4, zero
    GET_SDRAM_TYPE
    beqz    a1, 2f
    nop
    //both slot 0 and 1 has DIMM
    //step 1: compare the two DIMM type infor, if they differs, display errors
    xor     a1, t3, t4
    li.d     a0, 0xfff08000
    and     a1, a1, a0
    bnez    a1, 9f
    nop
    //step 2: if the two DIMM types are equal, merge the CS_MAP and MC0_MEMSIZE
    //1. Calculate new CS_MAP
    or    s1, t4, zero
    GET_MC_CS_MAP
    slli.d    a0, a1, 2
    or    s1, t3, zero
    GET_MC_CS_MAP
    or      t6, a0, a1
    slli.d    t6, t6, MC_CS_MAP_OFFSET    //store new MC_MAP in t6, don't move to s1 imediately because when merge MC_MEMSIZE, s1 will be damaged
    //2. merge MC0_MEMSIZE
    or    s1, t3, zero
    GET_DIMM_MEMSIZE
    or    a0, a1, zero
    or    s1, t4, zero
    GET_DIMM_MEMSIZE
    add.d   a1, a1, a0
    li.d     a0, MC_MEMSIZE_MASK //make sure a1 not exceed its range
    and     a1, a1, a0
    slli.d    a1, a1, MC0_MEMSIZE_OFFSET
    li.d     a0, MC_MEMSIZE_MASK
    slli.d    a0, a0, MC0_MEMSIZE_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR("\r\n T3 s1 = 0x");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
    //3. merge new MC_CS_MAP(in t6) to s1, do not affect other bits
    li.d     a0, 0xf
    slli.d    a0, a0, MC_CS_MAP_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, t6
    b       3f
    nop
9:      //two slot have different type DIMM, give ERROR message and use slot 0 only
    MM_PRINTSTR("MC0 has two different DIMM, please use same DIMM!!\r\n")
    MM_PRINTSTR("Currently system will use only slot 0!!\r\n")
    b       2f
    nop
2:  //no DIMM in slot 1 and slot 0 has DIMM
    or    s1, t3, zero
    b       4f
    nop
1:  //no DIMM in slot 0
    or    s1, t4, zero
    GET_SDRAM_TYPE
    beqz    a1, 1f
    nop
    //only slot 1 has DIMM, firstly shift the CS_MAP to upper 2 bit
    or    s1, t4, zero
    GET_MC_CS_MAP
    slli.d    a1, a1, (MC_CS_MAP_OFFSET + 2)
    li.d     a0, 0xf
    slli.d    a0, a0, MC_CS_MAP_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
    b       4f
    nop
4:  //move DIMM_MEMSIZE to MC0_MEMSIZE
    GET_DIMM_MEMSIZE
    slli.d    a1, a1, MC0_MEMSIZE_OFFSET
    li.d     a0, MC_MEMSIZE_MASK
    slli.d    a0, a0, MC0_MEMSIZE_OFFSET
    nor     a0, a0, zero
    and     s1, s1, a0
    or      s1, s1, a1
    b       3f
    nop
1:  //no DIMM in slot 0 and 1
    MM_PRINTSTR("\r\nNO DIMM in MC0 slot.\r\n");
    b       3f
    nop
3:
#ifdef  DEBUG_PROBE_NODE_DIMM
    /* show value of s1 */
    MM_PRINTSTR("\r\n T5 s1 = ");
    srli.d    a0, s1, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, s1, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
    /* show value of t0 */
    MM_PRINTSTR("\r\n t0 = 0x");
    srli.d    a0, t0, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("__")
    or    a0, t0, zero
    bl     mm_hexserial
    nop;
    MM_PRINTSTR("\r\n")
#endif
//merge MC1 and MC0 DIMM infor to s1
    li.d     a1, 0xffffff0000000000
    and     t0, t0, a1
    li.d     a1, 0xffffffff
    and     s1, s1, a1
    or      s1, s1, t0
12:
    or    ra, t8, zero
    jirl    zero, ra, 0
    nop
END(PROBE_NODE_DIMM)

/*************************
PROBE_DIMM:
function: probe the given slot(I2C device id is given in a0),
      if there is no DIMM in this slot, clear SDRAM_TYPE to 0,
      else read the DIMM infor from the SPD and store the infor
      in s1(CS_MAP at s1[MC_CS_MAP_OFFSET+2, MC_CS_MAP_OFFSET],
      MEMSIZE at s1[DIMM_MEMSIZE_OFFSET+7: DIMM_MEMSIZE_OFFSET]).
note: don't change t0, t1, t3, t8, s1

use register:
a0,a1,a2,a3
a4,a5
t5, t7

input: a0, t1
    a0:i2c device id(don't change it).
    t1[5:4]: NODE_ID
usage:
a1: register offset of i2c device
a2: I2C NODE ID
t5: temp vary.
t7: store ra

+++child.d must reserve: t7.

    child.d must reserve: a0, t0, t1, t3, t5, t7, t8, s1
*************************/
#if 0   //debug code, used in PROBE_DIMM, after read i2c, print a4
    //debug----------
    or    t5, a0, zero
    MM_PRINTSTR("\r\na0=0x");
    or    a0, t5, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n");
    or    a0, t5, zero
    //------------debug

    //Test whether i2cread will dead loop
    or    t5, a0, zero
    MM_PRINTSTR("\r\nIn Probe_DIMM, before i2cread!")
    or    a0, t5, zero
    li.d     a1, 0
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    or    t5, a0, zero
    MM_PRINTSTR("\r\nIn Probe_DIMM, after i2cread!")
    or    a0, t5, zero
#endif
LEAF(PROBE_DIMM)
    or    t7, ra, zero

//read the i2c spd for learn,read data is abandon
    li.d     a1, 0
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop

#if 0
//probe SDRAM type, if SDRAM type error, repeat t5 times.----seems no benefit
    li.d     t5, 1   //max probing times(t5)
1:
    addi.d  t5, t5, -1
#endif

    li.d     a1, 2
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
    /* a4 should.d be 0xb or 0x8,else error DIMM type */
    li.d     a1, 0x08
    beq     a4, a1, DDR2
    nop
    li.d     a1, 0x0B
    beq     a4, a1, DDR3
    nop
#if 0
    //this time probe error
//delay some time
    li.d     a1, 0x1000
2:
    addi.d  a1, a1, -1
    bnez    a1, 2b
    nop

    bnez    t5, 1b
    nop
#endif
    MM_PRINTSTR("\r\nNO DIMM in this slot.\r\n")
    b       ERROR_TYPE
    nop
DDR2:
    li.d     t5, 0x2
    slli.d    t5, t5, SDRAM_TYPE_OFFSET
    or      s1, s1, t5
//probe DIMM_TYPE
    li.d     a1, 20
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[5:0] used
    andi    a4, a4, 0x3f
    //here just recognize RDIMM ,UDIMM and SODIMM
    li.d     t5, 0x01
    beq     a4, t5, 1f
    nop
    li.d     t5, 0x02
    beq     a4, t5, 2f
    nop
    li.d     t5, 0x04    //SODIMM, deal as UDIMM
    beq     a4, t5, 2f
    nop
    MM_PRINTSTR("\r\nERROR: DIMM type is not in support range(UDIMM or RDIMM).\r\n")
    b       ERROR_TYPE
    nop
1:  //RDIMM
    li.d     t5, 0x1
    slli.d    t5, t5, DIMM_TYPE_OFFSET
    or      s1, s1, t5
    b       3f
    nop
2:  //UDIMM
    b       3f
    nop
3:
//probe DIMM WIDTH
    li.d     a1, 6
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
    //simply deal here
    li.d     t5, 0x40
    bge     a4, t5, 1f
    nop
    //reduc size
    li.d     t5, 1
    slli.d    t5, t5, DIMM_WIDTH_OFFSET
    or      s1, s1, t5
1:  //normal size, do nothing
//probe DIMM ECC
    li.d     a1, 11
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[1] used
    andi    t5, a4, 0x2
    srli.d    t5, t5, 1
    slli.d    t5, t5, DIMM_ECC_OFFSET
    or      s1, s1, t5
//probe SDRAM_WIDTH
    li.d     a1, 13
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
    //only check bit 4(here assuming x8 or x16 only)
    srli.d    t5, a4, 4
    andi     t5, t5, 0x1
    slli.d    t5, t5, SDRAM_WIDTH_OFFSET
    or      s1, s1, t5
//probe SDRAM_ROW_SIZE
    li.d     a1, 3
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
    //a4 should.d <= MAX_ROW_SIZE
    andi    a4, a4, 0x1f
    li.d     t5, MAX_ROW_SIZE
    sub.d   t5, t5, a4
    slli.d    t5, t5, ROW_SIZE_OFFSET
    or      s1, s1, t5
//probe SDRAM_COL_SIZE
    li.d     a1, 4
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
    //a4 should.d < 14
    andi    a4, a4, 0x0f
    li.d     t5, 12
    sub.d   t5, t5, a4
    slli.d    t5, t5, COL_SIZE_OFFSET
    or      s1, s1, t5
//probe SDRAM BANK number
    li.d     a1, 17
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //bit[7:0] used
    andi    a4, a4, 0xff
    //here just recognize 4 banks or 8 banks
    li.d     t5, 0x08
    beq     a4, t5, 1f
    nop
    li.d     t5, 0x04
    beq     a4, t5, 2f
    nop
    MM_PRINTSTR("\r\nERROR: SDRAM Banks number is not in support range(4 or 8).\r\n")
    b       ERROR_TYPE
    nop
1:  //8 banks
    li.d     t5, 0x1
    slli.d    t5, t5, EIGHT_BANK_OFFSET
    or      s1, s1, t5
    b       3f
    nop
2:  //4 banks
    //nothing need to do

3:
//probe DIMM Ranks
    li.d     a1, 5
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[2:0] used
    andi    a4, a4, 0x7
    //here just recognize 1 ranks or 2 ranks
    li.d     t5, 0x0
    beq     a4, t5, 1f
    nop
    li.d     t5, 0x1
    beq     a4, t5, 2f
    nop
    MM_PRINTSTR("\r\nERROR: DIMM Ranks number is not in support range(1 or 2).\r\n")
    b       ERROR_TYPE
    nop
1:  //1 rank
    li.d     t5, 0x1
    b       3f
    nop
2:  //2 ranks
    li.d     t5, 0x3
3:
    slli.d    t5, t5, MC_CS_MAP_OFFSET
    or      s1, s1, t5
//probe DIMM Density
    li.d     a1, 31
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[7:0] used
    andi    a4, a4, 0xff
//currently only support 512M <= 1DIMM size <= 7.5G, else assume there is no dimm by clear SDRAM_TYPE
    or    t5, a4, zero
    //we need to reorder t5 to normal order to represent 1 rank density(/128M)
    //because of the JEDEC SPD spec awkward defination.
    li.d     a1, 0xe0
    and     a1, t5, a1
    beqz    a1, 1f
    nop
    //1 rank<= 512M
    srli.d    t5, t5, 5
    b       2f
    nop
1:  //1 rank >= 1G
    slli.d    t5, t5, 3
2:
    //here, the 1 rank size is store in t5 in normal order, measured by 128M.
    //double the MEMSIZE if there are 2 ranks
    GET_MC_CS_MAP
    srli.d    a1, a1, 1   //test the cs 1
    sll.d    t5, t5, a1  //double the size if a1 = 1
    srli.d    t5, t5, 2   //change measure unit to 512M
    andi    t5, t5, DIMM_MEMSIZE_MASK
    //check size is 0
    bnez    t5, 1f
    nop
//DIMM density < 512M or > 63.5G, errors(clear SDRAM_TYPE, assume there is NO DIMM in this slot)
    li.d     t5, 0x3
    slli.d    t5, t5, SDRAM_TYPE_OFFSET
    nor     t5, t5, zero
    and     s1, s1, t5
    MM_PRINTSTR("\r\nERROR: DIMM size is not in support range(512M~63.5G).\r\n")
    b       ERROR_TYPE
    nop
1:
    slli.d    t5, t5, DIMM_MEMSIZE_OFFSET
    or      s1, s1, t5
//DDR2 probe finished
    b       probe_dimm_end
    nop

DDR3:  //DDR3 SDRAM
    li.d     t5, 0x3
    slli.d    t5, t5, SDRAM_TYPE_OFFSET
    or      s1, s1, t5
//!!!!!!need to be completely tested
//probe DIMM_TYPE
    li.d     a1, 0x3
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[3:0] used
    andi    a4, a4, 0xf
    //here just recognize RDIMM ,UDIMM and SODIMM
    li.d     t5, 0x01
    beq     a4, t5, 1f
    nop
    li.d     t5, 0x02
    beq     a4, t5, 2f
    nop
    li.d     t5, 0x03    //SODIMM, deal as UDIMM
    beq     a4, t5, 2f
    nop
    MM_PRINTSTR("\r\nERROR: DIMM type is not in support range(UDIMM or RDIMM).\r\n")
    b       ERROR_TYPE
    nop
1:  //RDIMM
    li.d     t5, 0x1
    slli.d    t5, t5, DIMM_TYPE_OFFSET
    or      s1, s1, t5
    b       3f
    nop
2:  //UDIMM

    b       3f
    nop
3:
//probe DIMM WIDTH and DIMM ECC
    li.d     a1, 8
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //bit[2:0]: DIMM_WIDTH, bit[3]: with ECC or not
    andi    a5, a4, 0x7
    //simply deal here
    li.d     t5, 0x2
    beq  a5, t5, 99f;     bge     a5, t5, 1f;99:
    nop
    //reduc size
    li.d     t5, 1
    slli.d    t5, t5, DIMM_WIDTH_OFFSET
    or      s1, s1, t5
1:  //normal size, do nothing
    //set DIMM_ECC
    andi    t5, a4, 0x8
    srli.d    t5, t5, 3
    slli.d    t5, t5, DIMM_ECC_OFFSET
    or      s1, s1, t5
//probe SDRAM_WIDTH
    li.d     a1, 7
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[2:0] used
    andi    a4, a4, 0x7
    //only check bit 1(here assuming x8 or x16 only)
    srli.d    t5, a4, 1
    andi    t5, t5, 0x1
    slli.d    t5, t5, SDRAM_WIDTH_OFFSET
    or      s1, s1, t5
//probe SDRAM_ROW_SIZE & SDRAM_COL_SIZE
    li.d     a1, 5
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[5:0] used
    andi    a4, a4, 0x3f
    //set row size
    andi    a5, a4, 0x38
    srli.d    a5, a5, 0x3
    //li.d     t5, 3
    li.d     t5, MAX_ROW_SIZE
    li.d tp, 12; sub.d   t5, t5, tp
    ble     a5, t5, 1f
    nop
    MM_PRINTSTR("\r\nERROR: The SDRAM Row size is too big(> MAX_ROW_SIZE).\r\n")
    b       ERROR_TYPE
    nop
1:
    sub.d   t5, t5, a5
    slli.d    t5, t5, ROW_SIZE_OFFSET
    or      s1, s1, t5
    //set SDRAM_COL_SIZE
    andi    a4, a4, 0x3 //the bit 2 is reserved currently.
    li.d     t5, 3
    sub.d   t5, t5, a4
    slli.d    t5, t5, COL_SIZE_OFFSET
    or      s1, s1, t5
//probe SDRAM BANK number
    li.d     a1, 4
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //bit[6:0] used
    andi    a4, a4, 0x7f
    //here just support 8 banks
    andi    a5, a4, 0x70
    beqz    a5, 1f
    nop
    MM_PRINTSTR("\r\nERROR: SDRAM Banks number is not supported(only support 8 banks now).\r\n")
    b       ERROR_TYPE
    nop
1:  //8 banks
    li.d     t5, 0x1
    slli.d    t5, t5, EIGHT_BANK_OFFSET
    or      s1, s1, t5

//probe DIMM Ranks
    li.d     a1, 7
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[5:3] used
    andi    a4, a4, 0x38
    srli.d    a4, a4, 3
    //here just recognize 1 ranks or 2 ranks
    li.d     t5, 0x0
    beq     a4, t5, 1f
    nop
    li.d     t5, 0x1
    beq     a4, t5, 2f
    nop
    MM_PRINTSTR("\r\nERROR: DIMM Ranks number is not in support range(1 or 2).\r\n")
    b       ERROR_TYPE
    nop
1:  //1 rank
    li.d     t5, 0x1
    b       3f
    nop
2:  //2 ranks
    li.d     t5, 0x3
3:
    slli.d    t5, t5, MC_CS_MAP_OFFSET
    or      s1, s1, t5
//probe DIMM Density
//DIMM Density = SDRAM Density / 8 * DIMM Width / SDRAM Width * Ranks
    li.d     a1, 4
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[3:0] used
    andi    a4, a4, 0x7 //bit 3 is reserved by JEDEC now
    li.d     t5, 0x1
    sll.d    t5, t5, a4
    //here t5 represent SDRAM Density in 256Mb
    slli.d    t5, t5, 3   //*8 (64 bit width)
    GET_DIMM_WIDTH
    srl.d    t5, t5, a1  //if reduc=1, t5=t5 / 2
    //here t5 = SDRAM Density / 8 * DIMM Width
    //probe SDRAM Width
    li.d     a1, 7
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[2:0] used
    andi    a4, a4, 0x3 //bit 2 is reserved now
    li.d     a5, 0x2
    add.d   a4, a4, a5
    srl.d    t5, t5, a4  //t5 /= SDRAM Width
    //here t5 = SDRAM Density / 8 * DIMM Width / SDRAM Width
    //here, the 1 rank size is store in t5 in normal order, measured by 256M.
    //double the MEMSIZE if there are 2 ranks
    GET_MC_CS_MAP
    srli.d    a1, a1, 1   //test the cs 1
    sll.d    t5, t5, a1  //double the size if a1=1
    srli.d    t5, t5, 1   //change measure unit to 512M
    andi    t5, t5, DIMM_MEMSIZE_MASK
    //check size is 0
    bnez    t5, 1f
    nop
//DIMM density < 512M or > 63.5G, errors(clear SDRAM_TYPE, assume there is NO DIMM in this slot)
    li.d     t5, 0x3
    slli.d    t5, t5, SDRAM_TYPE_OFFSET
    nor     t5, t5, zero
    and     s1, s1, t5
    MM_PRINTSTR("\r\nERROR: DIMM size is not in support range(512M~63.5G).\r\n")
    b       ERROR_TYPE
    nop
1:
    slli.d    t5, t5, DIMM_MEMSIZE_OFFSET
    or      s1, s1, t5

    GET_DIMM_TYPE
    bnez    a1, 1f
    nop
//DDR3 UDIMM -- probe DIMM Address Mirroring
    li.d     a1, 63
    GET_I2C_NODE_ID_a2
    bl     i2cread
    nop
    //only bit[0] used
    andi    a4, a4, 0x1
    or    t5, a4, zero
    slli.d    t5, t5, ADDR_MIRROR_OFFSET
    or      s1, s1, t5
1:
//DDR3 probe finished
    b       probe_dimm_end
    nop

ERROR_TYPE:
//no DIMM or unrecognized DIMM in this slot
    li.d     t5, 0x3
    slli.d    t5, t5, SDRAM_TYPE_OFFSET
    nor     t5, t5, zero
    and     s1, s1, t5
probe_dimm_end:
    or    ra, t7, zero
    jirl    zero, ra, 0
    nop
END(PROBE_DIMM)


LEAF(READ_DIMM_IDENTIFIER)
/********************
input:
    a0: bit[3:0] i2c addr
    a2: i2c bus node id
output:
    t4/t5: dimm indentifier
use: a0~a2, a4, a5, t8
********************/
    or    t8, ra, zero

    nor     t4, zero, zero
    nor     t5, zero, zero
    li.d     a1, 0x8
    bgeu    a0, a1, 8f
    nop
    or    t4, zero, zero
    or    t5, zero, zero
    slli.d    a0, a0, 1
    ori     a0, a0, 0xa1
    //test no meaning
    li.d     a1, 0
    bl     i2cread
    nop
#ifdef  DDR3_DIMM
    li.d     a1, 2
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    li.d     a1, 0x0b
    beq     a4, a1, 1f
    nop
    nor     t4, zero, zero
    nor     t5, zero, zero
    b       8f
    nop
1:
    //read manufater JEDEC ID
    li.d     a1, 117
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    //read other info
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
#else   //DDR2
    li.d     a1, 2
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    li.d     a1, 0x08
    beq     a4, a1, 1f
    nop
    nor     t4, zero, zero
    nor     t5, zero, zero
    b       8f
    nop
1:
    //read manufater JEDEC ID
    li.d     a1, 64
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    li.d     a1, 64
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    li.d     a1, 64
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    li.d     a1, 64
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    slli.d    t4, t4, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t4, t4, a4
    //read other info
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
    addi.d   a1, a1, 1
    bl     i2cread
    nop
    andi    a4, a4, 0xff
    or      t5, t5, a4
    slli.d    t5, t5, 8
#endif
8:

    or    ra, t8, zero
    jirl    zero, ra, 0
    nop
END(READ_DIMM_IDENTIFIER)

#ifdef  MULTI_I2C_BUS
#define GET_I2C_NODE_ID_a2_1 srli.d a2, s1, 4; and a2, a2, 0x3;
#else
#define GET_I2C_NODE_ID_a2_1  ;
#endif

LEAF(CHECK_DIMM_CHANGE)
/**********************
    check whether the 2 DIMMs are changed
input:
    s1: NODE_ID, I2C node ID
    t1: MC slot I2C addr
    t7: mc_level_info address
output:
    a4: return value
register usage:
    a6: save ra
    t8: by child.d READ_DIMM_IDENTIFIER
    t4/t5: dimm info
**********************/

    or    a6, ra, zero

    //check slot 0 DIMM
    andi    a0, t1, 0xf
    GET_I2C_NODE_ID_a2_1
    bl     READ_DIMM_IDENTIFIER
    nop
    ld.d      a1, t7, 0x8
    bne     t4, a1, do_arb_level
    nop
    ld.d      a1, t7, 0x10
    bne     t5, a1, do_arb_level
    nop
    //check slot 1 DIMM
    srli.d    a0, t1, 4
    andi    a0, a0, 0xf
    GET_I2C_NODE_ID_a2_1
    bl     READ_DIMM_IDENTIFIER
    nop
    ld.d      a1, t7, 0x18
    bne     t4, a1, do_arb_level
    nop
    ld.d      a1, t7, 0x20
    bne     t5, a1, do_arb_level
    nop

//do_not_arb_level:
    or    a4, zero, zero
    or    ra, a6, zero
    jirl    zero, ra, 0
    nop

do_arb_level:
    ori      a4, zero, 0x1
    or    ra, a6, zero
    jirl    zero, ra, 0
    nop
END(CHECK_DIMM_CHANGE)
