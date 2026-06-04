/* de2shell_rtos.ld — linker-script extension for FreeRTOS on DE2Extra
 *
 * This file is passed in addition to the upstream NEORV32 linker script.
 * It parks large RTOS/UI buffers in SDRAM so the 16KB DMEM is left for
 * startup data, task metadata and stacks.
 *
 * Strategy: define a `sdram` MEMORY region and use INSERT AFTER .heap
 * to include our sections in the output.  The `> sdram` directive tells
 * the linker to assign VMAs from the SDRAM region.
 */

/* IRQ stack: 1KB at the end of DMEM, below the main stack */
__freertos_irq_stack_top = ORIGIN(ram) + LENGTH(ram) - 1024;

MEMORY
{
  sdram (rwx) : ORIGIN = 0x01900000, LENGTH = 0x07000000
}

SECTIONS
{
  .sdram_bss (NOLOAD) : ALIGN(16)
  {
    __sdram_bss_start = .;
    *(.sdram_bss)
    *(.sdram_bss.*)
    . = ALIGN(16);
    __sdram_bss_end = .;
  } > sdram

  .freertos_heap (NOLOAD) : ALIGN(16)
  {
    __freertos_heap_start = .;
    KEEP(*(.freertos_heap))
    . = ALIGN(16);
    __freertos_heap_end = .;
  } > sdram
}
INSERT AFTER .heap;
