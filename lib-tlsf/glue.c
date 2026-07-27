/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Authors: Hugo Lefeuvre <hugo.lefeuvre@neclab.eu>
 *
 * Copyright (c) 2020, NEC Europe Ltd., NEC Corporation. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <uk/tlsf.h>
#include <uk/alloc_impl.h>
#include <uk/spinlock.h>
#include <uk/arch/limits.h>
#include <uk/essentials.h>
#include <errno.h>
#include <stdint.h> /* uintptr_t */
#include <tlsf.h>

/* TLSF 2.4.6 indexes free blocks with MAX_FLI = 30, so neither a memory
 * area nor an allocation may reach 1 GiB. The heap however can be many GiB,
 * arriving in a single uk_alloc_addmem() call (see heap_init() in ukboot).
 * It is therefore added as chunks well below the limit, separated by one
 * untouched guard page so add_new_area() cannot merge physically adjacent
 * chunks back into an oversized free block. The guard pages cost no
 * physical memory: the heap VMA is demand-paged and they are never touched.
 */
#define UK_TLSF_AREA_MAX	(256UL << 20)

/* Reject requests TLSF cannot represent. Allocations >= 16 MiB are
 * expected to be diverted to anonymous demand-paged mappings by
 * uk_malloc()/uk_posix_memalign() before reaching the allocator; this
 * guard turns any request slipping through (e.g. large uk_memalign())
 * into ENOMEM instead of index corruption.
 */
#define UK_TLSF_MAX_ALLOC	(128UL << 20)

/* Unlike the ifpages malloc, whose bookkeeping is decentralized and hence
 * reentrant, TLSF keeps central free lists: allocations from interrupt
 * context (or, with SMP, other cores) must be excluded. On the current
 * uniprocessor build this reduces to IRQ save/restore.
 * Lock and pool accounting are global, which assumes a single TLSF
 * instance (the boot-time default allocator).
 */
static __spinlock tlsf_lock = UK_SPINLOCK_INITIALIZER();
static size_t tlsf_pool_total; /* bytes under TLSF management */

static void *tlsf_pool(struct uk_alloc *a)
{
	return (void *)((uintptr_t) a + sizeof(struct uk_alloc));
}

/* malloc interface */

static void *uk_tlsf_malloc(struct uk_alloc *a, size_t size)
{
	unsigned long flags;
	void *ptr;

	if (unlikely(size > UK_TLSF_MAX_ALLOC))
		return NULL;

	uk_spin_lock_irqsave(&tlsf_lock, flags);
	ptr = tlsf_malloc(size, tlsf_pool(a));
	uk_spin_unlock_irqrestore(&tlsf_lock, flags);

	return ptr;
}

static void uk_tlsf_free(struct uk_alloc *a, void *ptr)
{
	unsigned long flags;

	uk_spin_lock_irqsave(&tlsf_lock, flags);
	tlsf_free(ptr, tlsf_pool(a));
	uk_spin_unlock_irqrestore(&tlsf_lock, flags);
}

static int uk_tlsf_addmem(struct uk_alloc *a, void *base, size_t len)
{
	uintptr_t pos = ALIGN_UP((uintptr_t)base, (uintptr_t)__PAGE_SIZE);
	size_t left = len - (pos - (uintptr_t)base);
	unsigned int areas = 0;
	unsigned long flags;
	size_t chunk, added = 0;

	while (left >= 2 * __PAGE_SIZE) {
		chunk = MIN(left, UK_TLSF_AREA_MAX);

		uk_spin_lock_irqsave(&tlsf_lock, flags);
		added += add_new_area((void *)pos, chunk, tlsf_pool(a));
		uk_spin_unlock_irqrestore(&tlsf_lock, flags);
		areas++;

		/* skip one guard page between areas */
		left -= MIN(left, chunk + __PAGE_SIZE);
		pos += chunk + __PAGE_SIZE;
	}

	if (unlikely(!areas))
		return -EINVAL;

	tlsf_pool_total += added;
	uk_pr_info("tlsf: added %" __PRIsz " B in %u area(s)\n", added, areas);

	return 0;
}

static __ssz uk_tlsf_availmem(struct uk_alloc *a)
{
	unsigned long flags;
	size_t used;

	uk_spin_lock_irqsave(&tlsf_lock, flags);
	used = get_used_size(tlsf_pool(a));
	uk_spin_unlock_irqrestore(&tlsf_lock, flags);

	return (__ssz)(tlsf_pool_total - used);
}

/* initialization */

struct uk_alloc *uk_tlsf_init(void *base, size_t len)
{
	struct uk_alloc *a;
	size_t res;

	/* enough space for allocator available? */
	if (sizeof(*a) > len) {
		uk_pr_err("Not enough space for allocator: %" __PRIsz
			  " B required but only %" __PRIuptr" B usable\n",
			  sizeof(*a), len);
		return NULL;
	}

	/* store allocator metadata on the heap, just before the memory pool */
	a = (struct uk_alloc *)base;
	uk_pr_info("Initialize tlsf allocator @ 0x%" __PRIuptr ", len %"
			__PRIsz"\n", (uintptr_t)a, len);

	res = init_memory_pool(len - sizeof(*a), base + sizeof(*a));
	if (res == (size_t)-1)
		return NULL;

	tlsf_pool_total = len - sizeof(*a);

	uk_alloc_init_malloc_ifmalloc(a, uk_tlsf_malloc, uk_tlsf_free,
		NULL /* maxalloc */, uk_tlsf_availmem, uk_tlsf_addmem);

	return a;
}