/* pf_io_de2_local.c -- pForth I/O stub for local testing (buffer-based)
 *
 * Captures output in test_output[] from test_forth.c for verification.
 */

#include "pf_all.h"
#include <stdio.h>

/* Shared with test_forth.c */
extern char test_output[];
extern int out_pos;

int sdTerminalOut(char c)
{
    if (out_pos < 4095) test_output[out_pos++] = c;
    return 0;
}

int sdTerminalEcho(char c)
{
    if (out_pos < 4095) test_output[out_pos++] = c;
    return 0;
}

int sdTerminalIn(void)
{
    return getchar();
}

int sdTerminalFlush(void)
{
    return 0;
}

int sdQueryTerminal(void)
{
    return 1; /* always have input in test mode */
}

void sdTerminalInit(void) {}
void sdTerminalTerm(void) {}

cell_t sdSleepMillis(cell_t msec)
{
    (void)msec;
    return 0;
}
