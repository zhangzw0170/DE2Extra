/* pf_win32.h -- WIN32 dependent include for pForth.
 * Include as PF_USER_INC2 for Windows builds.
 * Forces "b" mode for fopen to prevent LF mangling. */
#ifndef _pf_win32_h
#define _pf_win32_h

#undef PF_FAM_CREATE
#define PF_FAM_CREATE ("wb+")

#undef PF_FAM_OPEN_RO
#define PF_FAM_OPEN_RO ("rb")

#undef PF_FAM_OPEN_RW
#define PF_FAM_OPEN_RW ("rb+")

#endif /* _pf_win32_h */
