/* pf_io_host.c -- Host I/O stubs for pForth export build.
 * stdin/stdout based, used only during dictionary export (SDAD). */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef int32_t cell_t;
typedef uint32_t ucell_t;
typedef cell_t ThrowCode;
#define FileStream FILE

#include "pf_io.h"

int sdTerminalOut(char c)
{
    putchar(c);
    return 0;
}

int sdTerminalEcho(char c)
{
    putchar(c);
    return 0;
}

int sdTerminalFlush(void)
{
    fflush(stdout);
    return 0;
}

int sdTerminalIn(void)
{
    return getchar();
}

int sdQueryTerminal(void)
{
    return 0; /* no input available */
}

void sdTerminalInit(void)
{
}

void sdTerminalTerm(void)
{
    fflush(stdout);
}

cell_t sdSleepMillis(cell_t msec)
{
    (void)msec;
    return 0;
}

ThrowCode sdResizeFile(FileStream *fp, uint64_t size)
{
    (void)fp;
    (void)size;
    return 0;
}
