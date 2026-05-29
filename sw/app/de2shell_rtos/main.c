/* main.c -- de2shell_rtos: FreeRTOS-based de2shell
 *
 * SDRAM-executed shell firmware for DE2Extra V3.
 * Keeps the text terminal in VGA mode by default, reserves the last text row
 * for a live status bar, and launches de2shell programs as transient tasks.
 */

#include <neorv32.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "FreeRTOS_CLI.h"

#include "hw_build_info.h"
#include "sw_build_info.h"
#include "vga_hal.h"
#include "fb_hal.h"
#include "gpio_hal.h"
#include "board_status.h"
#include "ps2_decoder.h"

#define BAUD_RATE 115200
#define APP_BOOT_ADDR 0x01000000u
#define SDRAM_RESUME_MARKER_ADDR 0x018FFFF0u
#define SDRAM_RESUME_MAGIC 0x44523253u
#define SOFT_BOOT_SEQ_LEN 6u

#define PS2_MMIO_BASE ((volatile uint32_t *)0xF0008000u)
#define PS2_REG_DATA  0u
#define PS2_REG_STAT  1u
#define PS2_STAT_READY 0x01u
#define PS2_STATUS_TX_BUSY        0x00010000u
#define PS2_STATUS_TX_DONE        0x00020000u
#define PS2_STATUS_TX_ERROR       0x00040000u
#define PS2_STATUS_TX_RESP        0x00080000u
#define PS2_STATUS_TX_RESP_SHIFT  20u
#define PS2_STATUS_BUS_IDLE       0x10000000u
#define PS2_LED_SCROLL            0x01u
#define PS2_LED_NUM               0x02u
#define PS2_LED_CAPS              0x04u
#define PS2_RESP_ACK              0xfau
#define PS2_RESP_RESEND           0xfeu
#define PS2_HOST_TIMEOUT          250000u
#define PS2_POLL_BUDGET           8u

/* program_t is defined in vga_hal.h */
extern const program_t prog_hello;
extern const program_t prog_crypto;
extern const program_t prog_ps2;
extern const program_t prog_snake;
extern const program_t prog_life;
extern const program_t prog_info;
extern const program_t prog_monitor;
extern const program_t prog_demo;
extern const program_t prog_twm;
extern const program_t prog_conway_hw;
extern const program_t prog_pong_hw;
extern const program_t prog_ntt;

uint8_t last_ir_cmd = 0;

char cOutputBuffer[configCOMMAND_INT_MAX_OUTPUT_SIZE]
    __attribute__((section(".sdram_bss")));

typedef enum {
    PROG_SHELL = 0,
    PROG_HELLO,
    PROG_CRYPTO,
    PROG_PS2,
    PROG_SNAKE,
    PROG_LIFE,
    PROG_INFO,
    PROG_MONITOR,
    PROG_DEMO,
    PROG_WIN30,
    PROG_CONWAY_HW,
    PROG_PONG_HW,
    PROG_NTT,
    PROG_COUNT
} prog_id_t;

typedef enum {
    CMD_STOP = 0
} prog_cmd_t;

static const program_t *programs[PROG_COUNT] = {
    [PROG_SHELL]   = NULL,
    [PROG_HELLO]   = &prog_hello,
    [PROG_CRYPTO]  = &prog_crypto,
    [PROG_PS2]     = &prog_ps2,
    [PROG_SNAKE]   = &prog_snake,
    [PROG_LIFE]    = &prog_life,
    [PROG_INFO]    = &prog_info,
    [PROG_MONITOR] = &prog_monitor,
    [PROG_DEMO]    = &prog_demo,
    [PROG_WIN30]   = &prog_twm,
    [PROG_CONWAY_HW] = &prog_conway_hw,
    [PROG_PONG_HW]  = &prog_pong_hw,
    [PROG_NTT]      = &prog_ntt
};

static volatile prog_id_t active_prog = PROG_SHELL;
static volatile prog_id_t cli_launch_req = PROG_SHELL;
static volatile uint32_t g_dbg_code = 0xD000u;
static volatile uint32_t g_idle_count = 0u;
static volatile uint8_t g_vga_dump_req = 0u;
static volatile TickType_t g_vga_dump_period_ticks = 0;
static volatile TickType_t g_vga_dump_next_tick = 0;

static QueueHandle_t xInputQueue;
static QueueHandle_t xProgCmdQueue;
static SemaphoreHandle_t xVgaMutex;
static TaskHandle_t xActiveTask;
static const uint8_t s_soft_boot_seq[SOFT_BOOT_SEQ_LEN] = {0x00u, 'B', 'O', 'O', 'T', 0x00u};

static int utoa_local(char *buf, uint32_t val) {
    char tmp[11];
    int i = 0;
    char *start = buf;

    if (val == 0u) {
        buf[0] = '0';
        buf[1] = '\0';
        return 1;
    }

    while (val != 0u) {
        tmp[i++] = (char)('0' + (val % 10u));
        val /= 10u;
    }

    while (i > 0) {
        *buf++ = tmp[--i];
    }
    *buf = '\0';
    return (int)(buf - start);
}

static int strcpy_local(char *dst, const char *src) {
    int n = 0;
    while ((*dst++ = *src++) != '\0') {
        n++;
    }
    return n;
}

static int strcmp_local(const char *a, const char *b) {
    while ((*a != '\0') && (*a == *b)) {
        a++;
        b++;
    }
    return (int)((unsigned char)*a - (unsigned char)*b);
}

static int parse_u32_local(const char *s, uint32_t *out) {
    uint32_t val = 0u;

    if ((s == NULL) || (*s == '\0')) {
        return -1;
    }

    while (*s != '\0') {
        if ((*s < '0') || (*s > '9')) {
            return -1;
        }
        val = (val * 10u) + (uint32_t)(*s - '0');
        s++;
    }

    *out = val;
    return 0;
}

static int append_hw_build(char *buf) {
    char *p = buf;
    p += strcpy_local(p, "Hardware build: ");
    p += strcpy_local(p, HW_BUILD_TAG);
    *p++ = '\n';
    *p = '\0';
    return (int)(p - buf);
}

static int append_sw_build(char *buf) {
    char *p = buf;
    p += strcpy_local(p, "Software build: ");
    p += strcpy_local(p, SW_BUILD_TAG);
    *p++ = '\n';
    *p = '\0';
    return (int)(p - buf);
}

static void uart_put_char_sanitized(char c) {
    uint8_t uc = (uint8_t)c;
    if (uc == 0u) {
        neorv32_uart0_putc(' ');
    } else if ((uc >= 0x20u) && (uc < 0x7fu)) {
        neorv32_uart0_putc((char)uc);
    } else {
        neorv32_uart0_putc('.');
    }
}

static void uart_put_u32(uint32_t value) {
    char buf[11];
    (void)utoa_local(buf, value);
    neorv32_uart0_puts(buf);
}

static void uart_put_line(const char *s) {
    neorv32_uart0_puts(s);
    neorv32_uart0_putc('\n');
}

static void vga_dump_snapshot_locked(void) {
    int row;
    int col;

    neorv32_uart0_puts("\n[VGA SNAPSHOT ");
    uart_put_u32(board_status_uptime_seconds());
    neorv32_uart0_puts("s]\n");

    for (row = 0; row < VGA_ROWS; row++) {
        if (row < 10) {
            neorv32_uart0_putc('0');
        }
        uart_put_u32((uint32_t)row);
        neorv32_uart0_putc('|');
        for (col = 0; col < VGA_COLS; col++) {
            uart_put_char_sanitized(vga_read_char(col, row));
        }
        neorv32_uart0_putc('\n');
    }

    neorv32_uart0_puts("[END VGA SNAPSHOT]\n");
}

static uint8_t ps2_lock_mask(void) {
    uint8_t mask = 0u;

    if (ps2_dec_scroll_lock() != 0) {
        mask |= PS2_LED_SCROLL;
    }
    if (ps2_dec_num_lock() != 0) {
        mask |= PS2_LED_NUM;
    }
    if (ps2_dec_caps_lock() != 0) {
        mask |= PS2_LED_CAPS;
    }

    return mask;
}

static void dbg_set(uint32_t code, const char *msg) {
    g_dbg_code = code & 0xfffffff0u;
    gpio_write_out(g_dbg_code);
    if (msg != NULL) {
        neorv32_uart0_puts(msg);
    }
}

static void write_resume_marker(void) {
    neorv32_cpu_store_unsigned_word(SDRAM_RESUME_MARKER_ADDR + 0u, SDRAM_RESUME_MAGIC);
    neorv32_cpu_store_unsigned_word(SDRAM_RESUME_MARKER_ADDR + 4u, APP_BOOT_ADDR);
}

static void clear_resume_marker(void) {
    neorv32_cpu_store_unsigned_word(SDRAM_RESUME_MARKER_ADDR + 0u, 0u);
    neorv32_cpu_store_unsigned_word(SDRAM_RESUME_MARKER_ADDR + 4u, 0u);
}

static void bootloader_restart(void) __attribute__((noreturn));
static void bootloader_restart(void) {
    clear_resume_marker();
    neorv32_uart0_puts("\nBOOT: jump to bootloader\n");
    while (neorv32_uart0_tx_busy()) {
    }
    neorv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);
    neorv32_cpu_csr_write(CSR_MIE, 0u);
    asm volatile ("fence\nfence.i" ::: "memory");
    asm volatile ("li t0, %[bootrom]\n"
                  "jr t0\n"
                  :
                  : [bootrom] "i" (NEORV32_BOOTROM_BASE)
                  : "t0");
    __builtin_unreachable();
}

static int soft_boot_seq_feed(uint8_t byte, uint8_t *state) {
    if (byte == s_soft_boot_seq[*state]) {
        (*state)++;
        if (*state == SOFT_BOOT_SEQ_LEN) {
            *state = 0u;
            return 1;
        }
        return 0;
    }

    *state = (byte == s_soft_boot_seq[0]) ? 1u : 0u;
    return 0;
}

static configSTACK_DEPTH_TYPE active_prog_stack_words(prog_id_t pid) {
    switch (pid) {
        case PROG_CRYPTO:
        case PROG_INFO:
        case PROG_MONITOR:
        case PROG_NTT:
            return 640;
        case PROG_DEMO:
            return 896;
        case PROG_WIN30:
            return 1280;
        default:
            return 512;
    }
}

static int ps2_send_host_byte(volatile uint32_t *ps2, uint8_t byte, uint8_t *resp_out) {
    uint32_t timeout;

    ps2[PS2_REG_STAT] = PS2_STATUS_TX_DONE | PS2_STATUS_TX_ERROR | PS2_STATUS_TX_RESP;

    timeout = PS2_HOST_TIMEOUT;
    while (((ps2[PS2_REG_STAT] & PS2_STATUS_TX_BUSY) != 0u) && (timeout != 0u)) {
        timeout--;
    }
    if (timeout == 0u) {
        return -1;
    }

    ps2[3] = (uint32_t)byte;

    timeout = PS2_HOST_TIMEOUT;
    while (timeout != 0u) {
        uint32_t status = ps2[PS2_REG_STAT];
        if ((status & PS2_STATUS_TX_DONE) != 0u) {
            if (resp_out != NULL) {
                *resp_out = (uint8_t)((status >> PS2_STATUS_TX_RESP_SHIFT) & 0xffu);
            }
            if (((status & PS2_STATUS_TX_ERROR) != 0u) ||
                ((status & PS2_STATUS_TX_RESP) == 0u)) {
                return -1;
            }
            return 0;
        }
        timeout--;
    }

    return -1;
}

static int ps2_sync_leds(volatile uint32_t *ps2) {
    uint8_t resp = 0u;
    uint8_t led_mask = ps2_lock_mask();
    int attempt;

    for (attempt = 0; attempt < 2; attempt++) {
        if ((ps2_send_host_byte(ps2, 0xedu, &resp) == 0) && (resp == PS2_RESP_ACK) &&
            (ps2_send_host_byte(ps2, led_mask, &resp) == 0) && (resp == PS2_RESP_ACK)) {
            return 0;
        }
        if (resp != PS2_RESP_RESEND) {
            break;
        }
    }

    neorv32_uart0_puts("WARN: ps2 led sync failed\n");
    return -1;
}

#define PROG_CMD(name, pid)                                              \
static BaseType_t cli_##name(char *buf, size_t len, const char *cmd) {   \
    char *p = buf;                                                       \
    (void)cmd;                                                           \
    (void)len;                                                           \
    p += strcpy_local(p, "Starting " #name "...\r\n");                   \
    cli_launch_req = (pid);                                              \
    return pdFALSE;                                                      \
}

PROG_CMD(hello,   PROG_HELLO)
PROG_CMD(crypto,  PROG_CRYPTO)
PROG_CMD(ps2,     PROG_PS2)
PROG_CMD(snake,   PROG_SNAKE)
PROG_CMD(life,    PROG_LIFE)
PROG_CMD(info,    PROG_INFO)
PROG_CMD(monitor, PROG_MONITOR)
PROG_CMD(expdemo, PROG_DEMO)
PROG_CMD(win30,   PROG_WIN30)
PROG_CMD(conwayhw, PROG_CONWAY_HW)
PROG_CMD(ponghw,  PROG_PONG_HW)
PROG_CMD(ntt,     PROG_NTT)

static BaseType_t cli_stats(char *buf, size_t len, const char *cmd) {
    (void)cmd;
    (void)len;
    vTaskList(buf);
    return pdFALSE;
}

static BaseType_t cli_heapstat(char *buf, size_t len, const char *cmd) {
    char *p = buf;
    (void)cmd;
    (void)len;
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
    (void)cmd;
    (void)len;
    vTaskGetRunTimeStats(buf);
    return pdFALSE;
}

static BaseType_t cli_clear(char *buf, size_t len, const char *cmd) {
    (void)cmd;
    (void)len;
    vga_clear();
    vga_goto(0, 0);
    buf[0] = '\0';
    return pdFALSE;
}

static BaseType_t cli_vgadump(char *buf, size_t len, const char *cmd) {
    (void)cmd;
    (void)len;
    g_vga_dump_req = 1u;
    uart_put_line("vgadump: snapshot queued to UART");
    strcpy_local(buf, "vgadump:  snapshot queued to UART\r\n");
    return pdFALSE;
}

static BaseType_t cli_vgamon(char *buf, size_t len, const char *cmd) {
    const char *arg = cmd;
    uint32_t period_s = 2u;
    char *p = buf;

    (void)len;

    while ((*arg != '\0') && (*arg != ' ') && (*arg != '\t')) {
        arg++;
    }
    while ((*arg == ' ') || (*arg == '\t')) {
        arg++;
    }

    if ((*arg == '\0') || (strcmp_local(arg, "on") == 0)) {
        g_vga_dump_period_ticks = pdMS_TO_TICKS(period_s * 1000u);
    } else if (strcmp_local(arg, "off") == 0) {
        g_vga_dump_period_ticks = 0;
    } else if ((parse_u32_local(arg, &period_s) == 0) && (period_s >= 1u) && (period_s <= 60u)) {
        g_vga_dump_period_ticks = pdMS_TO_TICKS(period_s * 1000u);
    } else {
        strcpy_local(buf, "vgamon:   use 'vgamon', 'vgamon off' or 'vgamon <1..60>'\r\n");
        return pdFALSE;
    }

    g_vga_dump_next_tick = xTaskGetTickCount();

    if (g_vga_dump_period_ticks == 0) {
        uart_put_line("vgamon: disabled");
        strcpy_local(buf, "vgamon:   disabled\r\n");
    } else {
        p += strcpy_local(p, "vgamon:   every ");
        p += utoa_local(p, (uint32_t)(g_vga_dump_period_ticks / configTICK_RATE_HZ));
        p += strcpy_local(p, " s to UART\r\n");
        neorv32_uart0_puts("vgamon: every ");
        uart_put_u32((uint32_t)(g_vga_dump_period_ticks / configTICK_RATE_HZ));
        uart_put_line(" s to UART");
    }
    return pdFALSE;
}

static const CLI_Command_Definition_t cmd_hello_def =
    {"hello", "hello:    LED chaser\r\n", cli_hello, 0};
static const CLI_Command_Definition_t cmd_crypto_def =
    {"crypto", "crypto:   AES/SHA/SM4 CLI\r\n", cli_crypto, 0};
static const CLI_Command_Definition_t cmd_ps2_def =
    {"ps2", "ps2:      PS/2 keyboard test\r\n", cli_ps2, 0};
static const CLI_Command_Definition_t cmd_snake_def =
    {"snake", "snake:    Snake game\r\n", cli_snake, 0};
static const CLI_Command_Definition_t cmd_info_def =
    {"info", "info:     System dashboard\r\n", cli_info, 0};
static const CLI_Command_Definition_t cmd_expdemo_def =
    {"expdemo", "expdemo:  11 course labs\r\n", cli_expdemo, 0};

static const CLI_Command_Definition_t cmd_life_def =
    {"life", "life:     Conway's Game of Life\r\n", cli_life, 0};
static const CLI_Command_Definition_t cmd_conway_def =
    {"conwaylife", "conwaylife: Conway's Game of Life (alias)\r\n", cli_life, 0};
static const CLI_Command_Definition_t cmd_monitor_def =
    {"monitor", "monitor:  RISC-V monitor / asm\r\n", cli_monitor, 0};
static const CLI_Command_Definition_t cmd_riscvasm_def =
    {"riscvasm", "riscvasm:  monitor alias\r\n", cli_monitor, 0};
static const CLI_Command_Definition_t cmd_twm_def =
    {"twm", "twm:      Tiling window manager\r\n", cli_win30, 0};
static const CLI_Command_Definition_t cmd_conwayhw_def =
    {"conwayhw", "conwayhw: Hardware Conway (FPGA)\r\n", cli_conwayhw, 0};
static const CLI_Command_Definition_t cmd_ponghw_def =
    {"ponghw", "ponghw:   Hardware PONG (FPGA)\r\n", cli_ponghw, 0};
static const CLI_Command_Definition_t cmd_ntt_def =
    {"ntt", "ntt:      NTT accelerator CLI\r\n", cli_ntt, 0};

static const CLI_Command_Definition_t cmd_stats_def =
    {"stats", "stats:    Task list + stack HWM\r\n", cli_stats, 0};
static const CLI_Command_Definition_t cmd_heapstat_def =
    {"heapstat", "heapstat: Heap usage\r\n", cli_heapstat, 0};
static const CLI_Command_Definition_t cmd_cpustat_def =
    {"cpustat", "cpustat:  CPU usage per task\r\n", cli_cpustat, 0};
/* ── Pixel mode diagnostic (pxtest) ─────────────────────────────── */
#define PX_BASE       ((volatile uint32_t *)0xF0000000u)
#define PX_REG_MODE   (0x7000u / 4u)
#define PX_REG_FBBASE (0x7004u / 4u)
#define PX_REG_STATUS (0x7008u / 4u)
#define PX_REG_DBG0   (0x700Cu / 4u)
#define PX_REG_DBG1   (0x7010u / 4u)
#define PX_REG_DBG2   (0x7014u / 4u)
#define PX_REG_DBG3   (0x7018u / 4u)
#define PX_REG_SAMP0  (0x701Cu / 4u)
#define PX_REG_SAMP1  (0x7020u / 4u)
#define PX_REG_SAMP2  (0x7024u / 4u)
#define PX_REG_SAMP3  (0x7028u / 4u)
#define PX_FB         ((volatile uint8_t *)0x01800000u)
#define PX_FB_W       640
#define PX_FB_H       480

static void px_uart_hex(uint32_t v) {
    static const char hex[] = "0123456789ABCDEF";
    for (int s = 28; s >= 0; s -= 4)
        neorv32_uart0_putc(hex[(v >> s) & 0xf]);
}

static void px_dump(const char *label) {
    neorv32_uart0_puts(label);
    neorv32_uart0_puts(" MODE=");  px_uart_hex(PX_BASE[PX_REG_MODE]);
    neorv32_uart0_puts(" FB=");    px_uart_hex(PX_BASE[PX_REG_FBBASE]);
    neorv32_uart0_puts(" ST=");    px_uart_hex(PX_BASE[PX_REG_STATUS]);
    neorv32_uart0_puts("\n  D0=");  px_uart_hex(PX_BASE[PX_REG_DBG0]);
    neorv32_uart0_puts(" D1=");    px_uart_hex(PX_BASE[PX_REG_DBG1]);
    neorv32_uart0_puts(" D2=");    px_uart_hex(PX_BASE[PX_REG_DBG2]);
    neorv32_uart0_puts(" D3=");    px_uart_hex(PX_BASE[PX_REG_DBG3]);
    neorv32_uart0_puts("\n  S0=");  px_uart_hex(PX_BASE[PX_REG_SAMP0]);
    neorv32_uart0_puts(" S1=");    px_uart_hex(PX_BASE[PX_REG_SAMP1]);
    neorv32_uart0_puts(" S2=");    px_uart_hex(PX_BASE[PX_REG_SAMP2]);
    neorv32_uart0_puts(" S3=");    px_uart_hex(PX_BASE[PX_REG_SAMP3]);
    neorv32_uart0_putc('\n');
}

static BaseType_t cli_pxtest(char *buf, size_t len, const char *cmd) {
    (void)cmd; (void)len;
    char *p = buf;

    neorv32_uart0_puts("\n=== PXTEST: VGA pixel mode diagnostic ===\n");

    /* Phase 1: Test pattern (bypasses SDRAM) */
    neorv32_uart0_puts("\n-- Phase 1: test pattern (no SDRAM) --\n");
    PX_BASE[PX_REG_FBBASE] = 0x01800000u;
    PX_BASE[PX_REG_MODE]   = 0x00000003u;  /* mode_en=1, testpat=1 */
    px_dump("  after enable");
    neorv32_uart0_puts("  => Check monitor: should see color bars.\n");
    neorv32_uart0_puts("  => Waiting 3 s...\n");
    vTaskDelay(pdMS_TO_TICKS(3000));

    /* Phase 2: Read debug registers after 3s of test pattern */
    neorv32_uart0_puts("\n-- Phase 2: debug regs after test pattern --\n");
    px_dump("  ");
    {
        uint32_t d0 = PX_BASE[PX_REG_DBG0];
        uint32_t fsm = d0 & 0x7;
        uint32_t line_evt = d0 >> 16;
        neorv32_uart0_puts("  FSM=");
        neorv32_uart0_putc('0' + (char)fsm);
        neorv32_uart0_puts(" line_events=");
        px_uart_hex(line_evt);
        neorv32_uart0_puts(fsm == 0 ? " (IDLE)" :
                           fsm == 1 ? " (REQ)" :
                           fsm == 2 ? " (POP)" :
                           fsm == 3 ? " (NEXT_BURST)" :
                           fsm == 4 ? " (LINE_DONE)" : " (?)");
        neorv32_uart0_putc('\n');
    }

    /* Phase 3: Switch to SDRAM mode, write gradient */
    neorv32_uart0_puts("\n-- Phase 3: SDRAM framebuffer with gradient --\n");
    PX_BASE[PX_REG_MODE] = 0x00000001u;  /* mode_en=1, testpat=0 */
    for (int y = 0; y < PX_FB_H; y++) {
        for (int x = 0; x < PX_FB_W; x++) {
            uint8_t r = (uint8_t)(x * 7u / PX_FB_W);
            uint8_t g = (uint8_t)(y * 7u / PX_FB_H);
            uint8_t b = (uint8_t)((x + y) & 0x3);
            PX_FB[y * PX_FB_W + x] = (uint8_t)((r << 5) | (g << 2) | b);
        }
    }
    px_dump("  after gradient write");
    neorv32_uart0_puts("  => Check monitor: should see color gradient.\n");
    neorv32_uart0_puts("  => Waiting 3 s...\n");
    vTaskDelay(pdMS_TO_TICKS(3000));

    /* Phase 4: Debug regs after SDRAM mode */
    neorv32_uart0_puts("\n-- Phase 4: debug regs after SDRAM mode --\n");
    px_dump("  ");
    {
        uint32_t d2 = PX_BASE[PX_REG_DBG2];
        uint32_t d3 = PX_BASE[PX_REG_DBG3];
        neorv32_uart0_puts("  req_count=");   px_uart_hex(d2);
        neorv32_uart0_puts(" valid_count=");  px_uart_hex(d3);
        if (d2 == 0) {
            neorv32_uart0_puts(" *** NO SDRAM REQUESTS — fetch FSM never triggered!\n");
        } else if (d3 == 0) {
            neorv32_uart0_puts(" *** NO VALID DATA — SDRAM not returning data!\n");
        } else if (d3 < d2) {
            neorv32_uart0_puts(" *** DROPPED REQUESTS — SDRAM bandwidth issue?\n");
        } else {
            neorv32_uart0_puts(" (SDRAM reads active)\n");
        }
    }

    /* Phase 5: Restore text mode */
    neorv32_uart0_puts("\n-- Phase 5: restore text mode --\n");
    PX_BASE[PX_REG_MODE] = 0x00000000u;
    vga_cursor_show(1);
    neorv32_uart0_puts("  pixel mode disabled.\n");
    neorv32_uart0_puts("=== PXTEST done ===\n\n");

    p += strcpy_local(p, "pxtest:  see UART for full results\r\n");
    return pdFALSE;
}

static const CLI_Command_Definition_t cmd_pxtest_def =
    {"pxtest", "pxtest:   VGA pixel mode diagnostic\r\n", cli_pxtest, 0};

static const CLI_Command_Definition_t cmd_clear_def =
    {"clear", "clear:    Clear VGA screen\r\n", cli_clear, 0};
static const CLI_Command_Definition_t cmd_vgadump_def =
    {"vgadump", "vgadump:  dump current VGA text screen to UART\r\n", cli_vgadump, 0};
static const CLI_Command_Definition_t cmd_vgamon_def =
    {"vgamon", "vgamon:   periodic VGA dump to UART (default 2s)\r\n", cli_vgamon, -1};

static void register_cli_commands(void) {
    FreeRTOS_CLIRegisterCommand(&cmd_hello_def);
    FreeRTOS_CLIRegisterCommand(&cmd_crypto_def);
    FreeRTOS_CLIRegisterCommand(&cmd_ps2_def);
    FreeRTOS_CLIRegisterCommand(&cmd_snake_def);
    FreeRTOS_CLIRegisterCommand(&cmd_info_def);
    FreeRTOS_CLIRegisterCommand(&cmd_expdemo_def);
    FreeRTOS_CLIRegisterCommand(&cmd_life_def);
    FreeRTOS_CLIRegisterCommand(&cmd_conway_def);
    FreeRTOS_CLIRegisterCommand(&cmd_monitor_def);
    FreeRTOS_CLIRegisterCommand(&cmd_riscvasm_def);
    FreeRTOS_CLIRegisterCommand(&cmd_twm_def);
    FreeRTOS_CLIRegisterCommand(&cmd_conwayhw_def);
    FreeRTOS_CLIRegisterCommand(&cmd_ponghw_def);
    FreeRTOS_CLIRegisterCommand(&cmd_ntt_def);
    FreeRTOS_CLIRegisterCommand(&cmd_pxtest_def);
    FreeRTOS_CLIRegisterCommand(&cmd_stats_def);
    FreeRTOS_CLIRegisterCommand(&cmd_heapstat_def);
    FreeRTOS_CLIRegisterCommand(&cmd_cpustat_def);
    FreeRTOS_CLIRegisterCommand(&cmd_clear_def);
    FreeRTOS_CLIRegisterCommand(&cmd_vgadump_def);
    FreeRTOS_CLIRegisterCommand(&cmd_vgamon_def);
}

void freertos_risc_v_application_interrupt_handler(void) {
    dbg_set(0xDE10u, "DBG: application interrupt\n");
}

void freertos_risc_v_application_exception_handler(void) {
    dbg_set(0xDEE0u, "DBG: exception\n");
    neorv32_uart0_puts("!!! FreeRTOS exception !!!\n");
    for (;;) {
    }
}

void vApplicationMallocFailedHook(void) {
    dbg_set(0xDEF0u, "DBG: malloc failed\n");
    neorv32_uart0_puts("FATAL: malloc failed\n");
    for (;;) {
    }
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    dbg_set(0xDED0u, "DBG: stack overflow\n");
    neorv32_uart0_puts("FATAL: stack overflow '");
    neorv32_uart0_puts(pcTaskName);
    neorv32_uart0_puts("'\n");
    for (;;) {
    }
}

void vApplicationIdleHook(void) {
    g_idle_count++;
    if ((g_idle_count & 0x3fffu) == 0u) {
        gpio_write_out(g_dbg_code | ((g_idle_count >> 14) & 0x0fu));
    }
}

static void reset_display_mode(void) {
    vga_reset_scroll_region();
    fb_shutdown();
    vga_cursor_show(1);
}

static void shell_prompt(void) {
    vga_puts("RTOS > ", VGA_GREEN);
}

#define SHELL_LINE_SIZE 80
#define CLI_OUTPUT_BUF_SIZE configCOMMAND_INT_MAX_OUTPUT_SIZE
static char shell_line[SHELL_LINE_SIZE];
static int shell_line_pos;

static void shell_reset_line(void) {
    shell_line_pos = 0;
    shell_line[0] = '\0';
}

static void shell_init_screen(void) {
    char hw_line[64];
    char sw_line[64];

    reset_display_mode();
    xSemaphoreTake(xVgaMutex, portMAX_DELAY);
    vga_set_scroll_region(0, VGA_ROWS - 2);
    vga_clear();
    vga_goto(0, 0);
    vga_puts("DE2Extra Shell (FreeRTOS)\n", VGA_CYAN);
    append_hw_build(hw_line);
    append_sw_build(sw_line);
    vga_puts(hw_line, VGA_YELLOW);
    vga_puts(sw_line, VGA_YELLOW);
    vga_puts("Type 'help' for commands\n", VGA_GRAY);
    shell_reset_line();
    shell_prompt();
    xSemaphoreGive(xVgaMutex);
}

static void render_status_bar(void) {
    char up_buf[16];
    uint32_t up_s = board_status_uptime_seconds();
    const char *prog_name = "Shell";
    int saved_col = vga_col();
    int saved_row = vga_row();

    if ((active_prog > PROG_SHELL) && (active_prog < PROG_COUNT) && (programs[active_prog] != NULL)) {
        prog_name = programs[active_prog]->name;
    }

    utoa_local(up_buf, up_s);

    vga_goto(0, VGA_ROWS - 1);
    vga_clear_line(VGA_ROWS - 1, VGA_WHITE);
    vga_goto(0, VGA_ROWS - 1);
    vga_puts("DE2Extra RTOS", VGA_CYAN);
    vga_puts(" | ", VGA_GRAY);
    vga_puts(prog_name, VGA_GREEN);
    vga_puts(" | up ", VGA_GRAY);
    vga_puts(up_buf, VGA_WHITE);
    vga_puts("s", VGA_GRAY);
    vga_goto(saved_col, saved_row);
}

static void exit_active_program(void) {
    reset_display_mode();
    active_prog = PROG_SHELL;
    xActiveTask = NULL;
    vTaskDelete(NULL);
}

static void t_uart_input(void *pv) {
    char c;
    ps2_key_t key;
    volatile uint32_t * const ps2 = PS2_MMIO_BASE;
    uint8_t last_lock_mask;
    uint8_t soft_boot_state = 0u;

    (void)pv;
    dbg_set(0xD100u, "DBG: task uart\n");
    ps2_dec_init();
    last_lock_mask = ps2_lock_mask();
    (void)ps2_sync_leds(ps2);

    for (;;) {
        if (neorv32_uart0_char_received()) {
            uint8_t raw_uart = (uint8_t)neorv32_uart0_getc();
            if (soft_boot_seq_feed(raw_uart, &soft_boot_state) != 0) {
                bootloader_restart();
            }
            c = (char)raw_uart;
            (void)xQueueSend(xInputQueue, &c, 0);
        }

        {
            uint32_t budget = PS2_POLL_BUDGET;
            if (active_prog != PROG_PS2 && active_prog != PROG_WIN30 && active_prog != PROG_PONG_HW) {
                while (((ps2[PS2_REG_STAT] & PS2_STAT_READY) != 0u) && (budget != 0u)) {
                    uint8_t raw = (uint8_t)ps2[PS2_REG_DATA];
                    budget--;
                    if (ps2_dec_feed(raw, &key)) {
                        uint8_t lock_mask = ps2_lock_mask();
                        if (lock_mask != last_lock_mask) {
                            (void)ps2_sync_leds(ps2);
                            last_lock_mask = ps2_lock_mask();
                        }
                        if (key.is_press && key.has_ascii) {
                            c = (char)key.ascii;
                            (void)xQueueSend(xInputQueue, &c, 0);
                        }
                    }
                }
            }
        }

        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

static void t_active_prog(void *pv) {
    char c;
    prog_cmd_t cmd;

    (void)pv;

    for (;;) {
        const program_t *prog = programs[active_prog];

        if (xQueueReceive(xProgCmdQueue, &cmd, 0) == pdTRUE) {
            (void)cmd;
            exit_active_program();
        }

        if (xQueueReceive(xInputQueue, &c, 0) == pdTRUE) {
            if (c == 27) {
                exit_active_program();
            }
            if ((prog != NULL) && (prog->input != NULL)) {
                xSemaphoreTake(xVgaMutex, portMAX_DELAY);
                prog->input(c);
                xSemaphoreGive(xVgaMutex);
            }
        }

        if ((prog != NULL) && (prog->update != NULL)) {
            xSemaphoreTake(xVgaMutex, portMAX_DELAY);
            prog->update();
            xSemaphoreGive(xVgaMutex);
        }

        if ((prog != NULL) && (prog->finish != NULL) && prog->finish()) {
            exit_active_program();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
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
    char dummy;
    const program_t *prog;

    if ((pid <= PROG_SHELL) || (pid >= PROG_COUNT)) {
        return;
    }

    prog = programs[pid];
    if (prog == NULL) {
        return;
    }

    if (xActiveTask != NULL) {
        stop_active_program();
    }

    active_prog = pid;

    while (xQueueReceive(xInputQueue, &dummy, 0) == pdTRUE) {
    }

    xSemaphoreTake(xVgaMutex, portMAX_DELAY);
    if (prog->init != NULL) {
        prog->init();
    }
    xSemaphoreGive(xVgaMutex);

    if (xTaskCreate(t_active_prog, "prog", active_prog_stack_words(pid), NULL, 2, &xActiveTask) != pdPASS) {
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
    char c;

    (void)pv;
    dbg_set(0xD200u, "DBG: task shell\n");
    shell_reset_line();
    shell_init_screen();

    for (;;) {
        if (active_prog != PROG_SHELL) {
            vTaskDelay(pdMS_TO_TICKS(50));
            if (active_prog == PROG_SHELL) {
                shell_init_screen();
            }
            continue;
        }

        if (xQueueReceive(xInputQueue, &c, pdMS_TO_TICKS(20)) != pdTRUE) {
            continue;
        }

        xSemaphoreTake(xVgaMutex, portMAX_DELAY);

        if ((c == '\r') || (c == '\n')) {
            shell_line[shell_line_pos] = '\0';
            vga_putc('\n', VGA_WHITE);

            if (shell_line_pos > 0) {
                BaseType_t more;
                do {
                    more = FreeRTOS_CLIProcessCommand(shell_line, cOutputBuffer, CLI_OUTPUT_BUF_SIZE);
                    vga_puts(cOutputBuffer, VGA_WHITE);
                } while (more != pdFALSE);

                if (cli_launch_req != PROG_SHELL) {
                    prog_id_t pid = cli_launch_req;
                    cli_launch_req = PROG_SHELL;
                    shell_reset_line();
                    xSemaphoreGive(xVgaMutex);
                    launch_program(pid);
                    continue;
                }
            }

            shell_reset_line();
            shell_prompt();
        } else if ((c == '\b') || (c == 0x7fu)) {
            if (shell_line_pos > 0) {
                shell_line_pos--;
                shell_line[shell_line_pos] = '\0';
                vga_putc('\b', VGA_WHITE);
            }
        } else if ((c >= ' ') && (c < 0x7fu) && (shell_line_pos < (SHELL_LINE_SIZE - 1))) {
            shell_line[shell_line_pos++] = c;
            shell_line[shell_line_pos] = '\0';
            vga_putc(c, VGA_WHITE);
        }

        xSemaphoreGive(xVgaMutex);
    }
}

static void t_status(void *pv) {
    (void)pv;
    dbg_set(0xD300u, "DBG: task status\n");

    for (;;) {
        TickType_t now = xTaskGetTickCount();
        int do_vga_dump = 0;

        if (g_vga_dump_req != 0u) {
            g_vga_dump_req = 0u;
            do_vga_dump = 1;
        } else if ((g_vga_dump_period_ticks != 0) && (now >= g_vga_dump_next_tick)) {
            g_vga_dump_next_tick = now + g_vga_dump_period_ticks;
            do_vga_dump = 1;
        }

        xSemaphoreTake(xVgaMutex, portMAX_DELAY);
        render_status_bar();
        if (do_vga_dump != 0) {
            vga_dump_snapshot_locked();
        }
        xSemaphoreGive(xVgaMutex);

        board_status_set_program((uint8_t)active_prog, BOARD_STATE_LIVE, 0u, 0u);
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}

int main(void) {
    extern void freertos_risc_v_trap_handler(void);

    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    dbg_set(0xD010u, "BOOT: main()\n");
    neorv32_uart0_puts("\n=== de2shell_rtos: FreeRTOS on NEORV32 ===\n");
    append_hw_build(cOutputBuffer);
    neorv32_uart0_puts(cOutputBuffer);
    append_sw_build(cOutputBuffer);
    neorv32_uart0_puts(cOutputBuffer);
    neorv32_uart0_puts("UART debug mode: VGA mirroring disabled; use vgadump/vgamon for screen capture.\n");

    gpio_write_out(0u);
    board_status_init();
    vga_set_serial_mirror(0);
    vga_init();
    reset_display_mode();
    write_resume_marker();

    neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)freertos_risc_v_trap_handler);

    xInputQueue = xQueueCreate(64, sizeof(char));
    xProgCmdQueue = xQueueCreate(4, sizeof(prog_cmd_t));
    xVgaMutex = xSemaphoreCreateMutex();

    if ((xInputQueue == NULL) || (xProgCmdQueue == NULL) || (xVgaMutex == NULL)) {
        dbg_set(0xD020u, "FATAL: queue/mutex creation failed\n");
        for (;;) {
        }
    }
    dbg_set(0xD030u, "DBG: queues ok\n");

    xActiveTask = NULL;
    register_cli_commands();
    dbg_set(0xD040u, "DBG: cli ok\n");

    if (xTaskCreate(t_uart_input, "uart", 256, NULL, 1, NULL) != pdPASS) {
        dbg_set(0xD050u, "FATAL: uart task create failed\n");
        for (;;) {
        }
    }
    if (xTaskCreate(t_shell, "shell", 640, NULL, 3, NULL) != pdPASS) {
        dbg_set(0xD060u, "FATAL: shell task create failed\n");
        for (;;) {
        }
    }
    if (xTaskCreate(t_status, "status", 256, NULL, 1, NULL) != pdPASS) {
        dbg_set(0xD070u, "FATAL: status task create failed\n");
        for (;;) {
        }
    }
    dbg_set(0xD080u, "DBG: tasks ok\n");

    neorv32_uart0_puts("Starting FreeRTOS scheduler...\n");
    dbg_set(0xD090u, "DBG: scheduler start\n");
    vTaskStartScheduler();

    dbg_set(0xD0F0u, "FATAL: scheduler returned\n");
    for (;;) {
    }
}
