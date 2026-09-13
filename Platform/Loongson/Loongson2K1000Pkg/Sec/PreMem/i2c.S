/*************************
 * ls2k
*************************/


#define	i2c_wait_tip				\
		li.d	a4, LS2K1000_I2C0_SR_REG;	\
1:						\
		ld.b	a5, a4, 0x0		\
		andi	a5, a5, SR_TIP;		\
		bnez	a5, 1b;			\
		nop

#define	i2c_wait_ack				\
		li.d	a4, LS2K1000_I2C0_SR_REG;	\
1:						\
		ld.b	a5, a4, 0x0		\
		andi    a5, a5, SR_NOACK;	\
		bnez	a5, 1b;			\
		nop
LEAF(i2cinit)
		//LPB clock_a,SCL clock_s,prescale = clock_a / (4 * clock_s);
		li.d	  a5, 0
		li.d	  a4, LS2K1000_I2C0_CTR_REG
		st.b	  a5, a4, 0x0

		li.d	  a5, 0x71
		li.d	  a4, LS2K1000_I2C0_PRER_LO_REG
		st.b	  a5, a4, 0x0

		li.d	  a5, 0x2
		li.d	  a4, LS2K1000_I2C0_PRER_HI_REG
		st.b	  a5, a4, 0x0

		li.d	  a5, 0x80
		li.d	  a4, LS2K1000_I2C0_CTR_REG
		st.b	  a5, a4, 0x0

		jr      ra
		nop
END(i2cinit)

LEAF(i2cread)
/*
 * use register:
 *	a4, a5
 *	a0, a1
 *	input: a0,a1
 *	   a0: device ID
 *	   a1: register offset
 *	   a4: return value
 *
 */

/*i2c_send_b*/
	/* load device address */
	andi	a5, a0, 0xfe
	li.d	a4, LS2K1000_I2C0_TXR_REG
	st.b	a5, a4, 0x0

	/* send start frame */
	li.d	a5, CR_START | CR_WRITE
	li.d	a4, LS2K1000_I2C0_CR_REG
	st.b	a5, a4, 0x0

	/* waite send finished */
//	i2c_wait_tip
	li.d	a4, LS2K1000_I2C0_SR_REG
1:
	ld.b	a5, a4, 0x0
	andi	a5, a5, SR_TIP
	bnez	a5, 1b
	nop

	/* load data to be send */
	or	a5, a1, zero
	li.d	a4, LS2K1000_I2C0_TXR_REG
	st.b	a5, a4, 0x0

	/* send data frame */
	li.d	a5, CR_WRITE
	li.d	a4, LS2K1000_I2C0_CR_REG
	st.b	a5, a4, 0x0

	/* waite send finished */
//	i2c_wait_tip
	li.d	a4, LS2K1000_I2C0_SR_REG
1:
	ld.b	a5, a4, 0x0
	andi	a5, a5, SR_TIP
	bnez	a5, 1b
	nop

/* i2c_read_b */
	/* load device address */
	ori	a5, a0, 0x1
	li.d	a4, LS2K1000_I2C0_TXR_REG
	st.b	a5, a4, 0x0

	/* send start frame */
	li.d	a5, CR_START | CR_WRITE
	li.d	a4, LS2K1000_I2C0_CR_REG
	st.b	a5, a4, 0x0

	/* waite send finished */
//	i2c_wait_tip
	li.d	a4, LS2K1000_I2C0_SR_REG
1:
	ld.b	a5, a4, 0x0
	andi	a5, a5, SR_TIP
	bnez	a5, 1b
	nop

	/* receive data to fifo */
	li.d	a5, CR_READ | CR_ACK
	li.d	a4, LS2K1000_I2C0_CR_REG
	st.b	a5, a4, 0x0

//	i2c_wait_tip
	li.d	a4, LS2K1000_I2C0_SR_REG
1:
	ld.b	a5, a4, 0x0
	andi	a5, a5, SR_TIP
	bnez	a5, 1b
	nop

	/* read data from fifo */
	li.d	a4, LS2K1000_I2C0_RXR_REG
	ld.b	a1, a4, 0x0

/* i2c_stop */
	/* free i2c bus */
	li.d	a4, LS2K1000_I2C0_CR_REG
	li.d	a5, CR_STOP
	st.b	a5, a4, 0x0
1:
	li.d	a4, LS2K1000_I2C0_SR_REG
	ld.b	a5, a4, 0x0
	andi	a5, a5, SR_BUSY
	bnez	a5, 1b
	nop

	or	a4, a1, zero

	jr	ra
	nop
END(i2cread)


#if 0

LEAF(i2c_ls2k_write)
//a0: i2caddr, a1: chip, a2: reg, a3: val
#define plo  a0 , 0
#define phi  a0 , 1
#define ctr  a0 , 2
#define cr  a0 , 4
#define dr  a0 , 3
#define sbi(v, reg) li.d a4, v; st.b a4, reg;
#define waitz(v, reg) 1: ld.bu a4, reg; andi a4, a4, v; bnez a4, 1b; nop;
#define check_nak(reg) ld.bu reg, cr;andi reg, reg,0x80;bnez reg, 2f;nop;

 st.b a1, dr;
 srli.d a1, a1, 8
 sbi(0x90, cr);
 waitz(2, cr);
 check_nak(a5);
 st.b a1, dr;
 srli.d a1, a1, 8
 sbi(0x10, cr);
 waitz(2, cr);
 check_nak(a5);
 st.b a1, dr;
 sbi(0x10, cr);
 waitz(2, cr);
 check_nak(a5);
2:
 sbi(0x40, cr);
 waitz(0x40, cr);
 jr ra
 nop
END(i2c_ls2k_write)

LEAF(i2c_ls2k_read)
//a0: i2caddr, a1: chip, a2: reg, a3: val
 ori a4, a1, 1
 slli.d a4, a4, 16
 or a1, a1, a4
 st.b a1, dr;
 srli.d a1, a1, 8
 sbi(0x90, cr);
 waitz(2, cr);
 check_nak(a5);
 st.b a1, dr;
 srli.d a1, a1, 8
 sbi(0x10, cr);
 waitz(2, cr);
 check_nak(a5);
 st.b a1, dr;
 sbi(0x90, cr);
 waitz(2, cr);
 sbi(0x28, cr);
 waitz(2, cr);
 ld.bu a1, dr
2:
 sbi(0x40, cr);
 waitz(0x40, cr);
 or a4, a1, zero
 jr ra
 nop
END(i2c_ls2k_read)

LEAF(i2c_ls2k_init)
sbi(0, plo)
sbi(0x64, plo)
sbi(2, phi)
sbi(0x80, ctr)
jr ra
nop
END(i2c_ls2k_init)

#endif
