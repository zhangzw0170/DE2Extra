/* test_forth.c -- Local test for pForth integration
 *
 * Build: cd sw/lib/pforth && gcc -Wall -Wextra -Wno-unused -Wno-comment \
 *       -Wno-unused-parameter -Wno-cast-function-type \
 *       -Wno-incompatible-pointer-types -UWIN32 \
 *       -DPF_NO_FILEIO -DPF_NO_MALLOC -DPF_NO_CLIB \
 *       -DPF_STATIC_DIC \
 *       -I. -Icsrc test_forth.c csrc/pf_cglue.c csrc/pf_clib.c \
 *       csrc/pf_core.c csrc/pf_inner.c csrc/pf_io.c csrc/pf_mem.c \
 *       csrc/pf_save.c csrc/pf_text.c csrc/pf_words.c \
 *       csrc/pfcompil.c csrc/pfcustom.c pf_io_de2_local.c \
 *       -o test_forth.exe && ./test_forth
 *
 * Verifies: static dictionary load, ffInterpret, word definition.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* VGA HAL stubs */
#define VGA_WHITE   0
#define VGA_RED     1
#define VGA_GREEN   2
#define VGA_CYAN    3
#define VGA_YELLOW  4
#define VGA_GRAY    5
#define VGA_COLS 80
#define VGA_ROWS 30
char test_output[8192];
int out_pos;
void vga_putc(char c, int color) { if (out_pos < (int)sizeof(test_output)-1) test_output[out_pos++] = c; (void)color; }
void vga_puts(const char *s, int color) { while (*s && out_pos < (int)sizeof(test_output)-1) test_output[out_pos++] = *s++; (void)color; }
void vga_goto(int col, int row) { (void)col; (void)row; }
void vga_clear(void) { out_pos = 0; }

/* PS2 / board_status stubs */
#define PS2_VK_F1 0
#define PS2_VK_F10 0
void board_status_set_program(unsigned id, unsigned state, unsigned char f, unsigned short l) {}

/* pForth headers — static dictionary from pfdicdat.h */
#include "pf_config.h"
#include "csrc/pf_all.h"

/* Replicate static pfInit/pfTerm */
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

static void forth_term(void)
{
    ioTerm();
}

static int run_test(const char *name, const char *line)
{
    pfTaskData_t *td = (pfTaskData_t *)gCurrentTask;
    ThrowCode err;
    int len = strlen(line);
    td->td_IN = 0;
    td->td_SourceNum = len;
    td->td_InputStream = (void *)0x1;
    memcpy(td->td_SourcePtr, line, len);
    out_pos = 0;
    test_output[0] = '\0';
    err = ffInterpret();
    int pass = (err == 0);
    printf("  %s: %s (err=%d) out='%.*s'\n", pass ? "OK" : "FAIL", name, (int)err, out_pos, test_output);
    return pass;
}

int main(void)
{
    PForthTask task;
    PForthDictionary dic;
    ThrowCode err;
    int pass_count = 0, fail_count = 0;

    printf("pForth local test -- static dictionary load\n");

    forth_init_globals();

    task = pfCreateTask(128, 128);
    if (!task) { printf("FAIL: task alloc\n"); return 1; }
    pfSetCurrentTask(task);

    dic = pfLoadStaticDictionary();
    if (!dic) { printf("FAIL: dict load\n"); return 1; }
    printf("Dictionary loaded successfully.\n");

    err = pfExecIfDefined("AUTO.INIT");
    if (err != 0) printf("WARN: AUTO.INIT err=%d\n", (int)err);

    pfSetQuiet(1);

    /* Test 1: arithmetic */
    if (run_test("5 3 + .", "5 3 + .")) pass_count++; else fail_count++;

    /* Test 2: word definition */
    if (run_test(": square dup * ; 7 square .", ": square dup * ; 7 square .")) pass_count++; else fail_count++;

    /* Test 3: DO LOOP (system.fth word) */
    if (run_test("5 0 DO I . LOOP", "5 0 DO I . LOOP")) pass_count++; else fail_count++;

    /* Test 4: IF THEN ELSE (system.fth word) */
    if (run_test("10 5 > IF 99 ELSE 0 THEN .", "10 5 > IF 99 ELSE 0 THEN .")) pass_count++; else fail_count++;

    /* Test 5: VARIABLE (system.fth word) */
    if (run_test("VARIABLE X 42 X ! X @ .", "VARIABLE X 42 X ! X @ .")) pass_count++; else fail_count++;

    /* Test 6: EMIT */
    if (run_test("72 EMIT 105 EMIT", "72 EMIT 105 EMIT")) pass_count++; else fail_count++;

    /* Test 7: CONSTANT (system.fth word) */
    if (run_test("42 CONSTANT ANSWER ANSWER .", "42 CONSTANT ANSWER ANSWER .")) pass_count++; else fail_count++;

    /* Test 8: S\" string (system.fth word) */
    if (run_test("S\" hello\" TYPE", "S\" hello\" TYPE")) pass_count++; else fail_count++;

    /* Test 9: BEGIN UNTIL (system.fth word) */
    if (run_test("5 BEGIN DUP . 1 - DUP 0= UNTIL DROP", "5 BEGIN DUP . 1 - DUP 0= UNTIL DROP")) pass_count++; else fail_count++;

    /* Test 10: CASE (system.fth word) */
    if (run_test("2 CASE 1 OF ENDOF 2 OF 99 . ENDOF ENDCASE", "2 CASE 1 OF ENDOF 2 OF 99 . ENDOF ENDCASE")) pass_count++; else fail_count++;

    /* Cleanup */
    pfExecIfDefined("AUTO.TERM");
    pfDeleteDictionary(dic);
    pfDeleteTask(task);
    forth_term();

    printf("\n%d passed, %d failed.\n", pass_count, fail_count);
    return fail_count > 0 ? 1 : 0;
}
