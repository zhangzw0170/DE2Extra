/* de2shell_rtos.ld — linker-script extension for FreeRTOS on DE2Extra
 *
 * This file is passed in addition to the upstream NEORV32 linker script.
 * It parks large RTOS/UI buffers in SDRAM so the 16KB DMEM is left for
 * startup data, task metadata and stacks.
 *
 * NOTE:
 * GNU ld did not reliably honor an extra MEMORY region when this script was
 * layered on top of neorv32.ld, so the SDRAM sections are anchored with
 * absolute addresses instead.
 */

/* IRQ stack: 1KB at the end of DMEM, below the main stack */
__freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024;

/* Use a high SDRAM window well above the SDRAM-resident .text/.rodata image. */
__de2extra_sdram_base = 0x01900000;

SECTIONS
{
  .sdram_bss __de2extra_sdram_base (NOLOAD) : ALIGN(16)
  {
    __sdram_bss_start = .;
    *(.sdram_bss)
    *(.sdram_bss.*)
    . = ALIGN(16);
    __sdram_bss_end = .;
  }

  .freertos_heap (__de2extra_sdram_base + 0x00004000) (NOLOAD) : ALIGN(16)
  {
    __freertos_heap_start = .;
    KEEP(*(.freertos_heap))
    . = ALIGN(16);
    __freertos_heap_end = .;
  }
}
INSERT AFTER .heap;
