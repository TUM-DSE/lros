// SPDX-License-Identifier: Apache-2.0

#define _POSIX_C_SOURCE 200809L

#include "vaccel.h"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define noop_debug(fmt, ...) vaccel_debug("[noop] " fmt, ##__VA_ARGS__)
#define noop_error(fmt, ...) vaccel_error("[noop] " fmt, ##__VA_ARGS__)

void saxpy_internal(int n, float a, float *x, float *y, float *z);

static int saxpy_sgemm(struct vaccel_session *sess, long long int m,
		      long long int n, long long int k, float alpha, float *a,
		      long long int lda, float *b, long long int ldb,
		      float beta, float *c, long long int ldc)
{

    if (m!=n || n!=k) return VACCEL_EINVAL;
    
    saxpy_internal(n*n, alpha, a, b, c);

	return VACCEL_OK;
}



struct vaccel_op ops[] = {
	VACCEL_OP_INIT(ops[0], VACCEL_OP_BLAS_SGEMM, saxpy_sgemm),
};

static int init(void)
{
	return vaccel_plugin_register_ops(ops, sizeof(ops) / sizeof(ops[0]));
}

static int fini(void)
{
	return VACCEL_OK;
}

VACCEL_PLUGIN(.name = "saxpy", .version = VACCEL_VERSION,
	      .vaccel_version = VACCEL_VERSION, .type = VACCEL_PLUGIN_GPU,
	      .init = init, .fini = fini)
