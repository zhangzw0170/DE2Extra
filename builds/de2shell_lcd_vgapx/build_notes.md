# de2shell LCD + VGA pixel mode build
# Date: 2026-05-25 10:27
# SOF: de2shell_lcd_vgapx.sof
# Top entity: de2_115_top (par/de2extra)

## Firmware
- App: sw/app/de2shell
- IMEM image: 62,872 bytes / 65,536 bytes (95.9%, 2,664 remaining)
- text=62,792 data=80 bss=15,132

## Hardware resources
- Total LEs: 27,508 / 114,480 (24%)
- Combinational: 26,196 (23%)
- Registers: 9,239 (8%)
- Memory bits: 937,536 / 3,981,312 (24%)
- Multipliers: 19 / 532 (4%)
- PLLs: 1 / 4 (25%)
- Pins: 210 / 529 (40%)

## Build time
- Docker firmware: ~10s
- Quartus total: 25m57s
  - Fitter placement: 1m25s
  - Fitter routing round 1: failed (congestion 92% at X58_Y37~X68_Y48)
  - Fitter routing round 2 (high effort): ~20m
  - Assembler: ~1m
  - Timing Analysis: 18s
- Total: ~26m

## Key changes from previous build
- lcd_hal.c: replaced unreliable busy-polling with fixed delays (2ms/cmd, 1ms/char)
- fb_hal.c: added SDL_PollEvent for LOCAL_BUILD; NEORV32 backend now writes VGA pixel mode registers
- de2_115_top.vhd: added numeric_std; VGA pixel mode address decode (0x1F80+ offset)
- win30_desk.c: SDL2 keyboard events; shell command renamed to "startui"
- de2shell/main.c: "win30" → "startui" command

## Known issues
- Fitter congestion from VGA pixel mode address decode logic — ~4,500 extra LEs, long compile time
- IMEM nearly full at 95.9%
- LCD fix (busy-polling → fixed delay) needs board verification
