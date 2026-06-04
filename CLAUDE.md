# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEORV32 (RISC-V) soft-core SoC on DE2-115 (Cyclone IV E EP4CE115F29C7), running bare-metal C firmware. Target: turn the DE2-115 into a complete computer with VGA terminal, PS/2 keyboard, SDRAM, crypto accelerators, and games.

**V2 → V3 路线决策**: V2 (de2shell, bare-metal IMEM 64KB) 已冻结并删除。V3 工作重心在 **de2os** — IMEM 仅存放 ~2KB bootloader，主应用通过 boot mode 0 从 SDRAM (0x01000000) 执行 + FreeRTOS + PS/2 键盘主输入 + VGA 像素 GUI。

**NEORV32 version**: submodule pinned at release tag **v1.13.1** (2026-05-14). Do not track `main` branch — always use a release tag for stability.

## Build System

Boot mode 0 only: IMEM holds ~2KB bootloader, firmware uploaded via UART to SDRAM at `0x01000000`.
Software updates need no Quartus recompile. RTL changes require Quartus rebuild + flash.

Detailed guide: `doc/编译烧录前必看.md`.

### One-line deploy (recommended)
```bash
./run/deploy_de2shell_rtos.sh inc    # 增量: 重编 app + 上传 (~25s)
./run/deploy_de2shell_rtos.sh full   # 全量: app + bootloader + Quartus + 烧录 + 上传
./run/deploy_de2shell_rtos.sh fpga   # 仅 RTL: bootloader + Quartus + 烧录
```

### Cross-platform CLI (run/de2extra.py)
```bash
python run/de2extra.py full          # hw-build + hw-flash + sw-build + sw-upload
python run/de2extra.py inc           # sw-build + sw-upload (incremental, no Quartus)
python run/de2extra.py sw-build      # Cross-compile firmware (Docker)
python run/de2extra.py sw-upload     # Upload firmware via UART
python run/de2extra.py hw-build      # Quartus synthesis (FPGA bitstream)
python run/de2extra.py hw-flash      # Program FPGA via JTAG
```

### Manual build (if deploy script unavailable)
```bash
# Compile (~25s)
docker run --rm -v "$(pwd):/work" de2extra-builder bash -c \
  "cd /work && mkdir -p sw/app/de2shell_rtos/build && make -C sw/app/de2shell_rtos all image NEORV32_HOME=/work/neorv32"

# Upload (~5s, use --wait if board is running firmware; omit if bootloader is waiting)
python run/upload_de2os.py --wait
```

### Software local test (no FPGA needed)
```bash
cd sw/lib && make          # build de2shell.exe (SDL2 pixel-mode shell)
cd sw/lib && make run      # build + run
cd sw/lib && make clean    # remove build artifacts
```
Requires: GCC 15+ (scoop), SDL2 (scoop `SDL2` package). Uses `-DLOCAL_BUILD` to stub NEORV32 hardware. Programs available: hello, crypto, ps2, snake, conway, ntt, synth, info, riscvasm, expdemo, twm, pforth, cryptoviz.

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
├── wb_intercon          1-master, 12-slave address decoder (combinational, 10 active)
│   ├── s0: sdram_ctrl        0x01000000 (128MB, 100MHz state machine)
│   ├── s1: vga_text_terminal 0xF0000000 (32KB, 80×30 text + pixel mode via SDRAM FB)
│   ├── s2: ps2_controller   0xF0008000 (scancode + IRQ)
│   ├── s3: ir_nec_wb        0xF000C000 (NEC IR decoder)
│   ├── s4: ntt_sdf          0xF000F000 (HW removed, stub ack)
│   ├── s5: lcd_wb           0xF000B000 (HD44780 Wishbone)
│   ├── s6: build_info_wb    0xF0009000 (build info ROM)
│   ├── s7: (stub ack)       0xF000A000 (INTC reserved)
│   ├── s8: expdemo_wb       0xF0010000 (11 exp: 1-5,8-13; ch12/13 own LCD)
│   ├── s9: conway_engine    0xF0011000 (Conway engine)
│   ├── s10: synth_engine    0xF0012000 (HW removed, stub ack)
│   └── s11: gpu_2d          0xF0015000 (FILL rect via SDRAM burst)
│   Note: DDS, SD card, ChromaShader have address constants but no slave ports
├── seg7_mapper (×2)     GPIO[23:0] → HEX0–HEX7
├── lcd_status / lcd_debug  HD44780 16×2 LCD (SW16 mux; expdemo ch12/13 → HW, else → SW)
├── uart_jtag_bridge     UART TX → JTAG UART IP
└── jtag_uart_0           Platform Designer IP (Avalon JTAG UART)
```

### Address Map
| Base | Peripheral | Size | Bus width |
|------|-----------|------|-----------|
| 0x00000000 | IMEM | 64KB | 32-bit |
| 0x80000000 | DMEM | 16KB | 32-bit |
| 0x01000000 | SDRAM | 128MB | 32-bit |
| 0x01800000 | Framebuffer (in SDRAM) | 600KB | 16-bit |
| 0x01900000 | FreeRTOS heap (in SDRAM, via linker .freertos_heap) | 64KB | 32-bit |
| 0xF0000000 | VGA text terminal + pixel mode | 32KB | 16-bit |
| 0xF0008000 | PS/2 keyboard | 4KB | 32-bit |
| 0xF0009000 | Build info ROM | 4KB | 32-bit |
| 0xF000A000 | INTC (reserved) | 4KB | 32-bit |
| 0xF000B000 | LCD | 4KB | 32-bit |
| 0xF000C000 | IR receiver | 4KB | 32-bit |
| 0xF000F000 | NTT accelerator (HW removed, stub ack) | 4KB | 32-bit |
| 0xF0010000 | ExpDemo | 4KB | 32-bit |
| 0xF0011000 | Conway engine | 4KB | 32-bit |
| 0xF0012000 | Audio synth (HW removed, stub ack) | 4KB | 32-bit |
| 0xF0015000 | GPU 2D accelerator | 4KB | 32-bit |

Address constants: `src/rtl/lib/de2extra_pkg.vhd`.

Per-peripheral board status and known issues: `doc/phases/de2os-rtos-status.md`.

### Software Structure

| Directory | Description |
|-----------|-------------|
| **`sw/app/de2shell_rtos/`** | **主固件**: FreeRTOS + SDRAM 执行 + PS/2 键盘主输入 + VGA 像素 GUI。4 任务 (uart_input/shell/active/status)，shell 从 PS/2 和 UART 双路接收输入。程序启动器 (PROG_TWM 等) |
| `sw/lib/` | 源码库: HAL (vga_hal, fb_hal, gpio_hal, lcd_hal) + GPU 驱动 (gpu) + 程序 (crypto, crypto_viz, ps2, snake, conway_hw, ntt, synth, monitor, selfcheck 等) + TWM 窗口管理器 (twm, gfx, gui)。RTOS makefile 直接编译 |
| `sw/app/crypto_cli/` | 加密库: AES/SHA/SM4 (RTOS makefile 直接编译) |

**de2shell_rtos (V3 target)**: Runs from SDRAM at `0x01000000` via bootloader (boot mode 0). FreeRTOS heap (64KB `ucHeap`) at `0x01900000` in SDRAM via linker `.freertos_heap` section (no longer in DMEM). Framebuffer at `0x01800000`. Quartus project: `par/de2os/` (top entity: `de2os_top`). ICACHE currently disabled (burst CDC infrastructure pre-wired for future enable). PS/2 keyboard is the primary input (polled in `t_uart_input` alongside UART). Latest firmware: ~207KB. See `doc/phases/de2os-rtos-status.md` for build status. Source library at `sw/lib/`, crypto library at `sw/app/crypto_cli/`.

CLI commands (21 + help builtin):

| Program commands | Description |
|-----------------|-------------|
| hello | LED chaser + counter |
| crypto | AES/SHA/SM4 bench |
| ps2 (kbd) | PS/2 keyboard test |
| snake | Snake (1P/2P) |
| conway | Conway (HW accel) |
| info | System dashboard |
| riscvasm | RISC-V monitor/asm |
| expdemo | HW course labs (11 exp: 1-5, 8-13; Exp8→PS/2 chain) |
| twm | Tiling window mgr |
| ntt | NTT (SW only, HW disabled) |
| ~~synth~~ | Audio synth (disabled) |
| pforth | pForth interpreter |
| cryptoviz | AES/SHA step-through viz (pixel mode) |

| Utility commands | Description |
|-----------------|-------------|
| selfcheck | Board self-test (also runs at boot) |
| postverify | Bus probe (active + stub verification) |
| stats | Tasks + CPU + heap |
| ver | Version / build info |
| clear | Clear screen |
| pxtest | VGA pixel diag |
| vgadump | Dump VGA to UART |
| vgamon | Periodic VGA dump |

All interactive programs: F1=help overlay (pauses game), F10=quit to shell. cryptoviz uses Space=step, A=auto-play, P=pause, L/R=skip, Q=quit. Note: `chroma` command registered in source but excluded from build.

**Program chaining**: `g_chain_program` volatile variable lets programs request launching another program on exit. Exp8 (PS/2 scan codes) uses this to chain to the `ps2` keyboard program.

### NEORV32 ISA Extensions

Enabled in `neorv32_wrapper.vhd`: `IMC`, `Zicsr`, `Zicntr`, `Zbkb`, `Zbkc`, `Zbkx`, `Zknd`, `Zkne`, `Zknh`, `Zksed`, `Zksh`. Notably `Zfinx` is **disabled** — do not re-enable without explicit reason (synthesis memory cost).

### NEORV32 v1.13.1 Available Features (not yet wired up)

The upstream release includes these features that our wrapper/intercon have not yet connected:

- **Cache burst transfers** (`CACHE_BURSTS_EN`): ICACHE/DCACHE refill uses Wishbone incrementing bursts (`cti=010`). Enabled in top entity (`ICACHE_BURSTS => true`) with async FIFO CDC path in `sdram_ctrl`. ICACHE itself disabled (`ICACHE_EN => false`).
- **D-cache write-back** (`DCACHE_EN`): Not enabled.
- **XBUS `cti`/`tag` signals**: routed through `neorv32_wrapper` → `wb_intercon` → `sdram_ctrl`.

## Adding a New Peripheral
1. Write VHDL in `src/rtl/periph/` with generic register interface (`cs`, `wr_en`, `rd_en`, `addr`, `wr_data`, `rd_data`, `irq`)
2. Add address constant in `src/rtl/lib/de2extra_pkg.vhd`
3. Add slave port + chip select in `wb_intercon.vhd`
4. Instantiate in `de2os_top.vhd` (only entity that knows board pins)
5. Add pin assignments in `par/de2os/de2os.qsf` — **always verify against `DE2-115引脚表.xlsx`**
6. Add source file in `par/de2os/de2os.qsf`
7. Software accesses via base address pointer

## Conventions

- **Language**: VHDL only (VHDL-2008 for NEORV32 compat; set in Quartus Settings)
- **Naming**: active-low signals `_N` suffix, clock prefix `clk_`, reset prefix `rst_`
- **Top entity**: `de2os_top` (only entity that knows board-level pins)
- **neorv32_wrapper**: platform-agnostic CPU config; `std_ulogic` ↔ `std_logic` conversion lives here
- **One clock domain per entity**; cross-domain via synchronizers
- **Pin table is truth**: always verify against `DE2-115引脚表.xlsx` — wrong pins compile fine but malfunction

### Shell Idle Board Display (GPIO → 7-SEG + LED)

When `active_prog == PROG_SHELL`, `t_status` drives GPIO to show:

| Display | Content | Encoding |
|---------|---------|----------|
| HEX5-HEX4 | Heap used % (0–99) | Decimal (BCD) |
| HEX3-HEX0 | Uptime seconds | Hexadecimal |
| LEDG7-0 | Heap used % | Hexadecimal (raw) |
| LEDR15-0 | Uptime seconds | Hexadecimal (raw) |
| HEX7-HEX6 | Blank (common-anode off) | Hardwired |
| LCD line 1 | "DE2Extra Status" | Text |
| LCD line 2 | "RAW " + GPIO hex | Text |

When running a non-shell program, `board_status_set_program()` shows PROG_ID/state on HEX+LCD instead. Board status writes are protected by `xVgaMutex` to prevent Wishbone collision with VGA.

**info / expdemo LED display**: Both programs render `LEDR[17:0]` (red) and `LEDG[7:0]` (green) with color-coded bit display. LEDR = SW[17:16] + gpio_out[15:0], LEDG = gpio_out[23:16].

## Key Constraints

- **IMEM**: 64KB via M9K block RAM (`neorv32_imem_rom.vhd`), initialized from MIF. The old VHDL constant array caused OOM — that file is the replacement.
- **SDRAM phase shift**: DRAM_CLK requires `+1.56ns` phase shift for stable operation (empirically determined)
- **XBUS timeout**: 2048 cycles (~41μs @50MHz)
- **ICACHE disabled**: ICACHE_EN=false in de2os_top. Async FIFO CDC path for burst reads is pre-wired in sdram_ctrl but untested.
- **Boot mode 0 only**: bootloader from IMEM (~2KB), loads main app from UART into SDRAM at `0x01000000`. Boot mode 2 (IMEM direct) is deprecated.
- **Quartus parallelism**: `NUM_PARALLEL_PROCESSORS = 8` in QSF. Full build (app+bootloader+Quartus+flash+upload) ~40 min; incremental app-only ~25s.
- **CLI output buffer**: `cOutputBuffer` is 512 bytes (was 256, increased to fix `postverify` crash on long output).
- **LCD hardware mux**: `de2os_top` routes LCD to expdemo hardware only for ch12/13; other channels use software-controlled LCD via `lcd_shell_*` signals.

## Toolchain

| Tool | Version/Path |
|------|-------------|
| Quartus Prime | 23.1std Lite |
| NEORV32 | v1.13.1 release tag (submodule at `neorv32/`) |
| RISC-V GCC | Docker image `de2extra-builder` |
| Serial monitor | UART `115200 8N1` |

## Project Status

**V3 active (v0.3)** — de2os (FreeRTOS + SDRAM exec + PS/2 keyboard + VGA pixel GUI). 10 active Wishbone peripherals (NTT/Synth HW removed). FreeRTOS heap (64KB) in SDRAM via linker script. LCD mux fix for expdemo, postverify crash fix, program chaining (Exp8→PS/2), LEDR/LEDG color-coded display. Board verified 2026-06-04, all CLI commands tested, 0 crashes. Details: `doc/phases/de2os-rtos-status.md`.
