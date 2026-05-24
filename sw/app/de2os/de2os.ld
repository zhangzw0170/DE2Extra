/* de2os.ld — Supplemental linker script for FreeRTOS RISC-V port
 *
 * Provides the IRQ stack required by portASM.S.
 * Included via USER_FLAGS -T after the main neorv32.ld.
 */

/* IRQ stack: 1KB at the end of DMEM, below the main stack */
__freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024;
