/* pf_io_de2.c -- pForth I/O layer for DE2-115 (NEORV32 + VGA terminal)
 *
 * Provides sdTerminalOut/In/Echo/Flush/Init/Term and sdQueryTerminal
 * for pForth running inside the de2shell_rtos program framework.
 *
 * Input:  characters queued by the program_t input() callback
 * Output: VGA text terminal via vga_hal
 */

#include "pf_all.h"

#include "../vga_hal.h"
#include "../ps2_decoder.h"

/* Circular buffer for characters fed by input() callback. */
#define PF_RING_SIZE 128
static char pf_ring[PF_RING_SIZE];
static volatile int pf_ring_head = 0;
static volatile int pf_ring_tail = 0;

/* Called from program_t input() to feed a character into pForth. */
void pf_feed_char(char c)
{
    int next = (pf_ring_head + 1) % PF_RING_SIZE;
    if (next != pf_ring_tail) {
        pf_ring[pf_ring_head] = c;
        pf_ring_head = next;
    }
}

int sdTerminalOut(char c)
{
    vga_putc(c, VGA_WHITE);
    return 0;
}

int sdTerminalEcho(char c)
{
    vga_putc(c, VGA_WHITE);
    return 0;
}

int sdTerminalIn(void)
{
    if (pf_ring_head == pf_ring_tail) {
        return -1;
    }
    char c = pf_ring[pf_ring_tail];
    pf_ring_tail = (pf_ring_tail + 1) % PF_RING_SIZE;
    return (unsigned char)c;
}

int sdTerminalFlush(void)
{
    return 0;
}

int sdQueryTerminal(void)
{
    return (pf_ring_head != pf_ring_tail);
}

void sdTerminalInit(void)
{
    pf_ring_head = 0;
    pf_ring_tail = 0;
}

void sdTerminalTerm(void)
{
}

cell_t sdSleepMillis(cell_t msec)
{
    for (volatile cell_t i = 0; i < msec * 1000; i++) {
        /* busy-wait, ~1us per iteration at 50MHz */
    }
    return 0;
}
