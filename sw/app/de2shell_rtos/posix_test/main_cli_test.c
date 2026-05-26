/* main_cli_test.c — POSIX FreeRTOS CLI test for de2shell_rtos
 *
 * Interactive test: reads stdin line by line, processes via FreeRTOS+CLI.
 * Type 'help' for commands, 'quit' to exit.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include "FreeRTOS.h"
#include "task.h"
#include "FreeRTOS_CLI.h"

/* From mock_hal.c */
extern char cOutputBuffer[];

/* ── Program enum (mirrors main.c) ─────────────────────────────── */

typedef enum {
    PROG_SHELL = 0,
    PROG_HELLO, PROG_CRYPTO, PROG_PS2,
    PROG_SNAKE, PROG_LIFE, PROG_INFO, PROG_MONITOR,
    PROG_DEMO, PROG_WIN30, PROG_COUNT
} prog_id_t;

static volatile prog_id_t active_prog = PROG_SHELL;
static volatile prog_id_t cli_launch_req = PROG_SHELL;

/* ── Helpers (same as main.c) ──────────────────────────────────── */

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

/* ── CLI command callbacks ─────────────────────────────────────── */

#define PROG_CMD(name, pid)                                               \
static BaseType_t cli_##name(char *buf, size_t len, const char *cmd) {   \
    (void)cmd; (void)len;                                                 \
    char *p = buf;                                                        \
    p += strcpy_local(p, "Starting " #name "...\r\n");                    \
    cli_launch_req = (pid);                                               \
    return pdFALSE;                                                       \
}

PROG_CMD(hello,   PROG_HELLO)
PROG_CMD(crypto,  PROG_CRYPTO)
PROG_CMD(ps2,     PROG_PS2)
PROG_CMD(snake,   PROG_SNAKE)
PROG_CMD(life,    PROG_LIFE)
PROG_CMD(info,    PROG_INFO)
PROG_CMD(monitor, PROG_MONITOR)
PROG_CMD(expdemo, PROG_DEMO)
PROG_CMD(gui,     PROG_WIN30)

static BaseType_t cli_stats(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    vTaskList(buf);
    return pdFALSE;
}

static BaseType_t cli_heapstat(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    char *p = buf;
    p += strcpy_local(p, "Heap free: ");
    p += utoa_local(p, xPortGetFreeHeapSize());
    p += strcpy_local(p, " / ");
    p += utoa_local(p, configTOTAL_HEAP_SIZE);
    p += strcpy_local(p, " bytes\r\nMin free: ");
    p += utoa_local(p, xPortGetMinimumEverFreeHeapSize());
    p += strcpy_local(p, " bytes\r\n");
    return pdFALSE;
}

static BaseType_t cli_cpustat(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    vTaskGetRunTimeStats(buf);
    return pdFALSE;
}

static BaseType_t cli_quit(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    strcpy_local(buf, "Goodbye!\r\n");
    exit(0);
    return pdFALSE;
}

/* ── CLI command definitions ───────────────────────────────────── */

static const CLI_Command_Definition_t cmd_hello_def    = {"hello",    "hello:    LED chaser\r\n",                 cli_hello,    0};
static const CLI_Command_Definition_t cmd_crypto_def   = {"crypto",   "crypto:   AES/SHA/SM4 CLI\r\n",            cli_crypto,   0};
static const CLI_Command_Definition_t cmd_ps2_def      = {"ps2",      "ps2:      PS/2 keyboard test\r\n",          cli_ps2,      0};
static const CLI_Command_Definition_t cmd_snake_def    = {"snake",    "snake:    Snake game\r\n",                  cli_snake,    0};
static const CLI_Command_Definition_t cmd_info_def     = {"info",     "info:     System dashboard\r\n",            cli_info,     0};
static const CLI_Command_Definition_t cmd_expdemo_def  = {"expdemo",  "expdemo:  11 course labs\r\n",              cli_expdemo,  0};

/* Aliases */
static const CLI_Command_Definition_t cmd_conway_def   = {"conwaylife","conwaylife: Conway's Game of Life (alias)\r\n", cli_life, 0};
static const CLI_Command_Definition_t cmd_riscvasm_def = {"riscvasm",  "riscvasm:  monitor alias\r\n",           cli_monitor,  0};
static const CLI_Command_Definition_t cmd_gui_def      = {"gui",       "gui:       Win 3.0 GUI\r\n",              cli_gui,      0};

/* System stats */
static const CLI_Command_Definition_t cmd_stats_def    = {"stats",    "stats:    Task list + stack HWM\r\n",      cli_stats,    0};
static const CLI_Command_Definition_t cmd_heapstat_def = {"heapstat", "heapstat: Heap usage\r\n",                 cli_heapstat, 0};
static const CLI_Command_Definition_t cmd_cpustat_def  = {"cpustat",  "cpustat:  CPU usage per task\r\n",         cli_cpustat,  0};

/* Test-only */
static const CLI_Command_Definition_t cmd_quit_def     = {"quit",     "quit:     Exit POSIX test\r\n",            cli_quit,     0};

static void register_cli_commands(void) {
    FreeRTOS_CLIRegisterCommand(&cmd_hello_def);
    FreeRTOS_CLIRegisterCommand(&cmd_crypto_def);
    FreeRTOS_CLIRegisterCommand(&cmd_ps2_def);
    FreeRTOS_CLIRegisterCommand(&cmd_snake_def);
    FreeRTOS_CLIRegisterCommand(&cmd_info_def);
    FreeRTOS_CLIRegisterCommand(&cmd_expdemo_def);
    FreeRTOS_CLIRegisterCommand(&cmd_conway_def);
    FreeRTOS_CLIRegisterCommand(&cmd_riscvasm_def);
    FreeRTOS_CLIRegisterCommand(&cmd_gui_def);
    FreeRTOS_CLIRegisterCommand(&cmd_stats_def);
    FreeRTOS_CLIRegisterCommand(&cmd_heapstat_def);
    FreeRTOS_CLIRegisterCommand(&cmd_cpustat_def);
    FreeRTOS_CLIRegisterCommand(&cmd_quit_def);
}

/* ── Shell task ────────────────────────────────────────────────── */

#define CLI_BUF_SIZE 512

static void t_shell(void *pv) {
    (void)pv;
    char line[80];

    printf("\n=== DE2Extra POSIX CLI Test ===\n");
    printf("Type 'help' for commands, 'quit' to exit\n");
    printf("RTOS > ");
    fflush(stdout);

    for (;;) {
        if (fgets(line, sizeof(line), stdin) == NULL) {
            exit(0);
        }

        /* Strip trailing newline */
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
            len--;
        }

        if (len == 0) {
            printf("RTOS > ");
            fflush(stdout);
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        /* Process via CLI */
        BaseType_t more;
        do {
            more = FreeRTOS_CLIProcessCommand(line, cOutputBuffer, CLI_BUF_SIZE);
            printf("%s", cOutputBuffer);
        } while (more != pdFALSE);
        fflush(stdout);

        /* Handle program launch */
        if (cli_launch_req != PROG_SHELL) {
            printf("  [posix] would launch program %d\n", cli_launch_req);
            cli_launch_req = PROG_SHELL;
        }

        printf("RTOS > ");
        fflush(stdout);
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ── Status task ───────────────────────────────────────────────── */

static void t_status(void *pv) {
    (void)pv;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

/* ── Platform hooks ────────────────────────────────────────────── */

void freertos_risc_v_application_interrupt_handler(void) {}
void freertos_risc_v_application_exception_handler(void) {}

void vApplicationMallocFailedHook(void) {
    fprintf(stderr, "FATAL: malloc failed\n");
    exit(1);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    fprintf(stderr, "FATAL: stack overflow '%s'\n", pcTaskName);
    exit(1);
}

void vApplicationIdleHook(void) {}

/* ── Main ──────────────────────────────────────────────────────── */

int main(void) {
    register_cli_commands();

    xTaskCreate(t_shell, "shell", 2048, NULL, 2, NULL);
    xTaskCreate(t_status, "status", 1024, NULL, 1, NULL);

    printf("Starting FreeRTOS scheduler (POSIX)...\n");
    vTaskStartScheduler();

    fprintf(stderr, "FATAL: scheduler returned\n");
    return 1;
}
