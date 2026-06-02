/* pf_config.h -- pForth configuration for DE2-115/NEORV32
 *
 * These defines are also passed via -D flags in the makefile for the
 * NEORV32 cross-compile. Guard with #ifndef to avoid redefinition warnings.
 */

#ifndef PF_CONFIG_H
#define PF_CONFIG_H

/* We build the dictionary from C primitives at runtime (init mode).
 * Do NOT define PF_EMBEDDED — it sets PF_NO_INIT which prevents
 * dictionary building. Do NOT define PF_NO_SHELL — it removes
 * CreateDicEntry which pfBuildDictionary needs. */

#ifndef PF_NO_FILEIO
#define PF_NO_FILEIO
#endif
#ifndef PF_NO_CLIB
#define PF_NO_CLIB
#endif
#ifndef PF_NO_MALLOC
#define PF_NO_MALLOC
#endif

#ifndef PF_DEFAULT_HEADER_SIZE
#define PF_DEFAULT_HEADER_SIZE  (65536)
#endif
#ifndef PF_DEFAULT_CODE_SIZE
#define PF_DEFAULT_CODE_SIZE    (131072)
#endif

/* FP support adds ~20KB to the dictionary. Disable to save memory. */
#undef PF_SUPPORT_FP

/* Load pre-built dictionary from pfdicdat.h (exported via SDAD with 32-bit cells).
 * Disabled for now — need rv32-gcc + QEMU export to avoid corrupted pointers.
 * Uses pfBuildDictionary() instead (C primitives only). */
/* #undef PF_STATIC_DIC */

#endif /* PF_CONFIG_H */
