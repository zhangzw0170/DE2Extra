# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEORV32 (RISC-V) soft-core SoC on DE2-115 (Cyclone IV E EP4CE115F29C7), running bare-metal C firmware. Target: turn the DE2-115 into a complete computer with VGA terminal, PS/2 keyboard, SDRAM, crypto accelerators, and games.

**NEORV32 version**: submodule pinned at release tag **v1.13.1** (2026-05-14). Do not track `main` branch — always use a release tag for stability.

## Build System

### One-command build (Git Bash on Windows)
```bash
./build.sh app/de2shell            # firmware + Quartus compile
./build.sh --flash app/de2shell    # compile + JTAG program
./build.sh --flash-only            # only flash existing par/de2extra.sof
```

**Do not run `bash build.sh` from PowerShell** — it falls through to WSL and fails. Use Git Bash.

`build.sh` runs 3 stages: (1) Docker (`de2extra-builder`) cross-compiles RISC-V firmware → `neorv32_imem_image.vhd`, (2) copies IMEM image to `src/rtl/`, (3) Quartus compile → `par/de2extra.sof`.

### Manual build
1. Firmware: `cd sw/app/<name> && make clean all image NEORV32_HOME=../../../neorv32`
2. Copy: `cp neorv32/rtl/core/neorv32_imem_image.vhd src/rtl/`
3. Quartus: open `par/de2extra.qpf`, Ctrl+L
4. Program: Quartus Programmer → `par/de2extra.sof`

### Software local test (no FPGA needed)
```bash
cd sw/app/de2shell && make local   # compiles with host gcc, -DLOCAL_BUILD (needs SDL2 via scoop)
```

### Quartus VHDL version

NEORV32 requires **VHDL-2008** (uses `std_ulogic`, record types). Set once: Assignments → Settings → Compiler Settings → VHDL Input → VHDL 2008.

## Architecture

```
de2_115_top.vhd (only entity that knows board pins)
├── clk_rst_gen          PLL: 50MHz (CPU/WB) + 100MHz (SDRAM) + phase-shifted DRAM_CLK
├── neorv32_wrapper      CPU config wrapper (55 generics, std_ulogic ↔ std_logic conversion)
│   └── neorv32_top      RISC-V core (RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh/Zksed/Zksh)
│       ├── IMEM         64KB via M9K block RAM (neorv32_imem_rom.vhd, init from MIF)
│       ├── DMEM         16KB
│       ├── XBUS         Wishbone external bus master (timeout 2048 cycles), supports burst cti/tag signals
│       └── Built-in     UART0 (115200), GPIO(32), TRNG, CLINT, OCD
├── wb_intercon          1-master, 9-slave address decoder (combinational)
│   ├── s0: sdram_ctrl   0x01000000 (128MB, 100MHz state machine)
│   ├── s1: vga_text_terminal  0xF0000000 (16-bit reg IF, 80×25 text mode + pixel mode via SDRAM FB)
│   ├── s2: ps2_controller    0xF0002000 (scancode + IRQ)
│   ├── s3: ir_nec_wb         0xF0009000 (NEC IR decoder)
│   ├── s4: ntt_sdf           0xF000C000 (NTT accelerator — compiles clean, deferred to V3)
│   ├── s5: lcd_wb            0xF0008000 (LCD Wishbone controller)
│   ├── s6: timer_wb          0xF0004000 (Timer)
│   ├── s7: intc_wb           0xF0006000 (Interrupt controller)
│   └── s8: expdemo_wb        0xF000D000 (Hardware experiment multiplexer, 11 experiments, board verified ✅)
├── seg7_mapper (×2)     GPIO[23:0] → HEX0–HEX7
├── lcd_status / lcd_debug  HD44780 16×2 LCD (muxed by SW16)
├── uart_jtag_bridge     UART TX → JTAG UART IP (view output in Quartus System Console)
└── jtag_uart_0           Platform Designer IP (Avalon JTAG UART)
```

### Address Map
| Base | Peripheral | Size | Bus width |
|------|-----------|------|-----------|
| 0x00000000 | IMEM | 64KB | 32-bit |
| 0x80000000 | DMEM | 16KB | 32-bit |
| 0x01000000 | SDRAM | 128MB | 32-bit |
| 0xF0000000 | VGA text terminal + pixel mode | 8KB | 16-bit |
| 0xF0002000 | PS/2 keyboard | 4KB | 32-bit |
| 0xF0004000 | Timer (reserved) | 4KB | 32-bit |
| 0xF0006000 | INTC (reserved) | 4KB | 32-bit |
| 0xF0008000 | LCD | 4KB | 32-bit |
| 0xF0009000 | IR receiver | 4KB | 32-bit |
| 0xF000A000 | DDS (reserved) | 4KB | 32-bit |
| 0xF000B000 | SD card (reserved) | 4KB | 32-bit |
| 0xF000C000 | NTT accelerator | 4KB | 32-bit |
| 0xF000D000 | ExpDemo | 4KB | 32-bit |

Address constants: `src/rtl/lib/de2extra_pkg.vhd`.

Note: **NTT accelerator** (`ntt_sdf.vhd`) compiles clean and is instantiated in `wb_intercon` + both top entities. Deferred to V3 for board verification. The C driver (`sw/app/de2shell/ntt.c`) exists with dual-mode (LOCAL_BUILD SW reference / NEORV32 HW MMIO), verified in LOCAL_BUILD.

Note: **ExpDemo** is instantiated in `de2_115_top.vhd` (not in de2os_top.vhd). It wraps 11 experiment adapters with output/peripheral multiplexing. Board verified in V2.

Note: **VGA pixel mode** (`vga_pixel_ctrl.vhd`) is instantiated inside `vga_text_terminal`. It reads a framebuffer from SDRAM and displays 640×480@60Hz RGB565. Used by Win 3.0 GUI (`startui` command) and screenshot tools. SDL2-verified; deferred to V3 for VGA cable board test.

### Software Apps

| App | Location | Description |
|-----|----------|-------------|
| de2shell | `sw/app/de2shell/` | Main shell: command history, memtest, crypto, snake, life, pong, dashboard, VGA/PS2/IR HALs |
| crypto_cli | `sw/app/crypto_cli/` | Standalone AES/SHA/SM4 CLI (linked into de2shell) |
| de2shell_rtos | `sw/app/de2shell_rtos/` | Experimental: de2shell ported to FreeRTOS (WIP, not in main build) |
| de2os | `sw/app/de2os/` | **Experimental**: FreeRTOS on NEORV32, SDRAM execution, ICACHE + burst enabled (async FIFO CDC), separate Quartus project `par/de2os/` |
| sdram_test | `sw/app/sdram_test/` | Independent SDRAM diagnostic (4096-word dense + 31 sparse boundary probes) |
| hello | `sw/app/hello/` | Minimal UART test |
| game_snake | `sw/app/game_snake/` | Standalone snake game |
| game_life | `sw/app/game_life/` | Standalone Conway's Game of Life |
| ps2_test | `sw/app/ps2_test/` | Standalone PS/2 scancode dump |
| ir_test | `sw/app/ir_test/` | Standalone IR NEC decoder test |

`de2shell` is the primary firmware. Its `makefile` links crypto_cli sources directly (`crypto_aes.c`, `crypto_sha.c`, `crypto_sm.c`). GUI-related files (`gfx.c`, `gui.c`, `gui_widgets.c`, `win30_desk.c`, `fb_hal.c`, `screenshot_win30.c`) exist in the directory but are **excluded from the NEORV32 build** (filtered out in makefile line 13) — they only compile via `make local` (SDL2 host build). The `make local` target builds a host-native version with SDL2 for VGA frame buffer simulation.

`de2os` requires boot mode 0 + separate `par/de2os/` Quartus project. Current stable hardware baseline: `ICACHE_EN=false`. See `doc/phases/de2os-debug.md` for ICACHE/SDRAM CDC root cause analysis.

### NEORV32 ISA Extensions

Enabled in `neorv32_wrapper.vhd`: `IMC`, `Zicsr`, `Zicntr`, `Zbkb`, `Zbkc`, `Zbkx`, `Zknd`, `Zkne`, `Zknh`, `Zksed`, `Zksh`. Notably `Zfinx` is **disabled** — do not re-enable without explicit reason (synthesis memory cost).

### NEORV32 v1.13.1 Available Features (not yet wired up)

The upstream release includes these features that our wrapper/intercon have not yet connected:

- **Cache burst transfers** (`CACHE_BURSTS_EN`): ICACHE/DCACHE refill uses Wishbone incrementing bursts (`cti=010`) instead of N consecutive locked single-reads. **Enabled in de2os** (`ICACHE_BURSTS => true`) with async FIFO CDC path in `sdram_ctrl`. Not enabled in de2shell.
- **D-cache write-back** (`DCACHE_EN` + write-back policy): replaces write-through, reduces bus traffic. Not enabled.
- **XBUS `cti`/`tag` signals**: routed through `neorv32_wrapper` → `wb_intercon` → `sdram_ctrl` in de2os. de2shell ties them to `"000"` (backward compatible).
- **Bootloader flexible base address**: v1.12.8+ reworked the executable header format. Our build flow uses `image_gen` which handles this.

**ICACHE burst implementation**: `neorv32_wrapper` exposes `xbus_cti_o`/`xbus_tag_o`; `wb_intercon` passes `m_cti_i` → `s0_cti_o`; `sdram_ctrl` detects `cti=010` and uses a burst FSM with `async_fifo` (8-deep × 32-bit, Gray code CDC) for return data. Single-word path unchanged. See `doc/phases/de2os-debug.md` for root cause analysis.

## Adding a New Peripheral
1. Write VHDL in `src/rtl/periph/` with generic register interface (`cs`, `wr_en`, `rd_en`, `addr`, `wr_data`, `rd_data`, `irq`)
2. Add slave port + chip select in `wb_intercon.vhd`
3. Instantiate in `de2_115_top.vhd`
4. Add pin assignments in `par/de2extra.qsf` — **always verify against `DE2-115引脚表.xlsx`**
5. Software accesses via base address pointer

## Conventions

- **Language**: VHDL only (VHDL-2008 for NEORV32 compat; set in Quartus Settings)
- **Naming**: active-low signals `_N` suffix, clock prefix `clk_`, reset prefix `rst_`
- **Top entity**: `de2_115_top` (only entity that knows board-level pins)
- **neorv32_wrapper**: platform-agnostic CPU config; `std_ulogic` ↔ `std_logic` conversion lives here
- **One clock domain per entity**; cross-domain via synchronizers
- **Pin table is truth**: always verify against `DE2-115引脚表.xlsx` — wrong pins compile fine but malfunction

## Key Constraints

- **IMEM**: 64KB via M9K block RAM (`neorv32_imem_rom.vhd`), initialized from MIF. The old VHDL constant array caused OOM — that file is the replacement.
- **SDRAM phase shift**: DRAM_CLK requires `+1.56ns` phase shift for stable operation (empirically determined)
- **XBUS timeout**: 2048 cycles (~41μs @50MHz)
- **ICACHE + SDRAM CDC**: `sdram_ctrl` uses toggle handshake across 50MHz↔100MHz domains. Single accesses are stable; consecutive locked reads (ICACHE miss refill) can cause `req_shadow` overwrite. Fix options: (a) async FIFO in sdram_ctrl, (b) enable cache bursts. See `doc/phases/de2os-debug.md`.
- **Boot mode 2**: direct IMEM image execution (no bootloader)
- **Quartus parallelism**: `NUM_PARALLEL_PROCESSORS` is locked to `1` in QSF (was needed for OOM avoidance with old IMEM; may be safe to increase now)

## Toolchain

| Tool | Version/Path |
|------|-------------|
| Quartus Prime | 23.1std Lite (`/e/Software/intelFPGA_lite/23.1std/`) |
| NEORV32 | v1.13.1 release tag (submodule at `neorv32/`) |
| RISC-V GCC | Docker image `de2extra-builder` |
| Serial monitor | `COM10`, `115200 8N1` |

## Project Status

**V2 (v0.1) is complete** — 192/213 acceptance items passed. See `doc/de2shell-module-acceptance.md` for full results.

Deferred to V3: NTT board verification, VGA pixel mode cable test, Exp6/7 gallery, snake Game Over display, audio subsystem, de2shell_rtos.
