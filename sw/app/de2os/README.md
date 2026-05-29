# de2os — DEPRECATED

This firmware is superseded by `sw/app/de2shell_rtos/`.

- `de2os` was an early V3 prototype with 3 tasks (t_gui, t_crypto, t_input)
- `de2shell_rtos` is the active V3 firmware with FreeRTOS+CLI, 21 commands, VGA shell, PS/2 keyboard, and all hardware engines integrated
- The FreeRTOS submodule at `sw/app/de2os/freertos/` is shared by both firmwares — do not delete it
