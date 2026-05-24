/*
 * DE2Extra — Phase 0 验证程序
 *
 * 功能:
 *   - LEDR[15:0]: 16-bit 跑马灯, 1秒跑完一轮
 *   - HEX3-0: 实时显示 LEDR[15:0] 的十六进制值
 *   - HEX7-6: 秒计数器 (00~FF, 每秒 +1)
 *   - HEX5-4: 始终显示 00
 *   - LEDG[7:0]: 秒计数器的二进制表示
 *   - LEDG[8]: 复位指示灯
 *   - UART 输出启动信息 + 定期心跳
 *
 * GPIO 位段分配 (32 位, 无重叠):
 *   [15:0]  → LEDR[15:0] + seg7_mapper → HEX0-3
 *   [23:16] → LEDG[7:0] + seg7_mapper → HEX4-5 (秒计数器)
 *   [31:24] → 保留给 lcd_status 协议 (必须为 0)
 */
#include <neorv32.h>

#define BAUD_RATE 115200

/*
 * 延时常量: 16 LEDs × ~62.5ms/LED ≈ 1s 一轮
 * RV32IMC -Os 每次循环约 4 cycles × 20ns = 80ns
 * 62.5ms / 80ns ≈ 781250, 取 800000
 */
#define DELAY_PER_LED 50000

int main(void) {
    neorv32_rte_setup();

    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("\n");
    neorv32_uart0_puts("========================================\n");
    neorv32_uart0_puts("  DE2Extra — NEORV32 RISC-V alive!\n");
    neorv32_uart0_puts("  CPU: RV32IMC + Zk*\n");
    neorv32_uart0_puts("  Board: DE2-115 (Cyclone IV E)\n");
    neorv32_uart0_puts("========================================\n");

    neorv32_gpio_dir_set(0xFFFFFFFF);

    uint32_t led_idx = 0;
    uint32_t seconds = 0;

    while (1) {
        /* LED 跑马灯: 单 bit 左移循环 */
        uint32_t led_pattern = 1u << led_idx;

        /* 组合 GPIO 输出:
         *   [15:0]  = led_pattern  → LEDR + HEX0-3
         *   [23:16] = seconds      → LEDG[7:0] 二进制 + HEX4-5
         *   [31:24] = 0            → lcd_status 保持 TESTING
         */
        neorv32_gpio_port_set(led_pattern
                            | (seconds << 16));

        led_idx++;
        if (led_idx >= 16) {
            led_idx = 0;
            seconds++;
        }

        for (volatile int d = 0; d < DELAY_PER_LED; d++) {
            /* busy wait */
        }

        if ((seconds & 0x0F) == 0) {
            neorv32_uart0_puts("tick ");
        }
    }

    return 0;
}
