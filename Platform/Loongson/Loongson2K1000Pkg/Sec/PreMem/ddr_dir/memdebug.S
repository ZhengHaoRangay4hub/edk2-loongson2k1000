//!!!!note: inputaddress and Inputhex have been changed by cxk!!!!
//note: inputaddress will damage a6
    b       22f
    nop
inputaddress:
	  or  a6, ra, zero
	  MM_PRINTSTR("16'h");
	  li.w a0,16
	  bl Inputhex
	  nop
      or  ra, a6, zero
	  jirl	zero, ra, 0
	  nop

LEAF(Inputhex)
/*********
 * a4: return value
 * a5: volatile
 * a0: input--loop times, then used for tgt_putchar input param
 * a1: loop counter
 * a2: temp store of inputted value
 * a3: store ra
**********/
	or a3,ra, zero
	or a1,a0, zero
	or a2,zero, zero
1:
	bl mm_tgt_getchar
	nop
	li.w a5,'q'
	beq a4,a5,3f
	nop
	li.w a5,0x20	//space
	beq a5,a4,3f
	nop
	li.w a5,0xd	//CR
	beq a5,a4,3f
	nop
	li.w a5,0x8	//backspace
	beq a5,a4,4f
	nop
	li.w a5,'x'
	beq a5,a4,4f
	nop

	slti a5,a4,'0'
	bnez a5,1b
	nop

	slti tp,a4,'9'+1
	or a5,a4, zero
	bnez tp,2f

	slti a5,a4,'a'
	bnez a5,1b
	nop

	slti tp,a4,'f'+1
	or a5,a4, zero
	beqz tp,1b
    li.d tp, 'a' - 10 - '0'
    sub.d a4, a4, tp
//	addi.w a4, a4, 10-'a'+'0'
2:
    li.d tp, '0' - 0
    sub.d a4, a4, tp
//	addi.w a4, a4, 0-'0'
	slli.d a2, a2,4
	or a2,a4,a2
	or a0,a5, zero
	bl mm_tgt_putchar
	nop
    li.d    tp, 1
    sub.d   a1, a1, tp
	//addi.w  a1, a1, -1
	bnez a1,1b
	nop
	li.w a5,0
3:
	or a4,a2, zero
    or    ra, a3, zero
    jirl    zero, ra, 0
	nop
4:
	srli.d a2, a2, 4
	li.w	a5, 16
	bgeu a1, a5, 1b
	nop
	addi.d a1, a1, 1
	li.w a0,'\b'
	bl mm_tgt_putchar
	nop
	li.w a0,0x20	  //space
	bl mm_tgt_putchar
	nop
	li.w a0,'\b'
	bl mm_tgt_putchar
	nop
	b 1b
	nop
END(Inputhex)

LEAF(mm_tgt_putchar)
    li.d  a4, COM1_BASE_ADDR
1:
    ld.bu a5, a4, NSREG(NS16550_LSR)
    andi   a5, a5, LSR_TXRDY
    beqz    a5, 1b
    nop

    st.b  a0, a4, NSREG(NS16550_DATA)
   jirl    zero, ra, 0
    nop
END(mm_tgt_putchar)

LEAF(mm_hexserial64)
	ori	a2, ra, 0
	ori	a1, a0, 0
	li.d	a3, 16
1:
	rotri.d a0, a1, 60
	or	a1, a0, zero
	andi	a0, a0, 0xf

	la	a4, hexchar
	sub.d	a4, a4, s0

	add.d	a4, a4, a0
	ld.bu	a0, a4, 0

	bl	mm_tgt_putchar

	addi.d	a3, a3, -1
	bnez	a3, 1b

	ori	ra, a2, 0
	jirl	zero, ra, 0
END(mm_hexserial64)

LEAF(mm_stringserial)
	move	a2, ra
	sub.d	a1, a0, s0
	ld.bu	a0, a1, 0
1:
	beqz	a0, 2f

	addi.d	a1, a1, 1
	bl	mm_tgt_putchar

	ld.bu	a0, a1, 0
	b	1b
2:
	move	ra, a2
	jirl	zero, ra, 0
END(mm_stringserial)

LEAF(mm_hexserial)
	ori	a2, ra, 0
	ori	a1, a0, 0
	li.d	a3, 8
1:
	rotri.w a0, a1, 28
	or	a1, a0, zero
	andi	a0, a0, 0xf

	la	a4, hexchar
	sub.d	a4, a4, s0

	add.d	a4, a4, a0
	ld.bu	a0, a4, 0

	bl	mm_tgt_putchar

	addi.d	a3, a3, -1
	bnez	a3, 1b

	ori	ra, a2, 0
	jirl	zero, ra, 0
END(mm_hexserial)

LEAF(mm_tgt_getchar)
	li.d	a4, COM1_BASE_ADDR
1:
	ld.bu	a5, a4, NSREG(NS16550_LSR)
	andi	a5, a5, LSR_RXRDY
	beqz	a5, 1b
	nop
	ld.b	a4, a4, NSREG(NS16550_DATA)
	jirl	zero, ra, 0
	nop
END(mm_tgt_getchar)

#ifndef HAVE_TARGET_GETCHAR
#ifndef BONITOEL_CPCI
LEAF(tgt_testchar_old)
#ifdef HAVE_NB_SERIAL
#ifdef USE_LPC_UART
	la	a4, COM3_BASE_ADDR
#else
    la  a4, GS3_UART_BASE
#endif
#else
	li.d	a4, COM1_BASE_ADDR
#endif
1:
	ld.bu	a5, a4, NSREG(NS16550_LSR)
	andi	a4,a5, LSR_RXRDY
	jirl	zero, ra, 0
	nop
END(tgt_testchar_old)

#else
LEAF(tgt_testchar)
#ifdef HAVE_NB_SERIAL
#ifdef USE_LPC_UART
	la	a4, COM3_BASE_ADDR
#else
    la  a4, GS3_UART_BASE
#endif
#else
	la	a4, COM1_BASE_ADDR
	and a5,k1,1
	bnez a5,1f
	nop
	la	a4, COM2_BASE_ADDR
	and a5,k1,2
	bnez a5,1f
	nop
	li.w a4,0
    jirl    zero, ra, 0
	nop
#endif
1:
	ld.bu	a5, a4, NSREG(NS16550_LSR)
	and	a4,a5, LSR_RXRDY
	jirl	zero, ra, 0
	nop
END(tgt_testchar)

LEAF(tgt_getchar)
#ifdef HAVE_NB_SERIAL
#ifdef USE_LPC_UART
	la	a4, COM3_BASE_ADDR
#else
    la  a4, GS3_UART_BASE
#endif
#else
	la	a4, COM1_BASE_ADDR
	and a5,k1,1
	bnez a5,1f
	nop
	la	a4, COM2_BASE_ADDR
	and a5,k1,2
	bnez a5,1f
	nop
	li.w a4,-1
    jirl    zero, ra, 0
	nop
#endif
1:
	ld.bu	a5, a4, NSREG(NS16550_LSR)
	and	a5, LSR_RXRDY
	beqz	a5, 1b
	nop
	ld.b	a4, a4, NSREG(NS16550_DATA)
	jirl	zero, ra, 0
	nop
END(tgt_getchar)

#endif
#endif
22:

