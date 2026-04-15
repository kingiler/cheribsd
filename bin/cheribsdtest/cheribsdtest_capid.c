/*-
 * Copyright (c) 2026 Alfredo Mazzinghi
 * All rights reserved.
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

/*
 * Test the revocation CapID feature and integration across allocator
 * and kernel.
 */

#include <sys/cdefs.h>

#ifndef __CHERI_PURE_CAPABILITY__
#error "This code requires the CHERI purecap ABI"
#endif

#include <sys/mman.h>
#include <sys/sysctl.h>
#include <sys/signal.h>

#include <cheri/cheric.h>
#include <machine/cheri.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "cheribsdtest.h"

static const char *
skip_need_capid(const struct cheri_test *ctp __unused)
{
	if (!feature_present("cheri_caprevoke_capid"))
		return ("Kernel does not support capid revocation");
	return (NULL);
}

CHERIBSDTEST(cheri_capid_mmap,
    "check that mmap returns a capability that permits CapID manipulation",
    .ct_check_skip = skip_need_capid)
{
	void *mem = CHERIBSDTEST_CHECK_SYSCALL(
		mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_ANON, -1, 0));
	CHERIBSDTEST_VERIFY2(cheri_capid_get(mem) == 0, "Invalid mmap() CapID");
	/*
	 * TODO add permission bit to gate capid manipulation?
	 * CHERIBSDTEST_VERIFY2((cheri_perm_get(mem) == CHERI_PERM_CAPID, "Missing CapID permission");
	 */
	CHERIBSDTEST_CHECK_SYSCALL(munmap(mem, 0x1000));

	cheribsdtest_success();
}

CHERIBSDTEST(cheri_capid_mmap_simple_fault,
    "check that accessing memory with mismatching CapID faults",
    .ct_check_skip = skip_need_capid,
    .ct_flags = CT_FLAG_SIGNAL | CT_FLAG_SI_CODE,
    .ct_signum = SIGPROT,
    .ct_si_code = PROT_CHERI_SEALED)
{
	char *mem = CHERIBSDTEST_CHECK_SYSCALL(
		mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_ANON, -1, 0));
	volatile char *cap;

	/* Prepare a 15 bytes chunk with the CapID in the 16th byte */
	const int mode = 0; /* shift = 2 */
	const int loc = 4;
	cap = cheri_capid_mode_set((volatile char *)mem, mode);
	cap = cheri_capid_loc_set(cap, loc);
	cap = cheri_setboundsexact(cap, 0xf);

	CHERIBSDTEST_VERIFY2(cheri_capid_get(cap) == 0, "Invalid capability CapID");
	CHERIBSDTEST_VERIFY2(cheri_capid_load(cap) == 0, "Invalid memory CapID");

	cap[1] = 'x';

	/*
	 * CapID store authorized by current CapID == 0
	 * TODO: strip PERM_CAPID permission afterwards.
	 */
	cheri_capid_store(cap, 3);
	cap = cheri_capid_set(cap, 2);

	cap[1] = 'y';

	cheribsdtest_failure_errx("capability read with stale CapID succeded");
}
