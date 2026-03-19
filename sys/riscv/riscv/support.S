/*-
 * Copyright (c) 2015-2020 Ruslan Bukin <br@bsdpad.com>
 * All rights reserved.
 *
 * Portions of this software were developed by SRI International and the
 * University of Cambridge Computer Laboratory under DARPA/AFRL contract
 * FA8750-10-C-0237 ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * Portions of this software were developed by the University of Cambridge
 * Computer Laboratory as part of the CTSRD Project, with support from the
 * UK Higher Education Innovation Fund (HEIF).
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <machine/asm.h>
#include <machine/setjmp.h>
#include <machine/riscvreg.h>

#include "assym.inc"

/*
 * Hybrid kernels use .cap loads and stores whereas purecap kernels use
 * capmode loads and stores.
 */
#ifdef __CHERI_PURE_CAPABILITY__
#define	CLR_W		clr.w
#define	CLR_D		clr.d
#define	CLBU		clbu
#define	CLHU		clhu
#define	CLW		clw
#define	CLD		cld
#define	CLC		clc
#define	CSB		csb
#define	CSH		csh
#define	CSW		csw
#define	CSD		csd
#define	CSC		csc
#else
#if __has_feature(capabilities)
#define	_CAP_INSTR(x)	x##.cap
#define	CLC		lc.cap
#define	CSC		sc.cap
#else
#define	_CAP_INSTR(x)	x
#endif
#define	CLR_W		_CAP_INSTR(lr.w)
#define	CLR_D		_CAP_INSTR(lr.d)
#define	CLBU		_CAP_INSTR(lbu)
#define	CLHU		_CAP_INSTR(lhu)
#define	CLW		_CAP_INSTR(lw)
#define	CLD		_CAP_INSTR(ld)
#define	CSB		_CAP_INSTR(sb)
#define	CSH		_CAP_INSTR(sh)
#define	CSW		_CAP_INSTR(sw)
#define	CSD		_CAP_INSTR(sd)
#endif

/*
 * One of the fu* or su* functions failed, return -1.
 */
ENTRY(fsu_fault)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a1))	/* Reset the handler function */
	EXIT_USER_ACCESS(a1)
fsu_fault_nopcb:
	li	a0, -1
	ret
END(fsu_fault)

/*
 * int casueword32(volatile uint32_t * __capability, uint32_t, uint32_t *, uint32_t)
 */
ENTRY(casueword32)
	li	a4, (VM_MAXUSER_ADDRESS-3)
	bgeu	a0, a4, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a4))	/* And set it */
	ENTER_USER_ACCESS(a4)

	CLR_W	a4, 0(CAP(a0))		/* Load-exclusive the data */
	bne	a4, a1, 1f		/* If not equal then exit */
#if defined(__CHERI_PURE_CAPABILITY__) || !__has_feature(capabilities)
	sc.w	a5, a3, 0(CAP(a0))	/* Store the new data */
#else
	move	a5, a3
	sc.w.cap a5, 0(CAP(a0))	/* Store the new data */
#endif
	beqz	a5, 2f			/* Success */

1:	li	a5, 1			/* Normalize failure result */
2:
	EXIT_USER_ACCESS(a6)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a6))	/* Reset the fault handler */
	sw	a4, 0(PTR(a2))		/* Store the read data */
	mv	a0, a5			/* Success indicator */
	ret				/* Return */
END(casueword32)

/*
 * int casueword(volatile u_long * __capability, u_long, u_long *, u_long)
 */
ENTRY(casueword)
	li	a4, (VM_MAXUSER_ADDRESS-7)
	bgeu	a0, a4, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a4))	/* And set it */
	ENTER_USER_ACCESS(a4)

	CLR_D	a4, 0(CAP(a0))		/* Load-exclusive the data */
	bne	a4, a1, 1f		/* If not equal then exit */
#if defined(__CHERI_PURE_CAPABILITY__) || !__has_feature(capabilities)
	sc.d	a5, a3, 0(CAP(a0))	/* Store the new data */
#else
	move	a5, a3
	sc.d.cap a5, 0(CAP(a0))		/* Store the new data */
#endif
	beqz	a5, 2f			/* Success */
1:	li	a5, 1			/* Normalize failure result */
2:
	EXIT_USER_ACCESS(a6)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a6))	/* Reset the fault handler */
	sd	a4, 0(PTR(a2))		/* Store the read data */
	mv	a0, a5			/* Success indicator */
	ret				/* Return */
END(casueword)

/*
 * int fubyte(volatile const void * __capability)
 */
ENTRY(fubyte)
	li	a1, VM_MAXUSER_ADDRESS
	bgeu	a0, a1, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a1))	/* And set it */
	ENTER_USER_ACCESS(a1)
	CLBU	a0, 0(CAP(a0))		/* Try loading the data */
	EXIT_USER_ACCESS(a1)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a1))	/* Reset the fault handler */
	ret				/* Return */
END(fubyte)

/*
 * int fuword16(volatile const void * __capability)
 */
ENTRY(fuword16)
	li	a1, (VM_MAXUSER_ADDRESS-1)
	bgeu	a0, a1, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a1))	/* And set it */
	ENTER_USER_ACCESS(a1)
	CLHU	a0, 0(CAP(a0))		/* Try loading the data */
	EXIT_USER_ACCESS(a1)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a1))	/* Reset the fault handler */
	ret				/* Return */
END(fuword16)

/*
 * int32_t fueword32(volatile const void * __capability, int32_t *)
 */
ENTRY(fueword32)
	li	a2, (VM_MAXUSER_ADDRESS-3)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CLW	a0, 0(CAP(a0))		/* Try loading the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	sw	a0, 0(PTR(a1))		/* Save the data in kernel space */
	li	a0, 0			/* Success */
	ret				/* Return */
END(fueword32)

/*
 * long fueword(volatile const void __capability *, int64_t *)
 * int64_t fueword64(volatile const void __capability *, int64_t *)
 */
ENTRY(fueword)
EENTRY(fueword64)
	li	a2, (VM_MAXUSER_ADDRESS-7)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CLD	a0, 0(CAP(a0))		/* Try loading the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	sd	a0, 0(PTR(a1))		/* Save the data in kernel space */
	li	a0, 0			/* Success */
	ret				/* Return */
EEND(fueword64)
END(fueword)

#if __has_feature(capabilities)
/*
 * int fuecap(volatile const void __capability *, intcap_t *)
 */
ENTRY(fuecap)
	li	a2, (VM_MAXUSER_ADDRESS-7)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CLC	CAP(a0), 0(CAP(a0))	/* Try loading the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	sc	CAP(a0), 0(PTR(a1))		/* Save the data in kernel space */
	li	a0, 0			/* Success */
	ret				/* Return */
END(fuecap)
#endif

/*
 * int subyte(volatile void * __capability, int)
 */
ENTRY(subyte)
	li	a2, VM_MAXUSER_ADDRESS
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CSB	a1, 0(CAP(a0))		/* Try storing the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	li	a0, 0			/* Success */
	ret				/* Return */
END(subyte)

/*
 * int suword16(volatile void * __capability, int)
 */
ENTRY(suword16)
	li	a2, (VM_MAXUSER_ADDRESS-1)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CSH	a1, 0(CAP(a0))		/* Try storing the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	li	a0, 0			/* Success */
	ret				/* Return */
END(suword16)

/*
 * int suword32(volatile void * __capability, int)
 */
ENTRY(suword32)
	li	a2, (VM_MAXUSER_ADDRESS-3)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CSW	a1, 0(CAP(a0))		/* Try storing the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	li	a0, 0			/* Success */
	ret				/* Return */
END(suword32)

/*
 * int suword(volatile void * __capability, long)
 */
ENTRY(suword)
EENTRY(suword64)
	li	a2, (VM_MAXUSER_ADDRESS-7)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CSD	a1, 0(CAP(a0))		/* Try storing the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	li	a0, 0			/* Success */
	ret				/* Return */
EEND(suword64)
END(suword)

#if __has_feature(capabilities)
/*
 * int sucap(volatile void * __capability, intcap_t)
 */
ENTRY(sucap)
	li	a2, (VM_MAXUSER_ADDRESS-3)
	bgeu	a0, a2, fsu_fault_nopcb
	LA_PTR	PTR(a6), fsu_fault	/* Load the fault handler */
	SET_FAULT_HANDLER(PTR(a6), PTR(a2))	/* And set it */
	ENTER_USER_ACCESS(a2)
	CSC	CAP(a1), 0(CAP(a0))	/* Try storing the data */
	EXIT_USER_ACCESS(a2)
	SET_FAULT_HANDLER(PTR_NULL, PTR(a2))	/* Reset the fault handler */
	li	a0, 0			/* Success */
	ret				/* Return */
END(sucap)
#endif

ENTRY(setjmp)
	/* Store the stack pointer */
	S_PTR	PTR(sp), 0(PTR(a0))
	addi	PTR(a0), PTR(a0), PTR_WIDTH

	/* Store the general purpose registers and ra */
	S_PTR	PTR(s0), (0 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s1), (1 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s2), (2 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s3), (3 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s4), (4 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s5), (5 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s6), (6 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s7), (7 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s8), (8 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s9), (9 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s10), (10 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(s11), (11 * PTR_WIDTH)(PTR(a0))
	S_PTR	PTR(ra), (12 * PTR_WIDTH)(PTR(a0))

	/* Return value */
	li	a0, 0
	ret
END(setjmp)

ENTRY(longjmp)
	/* Restore the stack pointer */
	L_PTR	PTR(sp), 0(PTR(a0))
	addi	PTR(a0), PTR(a0), PTR_WIDTH

	/* Restore the general purpose registers and ra */
	L_PTR	PTR(s0), (0 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s1), (1 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s2), (2 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s3), (3 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s4), (4 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s5), (5 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s6), (6 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s7), (7 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s8), (8 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s9), (9 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s10), (10 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(s11), (11 * PTR_WIDTH)(PTR(a0))
	L_PTR	PTR(ra), (12 * PTR_WIDTH)(PTR(a0))

	/* Load the return value */
	mv	a0, a1
	ret
END(longjmp)

/*
 * CHERI CHANGES START
 * {
 *   "updated": 20230509,
 *   "target_type": "kernel",
 *   "changes_purecap": [
 *     "support"
 *   ]
 * }
 * CHERI CHANGES END
 */
