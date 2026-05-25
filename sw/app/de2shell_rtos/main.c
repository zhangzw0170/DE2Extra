/* main.c — de2shell_rtos: FreeRTOS-based de2shell
 *
 * Runs de2shell programs as FreeRTOS tasks on NEORV32.
 * SDRAM execution, CLINT MTIMER tick.
 *
 * Tasks:
 *   t_uart_input (pri 3): Polls UART + PS/2, feeds input queue
 *   t_shell      (pri 2): FreeRTOS+CLI command parser, program launcher
 *   t_active     (pri 2): Currently active program (dynamic)
 *   t_status     (pri 1): Status bar + heartbeat
 */

#include <neorv32.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "FreeRTOS_CLI.h"

#include "vga_hal.h"
#include "fb_hal.h"
#include "gpio_hal.h"
#include "board_status.h"
#include "ps2_decoder.h"

#define BAUD_RATE 115200
#define PS2_MMIO_BASE ((volatile uint32_t *)0xF0002000u)
#define PS2_REG_DATA  0u
#define PS2_REG_STAT  1u
#define PS2_STAT_READY 0x01u

/* ── Program declarations (program_t defined in vga_hal.h) ────── */

extern const program_t prog_hello;
extern const program_t prog_memtest;
extern const program_t prog_crypto;
extern const program_t prog_ps2;
extern const program_t prog_snake;
extern const program_t prog_life;
extern const program_t prog_info;
extern const program_t prog_monitor;
extern const program_t prog_demo;
extern const program_t prog_win30;

/* Stub for de2shell programs that reference last_ir_cmd */
uint8_t last_ir_cmd = 0;

/* CLI output buffer — placed in SDRAM to save DMEM */
char cOutputBuffer[configCOMMAND_INT_MAX_OUTPUT_SIZE] __attribute__((section(".sdram_bss")));

typedef enum {
    PROG_SHELL = 0,
    PROG_HELLO,
    PROG_MEMTEST,
    PROG_CRYPTO,
    PROG_PS2,
    PROG_SNAKE,
    PROG_LIFE,
    PROG_INFO,
    PROG_MONITOR,
    PROG_DEMO,
    PROG_WIN30,
    PROG_COUNT
} prog_id_t;

static const program_t *programs[PROG_COUNT] = {
    [PROG_SHELL]     = NULL,
    [PROG_HELLO]     = &prog_hello,
    [PROG_MEMTEST]   = &prog_memtest,
    [PROG_CRYPTO]    = &prog_crypto,
    [PROG_PS2]       = &prog_ps2,
    [PROG_SNAKE]     = &prog_snake,
    [PROG_LIFE]      = &prog_life,
    [PROG_INFO]      = &prog_info,
    [PROG_MONITOR]   = &prog_monitor,
    [PROG_DEMO]      = &prog_demo,
    [PROG_WIN30]     = &prog_win30,
};

/* ── Shared state ─────────────────────────────────────────────── */

static volatile prog_id_t active_prog = PROG_SHELL;
static volatile prog_id_t cli_launch_req = PROG_SHELL;

static QueueHandle_t xInputQueue;
static QueueHandle_t xProgCmdQueue;
static SemaphoreHandle_t xVgaMutex;
static TaskHandle_t xActiveTask;

typedef enum { CMD_STOP } prog_cmd_t;

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

/* ── FreeRTOS+CLI command callbacks ───────────────────────────── */

#define PROG_CMD(name, pid)                                               \
static BaseType_t cli_##name(char *buf, size_t len, const char *cmd) {   \
    (void)cmd; (void)len;                                                 \
    char *p = buf;                                                        \
    p += strcpy_local(p, "Starting " #name "...\r\n");                    \
    cli_launch_req = (pid);                                               \
    return pdFALSE;                                                       \
}

PROG_CMD(hello,   PROG_HELLO)
PROG_CMD(memtest, PROG_MEMTEST)
PROG_CMD(crypto,  PROG_CRYPTO)
PROG_CMD(ps2,     PROG_PS2)
PROG_CMD(snake,   PROG_SNAKE)
PROG_CMD(life,    PROG_LIFE)
PROG_CMD(info,    PROG_INFO)
PROG_CMD(monitor, PROG_MONITOR)
PROG_CMD(expdemo, PROG_DEMO)
PROG_CMD(startui, PROG_WIN30)

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

/* ── CLI command definitions ───────────────────────────────────── */

static const CLI_Command_Definition_t cmd_hello_def    = {"hello",    "hello:    LED chaser\r\n",                 cli_hello,    0};
static const CLI_Command_Definition_t cmd_memtest_def  = {"memtest",  "memtest:  SDRAM diagnostics\r\n",          cli_memtest,  0};
static const CLI_Command_Definition_t cmd_crypto_def   = {"crypto",   "crypto:   AES/SHA/SM4 CLI\r\n",            cli_crypto,   0};
static const CLI_Command_Definition_t cmd_ps2_def      = {"ps2",      "ps2:      PS/2 keyboard test\r\n",          cli_ps2,      0};
static const CLI_Command_Definition_t cmd_snake_def    = {"snake",    "snake:    Snake game\r\n",                  cli_snake,    0};
static const CLI_Command_Definition_t cmd_life_def     = {"life",     "life:     Conway's Game of Life\r\n",       cli_life,     0};
static const CLI_Command_Definition_t cmd_info_def     = {"info",     "info:     System dashboard\r\n",            cli_info,     0};
static const CLI_Command_Definition_t cmd_monitor_def  = {"monitor",  "monitor:  RISC-V instruction monitor\r\n",  cli_monitor,  0};
static const CLI_Command_Definition_t cmd_expdemo_def  = {"expdemo",  "expdemo:  11 course labs\r\n",              cli_expdemo,  0};
static const CLI_Command_Definition_t cmd_startui_def  = {"startui",  "startui:  Win 3.0 GUI\r\n",                cli_startui,  0};

/* Aliases */
static const CLI_Command_Definition_t cmd_kbd_def      = {"kbd",       "kbd:       PS/2 (alias)\r\n",             cli_ps2,      0};
static const CLI_Command_Definition_t cmd_conway_def   = {"conwaylife","conwaylife: life (alias)\r\n",            cli_life,     0};
static const CLI_Command_Definition_t cmd_dash_def     = {"dash",      "dash:      info (alias)\r\n",            cli_info,     0};
static const CLI_Command_Definition_t cmd_riscvasm_def = {"riscvasm",  "riscvasm:  monitor (alias)\r\n",         cli_monitor,  0};
static const CLI_Command_Definition_t cmd_rv32_def     = {"rv32",      "rv32:      monitor (alias)\r\n",         cli_monitor,  0};
static const CLI_Command_Definition_t cmd_gui_def      = {"gui",       "gui:       startui (alias)\r\n",         cli_startui,  0};

/* System stats */
static const CLI_Command_Definition_t cmd_stats_def    = {"stats",    "stats:    Task list + stack HWM\r\n",      cli_stats,    0};
static const CLI_Command_Definition_t cmd_heapstat_def = {"heapstat", "heapstat: Heap usage\r\n",                 cli_heapstat, 0};
static const CLI_Command_Definition_t cmd_cpustat_def  = {"cpustat",  "cpustat:  CPU usage per task\r\n",         cli_cpustat,  0};

static void register_cli_commands(void) {
    FreeRTOS_CLIRegisterCommand(&cmd_hello_def);
    FreeRTOS_CLIRegisterCommand(&cmd_memtest_def);
    FreeRTOS_CLIRegisterCommand(&cmd_crypto_def);
    FreeRTOS_CLIRegisterCommand(&cmd_ps2_def);
    FreeRTOS_CLIRegisterCommand(&cmd_snake_def);
    FreeRTOS_CLIRegisterCommand(&cmd_life_def);
    FreeRTOS_CLIRegisterCommand(&cmd_info_def);
    FreeRTOS_CLIRegisterCommand(&cmd_monitor_def);
    FreeRTOS_CLIRegisterCommand(&cmd_expdemo_def);
    FreeRTOS_CLIRegisterCommand(&cmd_startui_def);
    FreeRTOS_CLIRegisterCommand(&cmd_kbd_def);
    FreeRTOS_CLIRegisterCommand(&cmd_conway_def);
    FreeRTOS_CLIRegisterCommand(&cmd_dash_def);
    FreeRTOS_CLIRegisterCommand(&cmd_riscvasm_def);
    FreeRTOS_CLIRegisterCommand(&cmd_rv32_def);
    FreeRTOS_CLIRegisterCommand(&cmd_gui_def);
    FreeRTOS_CLIRegisterCommand(&cmd_stats_def);
    FreeRTOS_CLIRegisterCommand(&cmd_heapstat_def);
    FreeRTOS_CLIRegisterCommand(&cmd_cpustat_def);
}

/* ── Platform hooks ───────────────────────────────────────────── */

void freertos_risc_v_application_interrupt_handler(void) {
}

void freertos_risc_v_application_exception_handler(void) {
    neorv32_uart0_puts("!!! FreeRTOS exception !!!\n");
    for (;;) ;
}

void vApplicationMallocFailedHook(void) {
    neorv32_uart0_puts("FATAL: malloc failed\n");
    for (;;) ;
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    neorv32_uart0_puts("FATAL: stack overflow '");
    neorv32_uart0_puts(pcTaskName);
    neorv32_uart0_puts("'\n");
    for (;;) ;
}

void vApplicationIdleHook(void) {
    static uint32_t idle_count;
    idle_count++;
}

static void reset_display_mode(void) {
    fb_shutdown();
}

/* ── UART input task (pri 3) ──────────────────────────────────── */

static void t_uart_input(void *pv) {
    (void)pv;
    char c;
    ps2_key_t key;
    volatile uint32_t * const ps2 = PS2_MMIO_BASE;

    ps2_dec_init();

    for (;;) {
        if (neorv32_uart0_char_received()) {
            c = (char)neorv32_uart0_getc();
            xQueueSend(xInputQueue, &c, 0);
        }

        while ((ps2[PS2_REG_STAT] & PS2_STAT_READY) != 0u) {
            uint8_t raw = (uint8_t)ps2[PS2_REG_DATA];
            if (ps2_dec_feed(raw, &key) && key.is_press && key.has_ascii) {
                c = (char)key.ascii;
                xQueueSend(xInputQueue, &c, 0);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

/* ── Active program task (pri 2) ──────────────────────────────── */

static void exit_active_program(void) {
    reset_display_mode();
    active_prog = PROG_SHELL;
    xActiveTask = NULL;
    vTaskDelete(NULL);
}

static void t_active_prog(void *pv) {
    (void)pv;
    char c;
    prog_cmd_t cmd;

    for (;;) {
        if (xQueueReceive(xProgCmdQueue, &cmd, 0) == pdTRUE) {
            (void)cmd;
            exit_active_program();
        }

        if (xQueueReceive(xInputQueue, &c, 0) == pdTRUE) {
            if (c == 27) {
                exit_active_program();
            }
            const program_t *prog = programs[active_prog];
            if (prog && prog->input) {
                xSemaphoreTake(xVgaMutex, portMAX_DELAY);
                prog->input(c);
                xSemaphoreGive(xVgaMutex);
            }
        }

        const program_t *prog = programs[active_prog];
        if (prog && prog->update) {
            xSemaphoreTake(xVgaMutex, portMAX_DELAY);
            prog->update();
            xSemaphoreGive(xVgaMutex);
        }

        if (prog && prog->finish && prog->finish()) {
            exit_active_program();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ── Shell task (pri 2) ───────────────────────────────────────── */

#define SHELL_LINE_SIZE 48
#define CLI_OUTPUT_BUF_SIZE configCOMMAND_INT_MAX_OUTPUT_SIZE
static char shell_line[SHELL_LINE_SIZE];
static int shell_line_pos;

static void shell_prompt(void) {
    vga_puts("RTOS> ", VGA_GREEN);
}

static void shell_init_screen(void) {
    reset_display_mode();
    xSemaphoreTake(xVgaMutex, portMAX_DELAY);
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Shell (FreeRTOS)\n", VGA_CYAN);
    vga_puts("Type 'help' for commands\n", VGA_GRAY);
    shell_line_pos = 0;
    shell_line[0] = '\0';
    shell_prompt();
    xSemaphoreGive(xVgaMutex);
}

static void stop_active_program(void) {
    TaskHandle_t task = xActiveTask;
    TickType_t start;

    if (task == NULL) {
        reset_display_mode();
        active_prog = PROG_SHELL;
        return;
    }

    {
        prog_cmd_t cmd = CMD_STOP;
        (void)xQueueSend(xProgCmdQueue, &cmd, 0);
    }

    start = xTaskGetTickCount();
    while ((xActiveTask != NULL) && ((xTaskGetTickCount() - start) < pdMS_TO_TICKS(50))) {
        vTaskDelay(pdMS_TO_TICKS(5));
    }

    if (xActiveTask != NULL) {
        vTaskDelete(task);
        xActiveTask = NULL;
    }

    reset_display_mode();
    active_prog = PROG_SHELL;
}

static void launch_program(prog_id_t pid) {
    if (pid <= PROG_SHELL || pid >= PROG_COUNT) return;
    const program_t *prog = programs[pid];
    if (!prog) return;

    if (xActiveTask != NULL) {
        stop_active_program();
    }

    active_prog = pid;

    char dummy;
    while (xQueueReceive(xInputQueue, &dummy, 0)) {}

    xSemaphoreTake(xVgaMutex, portMAX_DELAY);
    if (prog->init) prog->init();
    xSemaphoreGive(xVgaMutex);

    if (xTaskCreate(t_active_prog, "prog", 256, NULL, 2, &xActiveTask) != pdPASS) {
        active_prog = PROG_SHELL;
        xActiveTask = NULL;
        reset_display_mode();
        xSemaphoreTake(xVgaMutex, portMAX_DELAY);
        vga_puts("ERR: program task alloc failed\n", VGA_RED);
        shell_prompt();
        xSemaphoreGive(xVgaMutex);
    }
}

static void t_shell(void *pv) {
    (void)pv;
    char c;

    shell_init_screen();

    for (;;) {
        if (active_prog != PROG_SHELL) {
            vTaskDelay(pdMS_TO_TICKS(50));
            if (active_prog == PROG_SHELL) {
                shell_init_screen();
            }
            continue;
        }

        if (xQueueReceive(xInputQueue, &c, pdMS_TO_TICKS(20)) != pdTRUE)
            continue;

        xSemaphoreTake(xVgaMutex, portMAX_DELAY);

        if (c == '\r' || c == '\n') {
            shell_line[shell_line_pos] = '\0';
            vga_putc('\n', VGA_WHITE);

            if (shell_line_pos > 0) {
                BaseType_t more;
                do {
                    more = FreeRTOS_CLIProcessCommand(
                        shell_line, cOutputBuffer, CLI_OUTPUT_BUF_SIZE);
                    vga_puts(cOutputBuffer, VGA_WHITE);
                } while (more != pdFALSE);

                if (cli_launch_req != PROG_SHELL) {
                    prog_id_t pid = cli_launch_req;
                    cli_launch_req = PROG_SHELL;
                    xSemaphoreGive(xVgaMutex);
                    launch_program(pid);
                    continue;
                }
            }
            shell_line_pos = 0;
            shell_line[0] = '\0';
            shell_prompt();
        } else if (c == '\b' || c == 0x7F) {
            if (shell_line_pos > 0) {
                shell_line_pos--;
                shell_line[shell_line_pos] = '\0';
                vga_putc('\b', VGA_WHITE);
            }
        } else if (c >= ' ' && c < 0x7F && shell_line_pos < SHELL_LINE_SIZE - 1) {
            shell_line[shell_line_pos++] = c;
            shell_line[shell_line_pos] = '\0';
            vga_putc(c, VGA_WHITE);
        }

        xSemaphoreGive(xVgaMutex);
    }
}

/* ── Status task (pri 1) ──────────────────────────────────────── */

static void t_status(void *pv) {
    (void)pv;
    for (;;) {
        xSemaphoreTake(xVgaMutex, portMAX_DELAY);
        int saved_col = vga_col();
        int saved_row = vga_row();
        vga_goto(0, VGA_ROWS - 1);
        vga_puts(" DE2Extra RTOS | ", VGA_CYAN);
        if (active_prog > PROG_SHELL && active_prog < PROG_COUNT && programs[active_prog]) {
            vga_puts(programs[active_prog]->name, VGA_GREEN);
        } else {
            vga_puts("Shell", VGA_GREEN);
        }
        for (int i = vga_col(); i < VGA_COLS; i++) {
            vga_putc(' ', VGA_BLACK);
        }
        vga_goto(saved_col, saved_row);
        xSemaphoreGive(xVgaMutex);

        board_status_set_program((uint8_t)active_prog, 1, 0, 0);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

/* ── Main ─────────────────────────────────────────────────────── */

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("\n=== de2shell_rtos: FreeRTOS on NEORV32 ===\n");

    gpio_write_out(0);
    board_status_init();
    vga_init();
    reset_display_mode();

    extern void freertos_risc_v_trap_handler(void);
    neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)freertos_risc_v_trap_handler);

    xInputQueue  = xQueueCreate(32, sizeof(char));
    xProgCmdQueue = xQueueCreate(4, sizeof(prog_cmd_t));
    xVgaMutex    = xSemaphoreCreateMutex();

    if (!xInputQueue || !xProgCmdQueue || !xVgaMutex) {
        neorv32_uart0_puts("FATAL: queue/mutex creation failed\n");
        for (;;) ;
    }

    xActiveTask = NULL;
    register_cli_commands();

    if (xTaskCreate(t_uart_input, "uart", 128, NULL, 3, NULL) != pdPASS) {
        neorv32_uart0_puts("FATAL: uart task create failed\n");
        for (;;) ;
    }
    if (xTaskCreate(t_shell, "shell", 256, NULL, 2, NULL) != pdPASS) {
        neorv32_uart0_puts("FATAL: shell task create failed\n");
        for (;;) ;
    }
    if (xTaskCreate(t_status, "status", 128, NULL, 1, NULL) != pdPASS) {
        neorv32_uart0_puts("FATAL: status task create failed\n");
        for (;;) ;
    }

    neorv32_uart0_puts("Starting FreeRTOS scheduler...\n");
    vTaskStartScheduler();

    neorv32_uart0_puts("FATAL: scheduler returned\n");
    for (;;) ;
}
