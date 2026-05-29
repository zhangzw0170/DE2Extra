/* crypto_viz.h — AES-128 and SHA-256 step-through visualization */
#ifndef CRYPTO_VIZ_H
#define CRYPTO_VIZ_H

#include "vga_hal.h"

/* Set args before launching via program_t interface */
void crypto_viz_set_args(const char *algo, const char *a1, const char *a2);

/* Run visualization standalone (LOCAL_BUILD SDL2 loop). */
int crypto_viz_run(const char *algo, const char *a1, const char *a2);

/* Program registration */
extern const program_t prog_cryptoviz;

#endif
