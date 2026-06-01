# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEORV32 (RISC-V) soft-core SoC on DE2-115 (Cyclone IV E EP4CE115F29C7), running bare-metal C firmware. Target: turn the DE2-115 into a complete computer with VGA terminal, PS/2 keyboard, SDRAM, crypto accelerators, and games.

**V2 → V3 路线决策**: V2 (de2shell, bare-metal IMEM 64KB) 已冻结并删除。V3 工作重心在 **de2os** — IMEM 仅存放 ~2KB bootloader，主应用通过 boot mode 0 从 SDRAM (0x01000000) 执行 + FreeRTOS + PS/2 键盘主输入 + VGA 像素 GUI。

**NEORV32 version**: submodule pinned at release tag **v1.13.1** (2026-05-14). Do not track `main` branch — always use a release tag for stability.

## Build System

### V3 deployment (Git Bash on Windows)

Two boot modes available for `de2os_top`:

**Boot mode 0** (default — recommended):
IMEM holds only a ~2KB bootloader. After FPGA config, use the deploy script to
cross-compile firmware in Docker, upload via UART, and execute from SDRAM at `0x01000000`.
Software updates need NO Quartus recompile — just `app` or `upload`.
```bash
./run/deploy_de2shell_rtos.sh app      # compile + UART upload (~48s)
./run/deploy_de2shell_rtos.sh upload   # upload existing bin only (fastest)
./run/deploy_de2shell_rtos.sh fpga     # rebuild bootloader + Quartus + flash
./run/deploy_de2shell_rtos.sh full     # full rebuild + flash + upload (~4min)
```

**Boot mode 2** (IMEM direct — for bring-up only):
Bakes the entire program into the bitstream. No UART upload needed at power-on,
but every code change requires a full Quartus rebuild. Used by `deploy_de2shell_rtos_imem.sh`.
```bash
./run/deploy_deshell_rtos_imem.sh build   # compile + generate IMEM image
./run/deployde2shell_rtos_imem.sh flash   # Quartus compile + JTAG flash
```

Only RTL/top/bootloader/address-map changes need `fpga` or `full`. See `doc/编译烧录前必看.md`
for the full deployment guide.

Normal SW changes (firmware only) need no Quartus compile -- just `app` or `upload`. Only RTL/top/bootloader/address-map changes need `fpga` or `full`. See `doc/编译烧录前必看.md` for the full incremental deployment guide.

### V2 one-command build (deprecated — V2 project deleted)

### Manual build
1. Firmware: `cd sw/app/<name> && make clean all image NEORV32_HOME=../../../neorv32`
2. Copy: `cp neorv32/rtl/core/neorv32_imem_image.vhd src/rtl/`
3. Quartus: open `par/de2os/de2os.qpf`, Ctrl+L
4. Program: Quartus Programmer → `par/de2os/de2os.sof`

### Software local test (no FPGA needed)
```bash
cd sw/lib && make local   # compiles with host gcc, -DLOCAL_BUILD (needs SDL2 via scoop)
```

### Quartus VHDL version

NEORV32 requires **VHDL-2008** (uses `std_ulogic`, record types). Set once: Assignments → Settings → Compiler Settings → VHDL Input → VHDL 2008.

## Architecture

```
de2os_top.vhd (top entity, knows board pins)
├── clk_rst_gen          PLL: 50MHz (CPU/WB) + 100MHz (SDRAM) + 25MHz (VGA pixel clock) + phase-shifted DRAM_CLK
├── neorv32_wrapper      CPU config wrapper (55 generics, std_ulogic ↔ std_logic conversion)
│   └── neorv32_top      RISC-V core (RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh/Zksed/Zksh)
│       ├── IMEM         64KB via M9K block RAM (neorv32_imem_rom.vhd, init from MIF)
│       ├── DMEM         16KB
│       ├── XBUS         Wishbone external bus master (timeout 2048 cycles), supports burst cti/tag signals
│       └── Built-in     UART0 (115200), GPIO(32), TRNG, CLINT, OCD
├── wb_intercon          1-master, 14-slave address decoder (combinational)
│   ├── s0: sdram_ctrl   0x01000000 (128MB, 100MHz state machine)
│   ├── s1: vga_text_terminal  0xF0000000 (32KB, 80×30 text mode + pixel mode via SDRAM FB)
│   ├── s2: ps2_controller    0xF0008000 (scancode + IRQ)
│   ├── s3: ir_nec_wb         0xF000C000 (NEC IR decoder)
│   ├── s4: ntt_sdf           0xF000F000 (NTT accelerator)
│   ├── s5: lcd_wb            0xF000B000 (LCD Wishbone controller)
│   ├── s6: build_info_wb      0xF0009000 (build info ROM; timer address reused)
│   ├── s7: (stub ack)        0xF000A000 (INTC address reserved, ack loopback)
│   ├── s8: expdemo_wb        0xF0010000 (Hardware experiment multiplexer, 11 experiments)
│   ├── s9: pong_engine      0xF0011000 (PONG engine + VGA output)
│   ├── s10: conway_engine   0xF0012000 (Conway engine)
│   ├── s11: synth_engine    0xF0013000 (Audio synth: 3xOSC + DX7 FM, WM8731 I2S)
│   ├── s12: gpu_2d          0xF0015000 (2D GPU: FILL rect via SDRAM burst-write)
│   └── s13: chroma_shader   0xF0014000 (HW noise terrain + VGA terminal override — NOT YET WIRED)
│   Note: DDS (0xF000D000) and SD card (0xF000E000) have address constants
│         in de2extra_pkg.vhd but no slave ports in wb_intercon.
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
| 0xF0000000 | VGA text terminal + pixel mode | 32KB | 16-bit |
| 0xF0013000 | Audio synth (synth_engine) | 4KB | 32-bit |
| 0xF0015000 | GPU 2D accelerator | 4KB | 32-bit |
| 0xF0008000 | PS/2 keyboard | 4KB | 32-bit |
| 0xF0009000 | Timer (reserved) | 4KB | 32-bit |
| 0xF000A000 | INTC (reserved) | 4KB | 32-bit |
| 0xF000B000 | LCD | 4KB | 32-bit |
| 0xF000C000 | IR receiver | 4KB | 32-bit |
| 0xF000D000 | DDS (reserved) | 4KB | 32-bit |
| 0xF000E000 | SD card (reserved) | 4KB | 32-bit |
| 0xF000F000 | NTT accelerator | 4KB | 32-bit |
| 0xF0010000 | ExpDemo | 4KB | 32-bit |
| 0xF0011000 | PONG engine | 4KB | 32-bit |
| 0xF0012000 | Conway engine | 4KB | 32-bit |
| 0xF0014000 | ChromaShader (HW terrain) | 4KB | 32-bit |

Address constants: `src/rtl/lib/de2extra_pkg.vhd`.

Note: **NTT accelerator** (`ntt_sdf.vhd`) is instantiated in `de2os_top.vhd` (RTL integrated, Quartus pass). The C driver (`sw/lib/ntt.c`) has dual-mode (LOCAL_BUILD SW reference / NEORV32 HW MMIO). NEORV32 path fixed: `cmd_ntt()` uses direct MMIO instead of software buffer. Board verification pending.

Note: **PONG engine** (`pong_engine.vhd`) is instantiated in `de2os_top.vhd` with full port map (Wishbone + VGA output). C driver (`pong_hw.c`) registered as `ponghw` CLI command. Board verification pending.

Note: **Conway engine** (`conway_engine.vhd`) is instantiated in `de2os_top.vhd`. C driver (`conway_hw.c`) registered as `conwayhw` CLI command. Board verification pending.

Note: **ExpDemo** is instantiated in `de2os_top.vhd`. It wraps 11 experiment adapters with output/peripheral multiplexing. Board verified.

Note: **VGA pixel mode** (`vga_pixel_ctrl.vhd`) is instantiated inside `vga_text_terminal`. It reads a framebuffer from SDRAM and displays 640×480@60Hz RGB565. Used by TWM (`twm` command) and screenshot tools. First displayed on physical monitor 2026-05-31 but unstable. VGA 25MHz clock changed from toggle flip-flop to PLL c3 output (2026-06-01) to fix UART TX noise coupling.

### Software Structure

| Directory | Description |
|-----------|-------------|
| **`sw/app/de2shell_rtos/`** | **主固件**: FreeRTOS + SDRAM 执行 + PS/2 键盘主输入 + VGA 像素 GUI。4 任务 (uart_input/shell/active/status)，shell 从 PS/2 和 UART 双路接收输入 |
| `sw/lib/` | 源码库: HAL (vga_hal, fb_hal, gpio_hal, lcd_hal) + 程序 (crypto, ps2, snake, life, ntt, synth 等) + GUI (gfx, gui, twm)。RTOS makefile 直接编译 |
| `sw/app/crypto_cli/` | 加密库: AES/SHA/SM4 (RTOS makefile 直接编译) |
| `sw/app/common/` | 公共头文件 |

**de2shell_rtos (V3 target)**: Runs from SDRAM at `0x01000000` via bootloader (boot mode 0). FreeRTOS heap at `0x01900000`, framebuffer at `0x01800000`. Quartus project: `par/de2os/` (top entity: `de2os_top`). ICACHE + burst enabled via async FIFO CDC. PS/2 keyboard is the primary input (polled in `t_uart_input` alongside UART). Latest firmware: 146KB. See `doc/phases/de2os-rtos-status.md` for build status and `doc/phases/de2os-debug.md` for ICACHE/SDRAM CDC analysis. Source library at `sw/lib/`, crypto library at `sw/app/crypto_cli/`.

CLI commands (21 total + help): hello, memtest, crypto, ps2, snake, life, info, expdemo, twm, conwayhw, ponghw, ntt, synth, pxtest, vgadump, vgam, stats, heapstat, cpustat, clear. Aliases: kbd→ps2, conwaylife→life, riscvasm→monitor.

### NEORV32 ISA Extensions

Enabled in `neorv32_wrapper.vhd`: `IMC`, `Zicsr`, `Zicntr`, `Zbkb`, `Zbkc`, `Zbkx`, `Zknd`, `Zkne`, `Zknh`, `Zksed`, `Zksh`. Notably `Zfinx` is **disabled** — do not re-enable without explicit reason (synthesis memory cost).

### NEORV32 v1.13.1 Available Features (not yet wired up)

The upstream release includes these features that our wrapper/intercon have not yet connected:

- **Cache burst transfers** (`CACHE_BURSTS_EN`): ICACHE/DCACHE refill uses Wishbone incrementing bursts (`cti=010`) instead of N consecutive locked single-reads. Enabled in both top entities (`ICACHE_BURSTS => true`) with async FIFO CDC path in `sdram_ctrl`. Note: `de2os_top` has `ICACHE_EN => false` currently (ICACHE disabled, but burst flag pre-set for when it is enabled).
- **D-cache write-back** (`DCACHE_EN` + write-back policy): replaces write-through, reduces bus traffic. Not enabled.
- **XBUS `cti`/`tag` signals**: routed through `neorv32_wrapper` → `wb_intercon` → `sdram_ctrl` in both top entities.
- **Bootloader flexible base address**: v1.12.8+ reworked the executable header format. Our build flow uses `image_gen` which handles this.

**ICACHE burst implementation**: `neorv32_wrapper` exposes `xbus_cti_o`/`xbus_tag_o`; `wb_intercon` passes `m_cti_i` → `s0_cti_o`; `sdram_ctrl` detects `cti=010` and uses a burst FSM with `async_fifo` (8-deep × 32-bit, Gray code CDC) for return data. Single-word path unchanged. See `doc/phases/de2os-debug.md` for root cause analysis.

## Adding a New Peripheral
1. Write VHDL in `src/rtl/periph/` with generic register interface (`cs`, `wr_en`, `rd_en`, `addr`, `wr_data`, `rd_data`, `irq`)
2. Add slave port + chip select in `wb_intercon.vhd`
3. Instantiate in `de2_115_top.vhd`
4. Add pin assignments in `par/de2os/de2os.qsf` — **always verify against `DE2-115引脚表.xlsx`**
5. Software accesses via base address pointer

## Conventions

- **Language**: VHDL only (VHDL-2008 for NEORV32 compat; set in Quartus Settings)
- **Naming**: active-low signals `_N` suffix, clock prefix `clk_`, reset prefix `rst_`
- **Top entity**: `de2os_top` (only entity that knows board-level pins)
- **neorv32_wrapper**: platform-agnostic CPU config; `std_ulogic` ↔ `std_logic` conversion lives here
- **One clock domain per entity**; cross-domain via synchronizers
- **Pin table is truth**: always verify against `DE2-115引脚表.xlsx` — wrong pins compile fine but malfunction

## Key Constraints

- **IMEM**: 64KB via M9K block RAM (`neorv32_imem_rom.vhd`), initialized from MIF. The old VHDL constant array caused OOM — that file is the replacement.
- **SDRAM phase shift**: DRAM_CLK requires `+1.56ns` phase shift for stable operation (empirically determined)
- **XBUS timeout**: 2048 cycles (~41μs @50MHz)
- **ICACHE + SDRAM CDC**: `sdram_ctrl` uses toggle handshake across 50MHz↔100MHz domains. Single accesses are stable; consecutive locked reads (ICACHE miss refill) can cause `req_shadow` overwrite. Fix options: (a) async FIFO in sdram_ctrl, (b) enable cache bursts. See `doc/phases/de2os-debug.md`.
- **Boot mode 0**: bootloader from IMEM (~2KB), loads main app from UART into SDRAM at `0x01000000`. Used by `de2os_top` (V3 primary, **recommended**). Incremental deployment via `run/deploy_de2shell_rtos.sh`.
- **Boot mode 2**: direct IMEM image execution (no bootloader, no UART upload needed). Entire program baked into bitstream. Used by `de2shell_rtos_imem_top` (V3 bring-up only) via `run/deploy_de2shell_rtos_imem.sh`. Every code change requires full Quartus rebuild.
- **Quartus parallelism**: `NUM_PARALLEL_PROCESSORS` is locked to `1` in QSF (was needed for OOM avoidance with old IMEM; may be safe to increase now)

## Toolchain

| Tool | Version/Path |
|------|-------------|
| Quartus Prime | 23.1std Lite (`/e/Software/intelFPGA_lite/23.1std/`) |
| NEORV32 | v1.13.1 release tag (submodule at `neorv32/`) |
| RISC-V GCC | Docker image `de2extra-builder` |
| Serial monitor | `COM10`, `115200 8N1` |

## Project Status

**V2 (v0.1) is complete** — 192/213 acceptance items passed. de2shell is frozen. See `doc/de2shell-module-acceptance.md` for full results.

**V3 is active** — all work on de2os (SDRAM exec + FreeRTOS + PS/2 keyboard + VGA pixel GUI). See `doc/phases/phase5-sdram-gui.md` for plan. See `doc/phases/de2os-rtos-status.md` for detailed build status.

V3 progress: SDRAM execution done, FreeRTOS 4 tasks running (uart_input / shell / active / status), CLI 22 commands (incl. chroma), VGA text terminal 80x30 (CP437 256 chars), VGA pixel mode wired (640x480 RGB565 framebuffer in SDRAM). **GPU 2D accelerator integrated** (s12 @ 0xF0015000, FILL rect via SDRAM burst-write). **VGA PLL clock fix in progress**: toggle flip-flop → PLL c3 25MHz output to eliminate UART TX noise coupling. TWM pixel mode first displayed on physical monitor (2026-05-31) but unstable. Current blocker: VGA pixel mode display quality. **Conway/PONG/NTT/Audio synth/ChromaShader RTL all integrated** in de2os_top. Latest Quartus build: 2026-06-01 (compiling with PLL VGA clock fix).
