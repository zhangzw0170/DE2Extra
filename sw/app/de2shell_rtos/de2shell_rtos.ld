/* de2shell_rtos.ld — Supplemental linker script for FreeRTOS RISC-V port
 *
 * Provides the IRQ stack required by portASM.S.
 * Included via USER_FLAGS -T after the main neorv32.ld.
 */

/* IRQ stack: 1KB at the end of DMEM, below the main stack */
__freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024;

__de2_framebuffer_base   = 0x01800000;
__de2_freertos_heap_base = 0x01900000;

SECTIONS
{
  .freertos_heap __de2_freertos_heap_base (NOLOAD) : ALIGN(16)
  {
    KEEP(*(.freertos_heap))
  }

  /* Large BSS buffers in SDRAM to avoid DMEM overflow */
  .sdram_bss 0x01904000 (NOLOAD) : ALIGN(16)
  {
    *(.sdram_bss)
  }
}
