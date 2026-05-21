/*
 * DE2Extra — Hello World + LED 闪烁心跳
 *
 * Phase 0 验证程序:
 *   - LEDR[0..17] 循环流水灯
 *   - 七段管显示递增计数器 (GPIO[19:4])
 *   - UART 输出 "DE2Extra alive!"
 *
 * NEORV32 boot mode 2: 程序烧入 IMEM image, 上电即跑。
 */
#include <neorv32.h>

#define BAUD_RATE 115200

int main(void) {
    /* 安装安全异常处理器 */
    neorv32_rte_setup();

    /* 初始化 UART0 */
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("\n");
    neorv32_uart0_puts("========================================\n");
    neorv32_uart0_puts("  DE2Extra — NEORV32 RISC-V alive!\n");
    neorv32_uart0_puts("  CPU: RV32IMC + Zfinx + Zk*\n");
    neorv32_uart0_puts("  Board: DE2-115 (Cyclone IV E)\n");
    neorv32_uart0_puts("========================================\n");

    /* GPIO: 低 18 位输出 (LEDR), 位 19..4 输出 (七段管) */
    neorv32_gpio_dir_set(0x000FFFFF);

    uint32_t counter = 0;

    while (1) {
        /* LED 流水灯: GPIO[17:0] */
        uint32_t led_pattern = 1 << (counter % 18);
        neorv32_gpio_port_set(led_pattern);

        /* 七段管计数器: GPIO[19:4], 每 16 次循环递增 */
        if ((counter & 0xF) == 0) {
            uint32_t hex_counter = (counter >> 4) & 0xFFFF;
            neorv32_gpio_port_set(led_pattern | (hex_counter << 4));
        }

        counter++;

        /* 简单延时 (~10ms @50MHz) */
        for (volatile int d = 0; d < 250000; d++) {
            /* busy wait */
        }

        /* 每 256 次循环输出一次心跳 */
        if ((counter & 0xFF) == 0) {
            neorv32_uart0_puts("tick ");
        }
    }

    return 0;  /* never reached */
}
