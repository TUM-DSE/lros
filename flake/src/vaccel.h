// SPDX-License-Identifier: Apache-2.0

#pragma once

#define VACCEL_VERSION "0.7.1"

// IWYU pragma: begin_exports

#include "vaccel/arg.h"
#include "vaccel/config.h"
#include "vaccel/core.h"
#include "vaccel/error.h"
#include "vaccel/file.h"
#include "vaccel/id.h"
#include "vaccel/log.h"
#include "vaccel/op.h"
#include "vaccel/ops/blas.h"
#include "vaccel/ops/exec.h"
#include "vaccel/ops/fpga.h"
#include "vaccel/ops/genop.h"
#include "vaccel/ops/image.h"
#include "vaccel/ops/minmax.h"
#include "vaccel/ops/noop.h"
#include "vaccel/ops/opencv.h"
#include "vaccel/ops/tf.h"
#include "vaccel/ops/tflite.h"
#include "vaccel/ops/torch.h"
#include "vaccel/plugin.h"
#include "vaccel/prof.h"
#include "vaccel/resource.h"
#include "vaccel/session.h"
#include "vaccel/utils/enum.h"
#include "vaccel/utils/path.h"
#include "vaccel/utils/str.h"

// IWYU pragma: end_exports

#ifdef __cplusplus
extern "C" {
#endif
int vaccel_ggml_backend_init(struct vaccel_session* sess);

int vaccel_ggml_backend_buft_alloc_buffer(struct vaccel_session *sess,
                                          size_t size, uint64_t *remote_ptr,
                                          uint64_t *remote_size,
                                          uint64_t *remote_base);
#ifdef __cplusplus
}
#endif
