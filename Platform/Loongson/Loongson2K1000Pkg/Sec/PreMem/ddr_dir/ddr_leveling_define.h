#ifdef LEVELING_CHECK_ALL_BITS
#define LEVELING_CHECK_BITS 0xff
#else
#define LEVELING_CHECK_BITS 0x1
#endif
#define GET_NUMBER_OF_SLICES	\
    li.w      t0, 0x8;\
    ld.b	    a0, t8, 0x1f2;\
	li.d    tp, 0x3;  bne	a0, tp, 1f;\
    nop;\
    li.w      t0, 0x2;\
    b       933f;\
    nop;\
1:;\
	li.d    tp, 0x5;  bne	a0, tp, 934f;\
    nop;\
    li.w      t0, 0x4;\
    b       933f;\
    nop;\
934:;\
    li.d     t1, 0x250;\
    or      t1, t1, t8;\
    ld.b      a0, t1, 0x2;\
    li.d     t1, 0x1;\
    and     a0, a0, t1;\
    bne     a0, t1, 933f ;\
    nop;\
    addi.d   t0, t0, 0x1;\
933:;

#define PRINT_THE_MC_PARAM \
    li.d     t4, DDR_PARAM_NUM;\
    GET_NODE_ID_a0;\
    li.d     t5, PHYS_TO_UNCACHED(0x0ff00000);\
    or      t5, t5, a0;\
1:;\
    ld.d      t6, t5, 0x0;\
    or    a0, t5, zero;\
    andi     a0, a0, 0xfff;\
    bl     mm_hexserial;\
    nop;\
    PRINTSTR(":  ");\
    srli.d    a0, t6, 32;\
    bl     mm_hexserial;\
    nop;\
    or    a0, t6, zero;\
    bl     mm_hexserial;\
    nop;\
    PRINTSTR("\r\n");\
    addi.d  t4, t4, -1;\
    addi.d  t5, t5, 8;\
    bnez    t4, 1b;\
    nop;

#define WRDQS_ADJUST_LOOP \
933:;\
    li.d  tp, 0x1;  sub.d    t0, t0, tp;\
    beqz     t0, 936f;\
    nop;\
    addi.d   t1, t1, 0x20;\
    ld.b      a0, t1, OFFSET_DLL_WRDQS;\
    bgeu    a0, a2, 933b;\
    nop;\
    bleu    a0, a3, 933b;\
    nop;\
    li.d     t4, 0x8;\
    and     t4, t4, a0;\
    beqz    t4, 934f;\
    nop;\
    st.b      a3, t1, OFFSET_DLL_WRDQS;\
    b       935f;\
    nop;\
934:;\
    st.b      a2, t1, OFFSET_DLL_WRDQS;\
935:;\
	ld.b		a0, t1, OFFSET_DLL_WRDQS;\
	li.d    tp, WRDQS_LTHF_STD;  blt		a0, tp, 937f;\
	nop;\
	li.w		t4, 0x0;\
	st.b		t4, t1, OFFSET_WRDQS_LTHF;\
	b		938f;\
	nop;\
937:;\
	li.w		t4, 0x1;\
	st.b		t4, t1, OFFSET_WRDQS_LTHF;\
938:;\
	li.d  tp, 0x20;  sub.d	a0, a0, tp;\
	li.d		t4, 0x7f;\
	and		a0, a0, t4;\
	st.b		a0, t1, OFFSET_DLL_WRDQ;\
	li.d    tp, WRDQ_LTHF_STD;  blt		a0, tp, 937f;\
	nop;\
	li.w		t4, 0x0;\
	st.b		t4, t1, OFFSET_WRDQ_LTHF;\
	b		938f;\
	nop;\
937:;\
	li.w		t4, 0x1;\
	st.b		t4, t1, OFFSET_WRDQ_LTHF;\
938:;\
    b       933b;\
    nop;\
936:;\

#define RDOE_SUB_TRDDATA_ADD	\
	li.d    tp, 0x4;  bne		a0, tp, 934f;\
	nop;\
    li.w      a1, 0x8;\
    li.d     t4, 0x250;\
    or      t4, t4, t8;\
    ld.b      a0, t4, 0x2;\
    li.d     t4, 0x1;\
    and     a0, a0, t4;\
    bne     a0, t4, 932f ;\
    nop;\
    addi.d   a1, a1, 0x1;\
932: ;\
	li.d		t4, 0x28;\
	or		t4, t4, t8;\
933: ;\
	ld.b		a0, t4, 0x7;\
	li.d  tp, 0x1;  sub.d	a0, a0, tp;\
	st.b		a0, t4, 0x7;\
	ld.b		a0, t4, 0x6;\
	li.d  tp, 0x1;  sub.d	a0, a0, tp;\
	st.b		a0, t4, 0x6;\
	addi.d	t4, t4, 0x20;\
	li.d  tp, 0x1;  sub.d	a1, a1, tp;\
	bnez	a1, 933b;\
	nop;\
	li.d		t4, 0x1c0;\
	or		t4, t4, t8;\
	ld.b		a0, t4, 0x0;\
	addi.d	a0, a0, 0x1;\
	st.b		a0, t4, 0x0;\
934: ;
#define	RDOE_ADD_TRDDATA_SUB		\
	li.d    tp, 0x0;  bne		a0, tp, 934f;\
	nop ;\
    li.w      a1, 0x8;\
    li.d     t4, 0x250;\
    or      t4, t4, t8;\
    ld.b      a0, t4, 0x2;\
    li.d     t4, 0x1;\
    and     a0, a0, t4;\
    bne     a0, t4, 932f ;\
    nop;\
    addi.d   a1, a1, 0x1;\
932: ;\
	li.d		t4, 0x28;\
	or		t4, t4, t8;\
933: ;\
	ld.b		a0, t4, 0x7;\
	addi.d	a0, a0, 0x1;\
	st.b		a0, t4, 0x7;\
	ld.b		a0, t4, 0x6;\
	addi.d	a0, a0, 0x1;\
	st.b		a0, t4, 0x6;\
	addi.d	t4, t4, 0x20;\
	li.d  tp, 0x1;  sub.d	a1, a1, tp;\
	bnez	a1, 933b;\
	nop;\
	li.d		t4, 0x1c0;\
	or		t4, t4, t8;\
	ld.b		a0, t4, 0x0;\
	li.d  tp, 0x1;  sub.d	a0, a0, tp;\
	st.b		a0, t4, 0x0;\
934: ;

