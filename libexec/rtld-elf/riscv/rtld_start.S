/*-
 * Copyright (c) 2015-2018 Ruslan Bukin <br@bsdpad.com>
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the CTSRD Project, with support from the UK Higher
 * Education Innovation Fund (HEIF).
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

#ifdef __CHERI_PURE_CAPABILITY__
#include <machine/riscvreg.h>
#endif

#ifdef __riscv_float_abi_double
#define	FLT_SIZE	8
#else
#define	FLT_SIZE	0
#endif

/*
 * Pure-capability:
 *
 * void
 * _rtld_relocate_nonplt_self(Elf_Dyn *dynp, Elf_Auxinfo *aux)
 *
 * func_ptr_type
 * _rtld(Elf_Auxinfo *aux, func_ptr_type *exit_proc, Obj_Entry **objp)
 */

/*
 * Plain:
 *
 * func_ptr_type
 * _rtld(Elf_Addr *sp, func_ptr_type *exit_proc, Obj_Entry **objp)
 */

ENTRY(.rtld_start)
	.cfi_undefined PTR(ra)	/* Do not attempt to unwind any further. */

	MV_PTR	PTR(s0), PTR(a0)		/* Put aux in a callee-saved register */
	MV_PTR	PTR(s1), PTR(sp)		/* And the stack pointer */

	addi	PTR(sp), PTR(sp), -(PTR_WIDTH * 2)	/* Make room for obj_main & exit_proc */

#ifdef __CHERI_PURE_CAPABILITY__
	llc	PTR(a0), _DYNAMIC		/* dynp */
	MV_PTR	PTR(a1), PTR(s0)		/* aux */
	jal	_rtld_relocate_nonplt_self	/* Relocate ourselves early, including __cap_relocs */

#if __CHERI_CAPABILITY_TABLE__ != 3
	/* TODO: CGP for PLT and FNDESC ABIs */
#error "Only the PC-relative ABI is currently supported"
#endif

	MV_PTR	PTR(a0), PTR(s0)		/* Restore aux */
	csetbounds	PTR(a1), PTR(sp), CAP_WIDTH	/* exit_proc */
	addi	PTR(a2), PTR(sp), CAP_WIDTH
	csetbounds	PTR(a2), PTR(a2), CAP_WIDTH	/* obj_main */
	jal	_rtld				/* Call the loader */
	MV_PTR	PTR(t0), PTR(a0)		/* Backup the entry point */

	L_PTR	PTR(a1), (CAP_WIDTH * 0)(PTR(sp))	/* Load cleanup */
	L_PTR	PTR(a2), (CAP_WIDTH * 1)(PTR(sp))	/* Load obj_main */
	MV_PTR	PTR(a0), PTR(s0)		/* Restore aux */
	MV_PTR	PTR(sp), PTR(s1)		/* Restore the stack pointer */
	jr	PTR(t0)				/* Jump to the entry point */
#else /* defined(__CHERI_PURE_CAPABILITY__) */
	mv	a1, sp		/* exit_proc */
	addi	a2, a1, 8	/* obj_main */
	jal	_rtld		/* Call the loader */
	mv	t0, a0		/* Backup the entry point */

	ld	a2, 0(sp)	/* Load cleanup */
	ld	a1, 8(sp)	/* Load obj_main */
	mv	a0, s0		/* Restore ps_strings */
	mv	sp, s1		/* Restore the stack pointer */
	jr	t0		/* Jump to the entry point */
#endif /* defined(__CHERI_PURE_CAPABILITY__) */
END(.rtld_start)

/*
 * (c)t0 = plt pointer
 * t1 = reloc offset
 */
ENTRY(_rtld_bind_start)
	/* Save the arguments and (c)ra */
	/*
	 * We require 8 GP(C)Rs, 1 pointer and 8 FPRs, but the stack must be
	 * aligned to 16-bytes.
	 */
#define	FLT_OFFSET	(8 * CAP_WIDTH + 1 * PTR_WIDTH)
#define	FRAME_SIZE	(((FLT_OFFSET + 8 * FLT_SIZE) + 15) & ~15)

	addi		PTR(sp), PTR(sp), -FRAME_SIZE
	S_CAP	CAP(a0), (CAP_WIDTH * 0)(PTR(sp))
	S_CAP	CAP(a1), (CAP_WIDTH * 1)(PTR(sp))
	S_CAP	CAP(a2), (CAP_WIDTH * 2)(PTR(sp))
	S_CAP	CAP(a3), (CAP_WIDTH * 3)(PTR(sp))
	S_CAP	CAP(a4), (CAP_WIDTH * 4)(PTR(sp))
	S_CAP	CAP(a5), (CAP_WIDTH * 5)(PTR(sp))
	S_CAP	CAP(a6), (CAP_WIDTH * 6)(PTR(sp))
	S_CAP	CAP(a7), (CAP_WIDTH * 7)(PTR(sp))
	S_PTR	PTR(ra), (CAP_WIDTH * 8)(PTR(sp))

#if FLT_SIZE != 0
	/* Save any floating-point arguments */
	fsd	fa0, (FLT_OFFSET + FLT_SIZE * 0)(PTR(sp))
	fsd	fa1, (FLT_OFFSET + FLT_SIZE * 1)(PTR(sp))
	fsd	fa2, (FLT_OFFSET + FLT_SIZE * 2)(PTR(sp))
	fsd	fa3, (FLT_OFFSET + FLT_SIZE * 3)(PTR(sp))
	fsd	fa4, (FLT_OFFSET + FLT_SIZE * 4)(PTR(sp))
	fsd	fa5, (FLT_OFFSET + FLT_SIZE * 5)(PTR(sp))
	fsd	fa6, (FLT_OFFSET + FLT_SIZE * 6)(PTR(sp))
	fsd	fa7, (FLT_OFFSET + FLT_SIZE * 7)(PTR(sp))
#endif

	/* Reloc offset is 3x or 1.5x of the .got.plt offset */
#ifdef __CHERI_PURE_CAPABILITY__
	srli	a1, t1, 1	/* Divide items by 2 */
#else
	slli	a1, t1, 1	/* Mult items by 2 */
#endif
	add	a1, a1, t1	/* Plus item */

	/* Load plt */
	MV_PTR	PTR(a0), PTR(t0)

	/* Call into rtld */
	jal	_rtld_bind

	/* Backup the address to branch to */
	MV_PTR	PTR(t0), PTR(a0)

	/* Restore the arguments and ra */
	L_CAP	CAP(a0), (CAP_WIDTH * 0)(PTR(sp))
	L_CAP	CAP(a1), (CAP_WIDTH * 1)(PTR(sp))
	L_CAP	CAP(a2), (CAP_WIDTH * 2)(PTR(sp))
	L_CAP	CAP(a3), (CAP_WIDTH * 3)(PTR(sp))
	L_CAP	CAP(a4), (CAP_WIDTH * 4)(PTR(sp))
	L_CAP	CAP(a5), (CAP_WIDTH * 5)(PTR(sp))
	L_CAP	CAP(a6), (CAP_WIDTH * 6)(PTR(sp))
	L_CAP	CAP(a7), (CAP_WIDTH * 7)(PTR(sp))
	L_PTR	PTR(ra), (CAP_WIDTH * 8)(PTR(sp))

#if FLT_SIZE != 0
	/* Restore floating-point arguments */
	fld	fa0, (FLT_OFFSET + FLT_SIZE * 0)(PTR(sp))
	fld	fa1, (FLT_OFFSET + FLT_SIZE * 1)(PTR(sp))
	fld	fa2, (FLT_OFFSET + FLT_SIZE * 2)(PTR(sp))
	fld	fa3, (FLT_OFFSET + FLT_SIZE * 3)(PTR(sp))
	fld	fa4, (FLT_OFFSET + FLT_SIZE * 4)(PTR(sp))
	fld	fa5, (FLT_OFFSET + FLT_SIZE * 5)(PTR(sp))
	fld	fa6, (FLT_OFFSET + FLT_SIZE * 6)(PTR(sp))
	fld	fa7, (FLT_OFFSET + FLT_SIZE * 7)(PTR(sp))
#endif
	addi	PTR(sp), PTR(sp), FRAME_SIZE

	/* Call into the correct function */
	jr	PTR(t0)
END(_rtld_bind_start)
