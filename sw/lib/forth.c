/* forth.c -- pForth interpreter for DE2-115 (NEORV32 + VGA terminal)
 *
 * Wraps pForth as a program_t. Characters are buffered in input() until
 * newline, then the complete line is fed to ffInterpret() — no blocking
 * ACCEPT/REFILL needed.
 *
 * Uses init-mode dictionary (pfBuildDictionary) with no filesystem.
 * All kernel words (arithmetic, control structures, I/O) are available.
 *
 * Reference: https://github.com/profburke/pforth
 */

#include "vga_hal.h"
#include "board_status.h"
#include "ps2_decoder.h"

#include "pforth/pf_config.h"
#include "pforth/csrc/pf_all.h"
#include "pforth/system_fth.h"

/* PF_STDIN is normally defined in pf_io.h under !PF_NO_FILEIO.
 * Provide our own sentinel so ffRefill knows we're not a file stream. */
#ifndef PF_STDIN
#define PF_STDIN ((FileStream *)0)
#endif

/* Replicate pForth's static pfInit/pfTerm since they're not public. */
static void forth_init_globals(void)
{
    gCurrentTask = NULL;
    gCurrentDictionary = NULL;
    gNumPrimitives = 0;
    gLocalCompiler_XT = 0;
    gVarContext = 0;
    gVarState = 0;
    gVarByeCode = 0;
    gVarEcho = 0;
    gVarTraceLevel = 0;
    gVarTraceFlags = 0;
    gVarReturnCode = 0;
    gIncludeIndex = 0;
    gVarBase = 10;
    gDepthAtColon = DEPTH_AT_COLON_INVALID;
    gVarTraceStack = 1;
    pfInitMemoryAllocator();
    ioInit();
}

#define FORTH_PROG_ID 12u
#define LINE_BUF_SIZE 128
#define FORTH_DATA_STACK 128
#define FORTH_RETURN_STACK 128

static char line_buf[LINE_BUF_SIZE];
static int line_pos;
static int done;
static int help_open;

/* pForth state — initialized in init(), cleaned up in finish(). */
static PForthTask forth_task;
static PForthDictionary forth_dict;

static void print_welcome(void)
{
    vga_clear();
    vga_goto(0, 0);
    vga_puts("pForth V2.1 on NEORV32 RISC-V\n", VGA_CYAN);
    vga_puts("============================\n", VGA_GRAY);
    vga_puts("Full Forth: arithmetic, control, variables,\n", VGA_WHITE);
    vga_puts("words, strings, and more.\n", VGA_WHITE);
    vga_puts("Loading system words...\n\n", VGA_YELLOW);
}

static void draw_help(void)
{
    vga_goto(2, 2);
    vga_putc('+', VGA_CYAN);
    for (int i = 3; i < VGA_COLS - 2; i++) vga_putc('-', VGA_CYAN);
    vga_putc('+', VGA_CYAN);
    vga_goto(4, 3);
    vga_puts("pForth Quick Reference", VGA_YELLOW);
    vga_goto(4, 4);
    vga_puts("Arithmetic: + - * / MOD /MOD ABS NEGATE", VGA_WHITE);
    vga_goto(4, 5);
    vga_puts("Logic:     AND OR XOR INVERT NOT", VGA_WHITE);
    vga_goto(4, 6);
    vga_puts("Compare:   = < > 0= 0< >= <=", VGA_WHITE);
    vga_goto(4, 7);
    vga_puts("Stack:     DUP DROP SWAP OVER ROT NIP", VGA_WHITE);
    vga_goto(4, 8);
    vga_puts("Control:   IF THEN ELSE DO LOOP +LOOP", VGA_WHITE);
    vga_goto(4, 9);
    vga_puts("           BEGIN UNTIL WHILE REPEAT", VGA_WHITE);
    vga_goto(4, 10);
    vga_puts("Define:    : name ... ; VARIABLE CONST", VGA_WHITE);
    vga_goto(4, 11);
    vga_puts("Output:    . .S CR EMIT TYPE SPACE SPACES", VGA_WHITE);
    vga_goto(4, 12);
    vga_puts("Memory:    @ ! C@ C! ALLOT CELLS", VGA_WHITE);
    vga_goto(4, 13);
    vga_puts("String:    S\" .\" TYPE COUNT", VGA_WHITE);
    vga_goto(4, 14);
    vga_puts("System:    WORDS SEE .( DUMP", VGA_WHITE);
    vga_goto(4, 15);
    vga_puts("F1=close help  F10=exit to shell", VGA_GRAY);
    vga_goto(2, 16);
    vga_putc('+', VGA_CYAN);
    for (int i = 3; i < VGA_COLS - 2; i++) vga_putc('-', VGA_CYAN);
    vga_putc('+', VGA_CYAN);
}

static void prompt(void);

static void prompt(void)
{
    vga_putc('>', VGA_WHITE);
    vga_putc(' ', VGA_WHITE);
    for (int i = 0; i < line_pos; i++) {
        vga_putc(line_buf[i], VGA_WHITE);
    }
}

/* Execute one line through pForth's interpreter. */
static void execute_line(void)
{
    pfTaskData_t *td = (pfTaskData_t *)forth_task;
    ThrowCode err;

    if (line_pos == 0) return;

    line_buf[line_pos] = '\0';
    int len = line_pos;

    td->td_IN = 0;
    td->td_SourceNum = len;
    td->td_InputStream = (FileStream *)0x1;
    int copy_len = len < TIB_SIZE ? len : TIB_SIZE;
    for (int i = 0; i < copy_len; i++) {
        td->td_SourcePtr[i] = line_buf[i];
    }

    vga_putc('\n', VGA_WHITE);
    err = ffInterpret();

    vga_putc('\n', VGA_WHITE);
    if (err == 0 || err == -1) {
        vga_puts("OK ", VGA_GREEN);
    } else {
        vga_puts("ERR ", VGA_RED);
        char buf[16];
        int neg = 0;
        int val = (int)err;
        if (val < 0) { neg = 1; val = -val; }
        int pos = 0;
        if (val == 0) { buf[pos++] = '0'; }
        else {
            while (val > 0) { buf[pos++] = '0' + (val % 10); val /= 10; }
        }
        if (neg) buf[pos++] = '-';
        for (int i = pos - 1; i >= 0; i--) vga_putc(buf[i], VGA_RED);
        vga_putc(' ', VGA_WHITE);
    }

    line_pos = 0;
    prompt();
}

static void init(void)
{
    ThrowCode err;

    print_welcome();

    line_pos = 0;
    done = 0;
    help_open = 0;

    forth_init_globals();

    forth_task = pfCreateTask(FORTH_DATA_STACK, FORTH_RETURN_STACK);
    if (!forth_task) {
        vga_puts("ERR: Forth task alloc failed\n", VGA_RED);
        done = 1;
        return;
    }
    pfSetCurrentTask(forth_task);

    /* Build dictionary from C primitives, then interpret system.fth
     * to define high-level words (IF/THEN, DO/LOOP, VARIABLE, etc). */
    forth_dict = pfBuildDictionary(PF_DEFAULT_HEADER_SIZE, PF_DEFAULT_CODE_SIZE);
    if (!forth_dict) {
        vga_puts("ERR: Forth dict build failed\n", VGA_RED);
        done = 1;
        return;
    }

    pfSetQuiet(1);

    /* Interpret embedded system.fth to define high-level words.
     * Feed one line at a time via ffInterpret(). */
    {
        pfTaskData_t *td = (pfTaskData_t *)forth_task;
        const char *src = g_system_fth;
        int total_errors = 0;

        while (*src) {
            /* Extract one line */
            const char *eol = src;
            while (*eol && *eol != '\n') eol++;
            int linelen = (int)(eol - src);
            if (linelen > TIB_SIZE - 1) linelen = TIB_SIZE - 1;

            td->td_IN = 0;
            td->td_SourceNum = linelen;
            td->td_InputStream = PF_STDIN; /* prevent ffRefill */
            for (int i = 0; i < linelen; i++) {
                td->td_SourcePtr[i] = src[i];
            }
            td->td_SourcePtr[linelen] = '\0';

            err = ffInterpret();
            if (err != 0 && err != -1) { /* -1 = normal EOF from empty line */
                total_errors++;
                if (total_errors <= 3) {
                    vga_puts("ERR line: ", VGA_RED);
                    for (int i = 0; i < linelen && i < 40; i++) {
                        vga_putc(src[i], VGA_RED);
                    }
                    vga_putc('\n', VGA_RED);
                }
            }

            /* Skip past newline */
            src = *eol ? eol + 1 : eol;
        }

        if (total_errors > 0) {
            char buf[8];
            vga_puts("WARN: system.fth: ", VGA_YELLOW);
            /* Show error count */
            int n = total_errors;
            if (n == 0) { buf[0] = '0'; n = 1; }
            else {
                int pos = 0;
                while (n > 0 && pos < 7) { buf[pos++] = '0' + (n % 10); n /= 10; }
                n = pos;
            }
            for (int i = n - 1; i >= 0; i--) vga_putc(buf[i], VGA_YELLOW);
            vga_puts(" errors\n", VGA_YELLOW);
        }
    }

    pfSetQuiet(1);

    prompt();
}

static void update(void)
{
}

static void input(char c)
{
    if (c == (char)PS2_VK_F10) {
        done = 1;
        return;
    }

    if (c == (char)PS2_VK_F1) {
        help_open = !help_open;
        if (help_open) {
            vga_clear();
            draw_help();
            vga_goto(0, 17);
            prompt();
        }
        /* closing help: don't redraw — session output preserved */
        return;
    }

    if (help_open) return;

    if (c == 0x08 || c == 0x7F) {
        if (line_pos > 0) {
            line_pos--;
            int col = vga_col();
            int row = vga_row();
            if (col > 0) {
                vga_goto(col - 1, row);
                vga_putc(' ', VGA_WHITE);
                vga_goto(col - 1, row);
            }
        }
        return;
    }

    if (c == '\r' || c == '\n') {
        execute_line();
        return;
    }

    if (line_pos < LINE_BUF_SIZE - 1) {
        line_buf[line_pos++] = c;
        vga_putc(c, VGA_WHITE);
    }
}

static int finish(void)
{
    return done;
}

const program_t prog_forth = {
    "pForth", "pForth interpreter (stack-based Forth language)",
    init, update, input, NULL, finish
};
