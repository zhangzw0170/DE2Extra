/* standalone_test.c — Standalone CLI test (no FreeRTOS kernel)
 *
 * Compiles FreeRTOS_CLI.c with stub types and tests all commands.
 * Works on Windows/MinGW — no POSIX port needed.
 *
 * Usage: make test-standalone
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Override FreeRTOS includes with stubs */
#include "FreeRTOS.h"
#include "FreeRTOS_CLI.h"

/* ── CLI output buffer ─────────────────────────────────────────── */

#define BUF_SIZE 512
static char output_buf[BUF_SIZE];

/* FreeRTOS_CLI.c expects this when configAPPLICATION_PROVIDES_cOutputBuffer=1 */
char cOutputBuffer[BUF_SIZE];

/* ── Helpers ───────────────────────────────────────────────────── */

static int utoa_local(char *buf, uint32_t val) {
    char tmp[11];
    int i = 0;
    if (val == 0) { buf[0] = '0'; buf[1] = '\0'; return 1; }
    while (val) { tmp[i++] = '0' + (val % 10); val /= 10; }
    int len = i;
    while (i--) *buf++ = tmp[i];
    *buf = '\0';
    return len;
}

static int strcpy_local(char *dst, const char *src) {
    int n = 0;
    while ((*dst++ = *src++)) n++;
    return n - 1;
}

/* ── Mock program commands ─────────────────────────────────────── */

#define PROG_CMD(name)                                                     \
static BaseType_t cli_##name(char *buf, size_t len, const char *cmd) {   \
    (void)cmd; (void)len;                                                 \
    sprintf(buf, "Starting " #name "...\r\n");                            \
    return pdFALSE;                                                       \
}

PROG_CMD(hello)
PROG_CMD(crypto)
PROG_CMD(ps2)
PROG_CMD(snake)
PROG_CMD(life)
PROG_CMD(info)
PROG_CMD(monitor)
PROG_CMD(expdemo)
PROG_CMD(gui)

/* ── System stats (mocked) ─────────────────────────────────────── */

static BaseType_t cli_stats(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    const char *mock = "Name          State  Prio  Stack  #\r\n"
                       "***********************************\r\n"
                       "shell         B      2     128    1\r\n"
                       "uart          B      3     64     2\r\n"
                       "status        B      1     89     3\r\n"
                       "IDLE          R      0     89     4\r\n"
                       "Tmr Svc       N/A    0     0      0\r\n";
    strcpy(buf, mock);
    return pdFALSE;
}

static BaseType_t cli_heapstat(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    sprintf(buf, "Heap free: %u / %u bytes\r\nMin free: %u bytes\r\n",
            15872u, 16384u, 14336u);
    return pdFALSE;
}

static BaseType_t cli_cpustat(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    const char *mock = "Name          Abs Time    % Time\r\n"
                       "***********************************\r\n"
                       "shell         52345       12%\r\n"
                       "uart          18432       43%\r\n"
                       "status        5003        11%\r\n"
                       "IDLE          12345       28%\r\n";
    strcpy(buf, mock);
    return pdFALSE;
}

/* ── Command definitions ───────────────────────────────────────── */

static const CLI_Command_Definition_t cmds[] = {
    {"hello",    "hello:    LED chaser\r\n",                 cli_hello,    0},
    {"crypto",   "crypto:   AES/SHA/SM4 CLI\r\n",            cli_crypto,   0},
    {"ps2",      "ps2:      PS/2 keyboard test\r\n",          cli_ps2,      0},
    {"snake",    "snake:    Snake game\r\n",                  cli_snake,    0},
    {"info",     "info:     System dashboard\r\n",            cli_info,     0},
    {"expdemo",  "expdemo:  11 course labs\r\n",              cli_expdemo,  0},
    {"gui",      "gui:      Win 3.0 GUI\r\n",                 cli_gui,      0},
    /* Aliases */
    {"conwaylife","conwaylife: Conway's Game of Life (alias)\r\n", cli_life, 0},
    {"riscvasm",  "riscvasm:  monitor alias\r\n",           cli_monitor,  0},
    /* Stats */
    {"stats",    "stats:    Task list + stack HWM\r\n",      cli_stats,    0},
    {"heapstat", "heapstat: Heap usage\r\n",                 cli_heapstat, 0},
    {"cpustat",  "cpustat:  CPU usage per task\r\n",         cli_cpustat,  0},
};

#define NUM_CMDS (sizeof(cmds) / sizeof(cmds[0]))

/* ── Test framework ────────────────────────────────────────────── */

static int tests_passed = 0;
static int tests_failed = 0;

static void assert_contains(const char *desc, const char *output, const char *expected) {
    if (strstr(output, expected) != NULL) {
        printf("  PASS: %s\n", desc);
        tests_passed++;
    } else {
        printf("  FAIL: %s\n  Expected substring: \"%s\"\n  Got: \"%s\"\n",
               desc, expected, output);
        tests_failed++;
    }
}

static void assert_not_contains(const char *desc, const char *output, const char *unexpected) {
    if (strstr(output, unexpected) == NULL) {
        printf("  PASS: %s\n", desc);
        tests_passed++;
    } else {
        printf("  FAIL: %s\n  Unexpected substring found: \"%s\"\n", desc, unexpected);
        tests_failed++;
    }
}

static size_t accumulated_len;
static char accumulated_buf[BUF_SIZE * 4];

static void run_command(const char *cmd_str) {
    BaseType_t more;
    accumulated_len = 0;
    accumulated_buf[0] = '\0';
    do {
        memset(output_buf, 0, BUF_SIZE);
        more = FreeRTOS_CLIProcessCommand(cmd_str, output_buf, BUF_SIZE);
        size_t chunk = strlen(output_buf);
        if (accumulated_len + chunk < sizeof(accumulated_buf) - 1) {
            memcpy(accumulated_buf + accumulated_len, output_buf, chunk);
            accumulated_len += chunk;
            accumulated_buf[accumulated_len] = '\0';
        }
    } while (more != pdFALSE);
}

/* ── Tests ─────────────────────────────────────────────────────── */

static void test_help(void) {
    printf("\n=== test: help ===\n");
    run_command("help");
    assert_contains("help lists hello",    accumulated_buf, "hello");
    assert_not_contains("help hides memtest", accumulated_buf, "memtest");
    assert_not_contains("help hides startui", accumulated_buf, "startui");
    assert_contains("help lists gui", accumulated_buf, "gui");
    assert_contains("help lists stats",    accumulated_buf, "stats");
    assert_contains("help lists heapstat", accumulated_buf, "heapstat");
    assert_contains("help lists cpustat",  accumulated_buf, "cpustat");
}

static void test_program_commands(void) {
    printf("\n=== test: program commands ===\n");
    const char *cmds[] = {"hello", "crypto", "ps2", "snake",
                          "info", "expdemo", "gui"};
    const char *names[] = {"hello", "crypto", "ps2", "snake",
                           "info", "expdemo", "gui"};

    for (int i = 0; i < 7; i++) {
        run_command(cmds[i]);
        char expected[64];
        sprintf(expected, "Starting %s", names[i]);
        assert_contains(cmds[i], output_buf, expected);
    }
}

static void test_aliases(void) {
    printf("\n=== test: aliases ===\n");

    run_command("conwaylife");
    assert_contains("conwaylife -> life", output_buf, "Starting life");

    run_command("riscvasm");
    assert_contains("riscvasm -> monitor", output_buf, "Starting monitor");
}

static void test_stats(void) {
    printf("\n=== test: stats ===\n");
    run_command("stats");
    assert_contains("stats shows shell",  output_buf, "shell");
    assert_contains("stats shows uart",   output_buf, "uart");
    assert_contains("stats shows status", output_buf, "status");
    assert_contains("stats shows IDLE",   output_buf, "IDLE");
}

static void test_heapstat(void) {
    printf("\n=== test: heapstat ===\n");
    run_command("heapstat");
    assert_contains("heapstat shows Heap free", output_buf, "Heap free:");
    assert_contains("heapstat shows bytes",     output_buf, "bytes");
    assert_contains("heapstat shows Min free",  output_buf, "Min free:");
}

static void test_cpustat(void) {
    printf("\n=== test: cpustat ===\n");
    run_command("cpustat");
    assert_contains("cpustat shows shell", output_buf, "shell");
    assert_contains("cpustat shows %",      output_buf, "%");
}

static void test_unknown(void) {
    printf("\n=== test: unknown command ===\n");
    run_command("xyzzy123");
    /* FreeRTOS+CLI returns empty buffer for unknown commands */
    printf("  INFO: unknown command output: \"%s\"\n", output_buf);
}

static void test_case_sensitivity(void) {
    printf("\n=== test: case sensitivity ===\n");
    run_command("HELP");
    /* FreeRTOS+CLI requires lowercase — should not match */
    assert_not_contains("HELP uppercase not matched", output_buf, "Starting");
}

/* ── Main ──────────────────────────────────────────────────────── */

int main(void) {
    /* Register all commands */
    for (int i = 0; i < (int)NUM_CMDS; i++) {
        BaseType_t result = FreeRTOS_CLIRegisterCommand(&cmds[i]);
        if (result != pdPASS) {
            fprintf(stderr, "FATAL: failed to register command '%s'\n", cmds[i].pcCommand);
            return 1;
        }
    }
    printf("Registered %d CLI commands\n", (int)NUM_CMDS);

    /* Run tests */
    test_help();
    test_program_commands();
    test_aliases();
    test_stats();
    test_heapstat();
    test_cpustat();
    test_unknown();
    test_case_sensitivity();

    /* Summary */
    printf("\n===============================\n");
    printf("Results: %d passed, %d failed\n", tests_passed, tests_failed);
    printf("===============================\n");

    return tests_failed > 0 ? 1 : 0;
}
