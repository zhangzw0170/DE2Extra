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

### Manual build (if deploy script unavailable)
```bash
# Compile (~25s)
docker run --rm -v "E:/Main/JuniorII/NonExam/FPGA/DE2Extra:/work" de2extra-builder bash -c \
  "cd /work && mkdir -p sw/app/de2shell_rtos/build && make -C sw/app/de2shell_rtos all image NEORV32_HOME=/work/neorv32"

# Upload (~5s, use --wait if board is running firmware; omit if bootloader is waiting)
python run/upload_de2os.py --wait
```

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
├── wb_intercon          1-master, 12-slave address decoder (combinational)
│   ├── s0: sdram_ctrl   0x01000000 (128MB, 100MHz state machine)
│   ├── s1: vga_text_terminal  0xF0000000 (32KB, 80×30 text mode + pixel mode via SDRAM FB)
│   ├── s2: ps2_controller    0xF0008000 (scancode + IRQ)
│   ├── s3: ir_nec_wb         0xF000C000 (NEC IR decoder)
│   ├── s4: ntt_sdf           0xF000F000 (NTT accelerator)
│   ├── s5: lcd_wb            0xF000B000 (LCD Wishbone controller)
│   ├── s6: build_info_wb      0xF0009000 (build info ROM; timer address reused)
│   ├── s7: (stub ack)        0xF000A000 (INTC address reserved, ack loopback)
│   ├── s8: expdemo_wb        0xF0010000 (Hardware experiment multiplexer, 13 experiments)
│   ├── s9: conway_engine   0xF0011000 (Conway engine)
│   ├── s10: synth_engine    0xF0012000 (Audio synth: 3xOSC + DX7 FM, WM8731 I2S)
│   └── s11: gpu_2d          0xF0015000 (2D GPU: FILL rect via SDRAM burst-write)
│   Note: DDS (0xF000D000), SD card (0xF000E000), ChromaShader (0xF0014000) have
│         address constants but no slave ports in wb_intercon. chroma.c excluded from build.
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
| 0x01800000 | Framebuffer (in SDRAM) | 600KB | 16-bit |
| 0x01900000 | FreeRTOS heap (in SDRAM) | 16KB | 32-bit |
| 0xF0000000 | VGA text terminal + pixel mode | 32KB | 16-bit |
| 0xF0008000 | PS/2 keyboard | 4KB | 32-bit |
| 0xF0009000 | Build info ROM | 4KB | 32-bit |
| 0xF000A000 | INTC (reserved) | 4KB | 32-bit |
| 0xF000B000 | LCD | 4KB | 32-bit |
| 0xF000C000 | IR receiver | 4KB | 32-bit |
| 0xF000F000 | NTT accelerator | 4KB | 32-bit |
| 0xF0010000 | ExpDemo | 4KB | 32-bit |
| 0xF0011000 | Conway engine | 4KB | 32-bit |
| 0xF0012000 | Audio synth | 4KB | 32-bit |
| 0xF0015000 | GPU 2D accelerator | 4KB | 32-bit |

Address constants: `src/rtl/lib/de2extra_pkg.vhd`.

Per-peripheral board status and known issues: `doc/phases/de2os-rtos-status.md`.

### Software Structure

| Directory | Description |
|-----------|-------------|
| **`sw/app/de2shell_rtos/`** | **主固件**: FreeRTOS + SDRAM 执行 + PS/2 键盘主输入 + VGA 像素 GUI。4 任务 (uart_input/shell/active/status)，shell 从 PS/2 和 UART 双路接收输入。程序启动器 (PROG_TWM 等) |
| `sw/lib/` | 源码库: HAL (vga_hal, fb_hal, gpio_hal, lcd_hal) + GPU 驱动 (gpu) + 程序 (crypto, ps2, snake, conway_hw, ntt, synth, monitor, selfcheck 等) + TWM 窗口管理器 (twm, gfx)。RTOS makefile 直接编译 |
| `sw/app/crypto_cli/` | 加密库: AES/SHA/SM4 (RTOS makefile 直接编译) |
| `sw/app/common/` | 公共头文件 |

**de2shell_rtos (V3 target)**: Runs from SDRAM at `0x01000000` via bootloader (boot mode 0). FreeRTOS heap at `0x01900000`, framebuffer at `0x01800000`. Quartus project: `par/de2os/` (top entity: `de2os_top`). ICACHE currently disabled (burst CDC infrastructure pre-wired for future enable). PS/2 keyboard is the primary input (polled in `t_uart_input` alongside UART). Latest firmware: ~156KB. See `doc/phases/de2os-rtos-status.md` for build status. Source library at `sw/lib/`, crypto library at `sw/app/crypto_cli/`.

CLI commands (18 + help builtin):

| Program commands | Description |
|-----------------|-------------|
| hello | LED chaser + counter |
| crypto | AES/SHA/SM4 bench |
| ps2 (kbd) | PS/2 keyboard test |
| snake | Snake (1P/2P) |
| conway | Conway (HW accel) |
| info | System dashboard |
| riscvasm | RISC-V monitor/asm |
| expdemo | HW course labs (13 exp) |
| twm | Tiling window mgr |
| ntt | NTT accelerator |
| synth | Audio synth |

| Utility commands | Description |
|-----------------|-------------|
| selfcheck | Board self-test (also runs at boot) |
| stats | Tasks + CPU + heap |
| ver | Version / build info |
| clear | Clear screen |
| pxtest | VGA pixel diag |
| vgadump | Dump VGA to UART |
| vgamon | Periodic VGA dump |

All interactive programs: F1=help overlay (pauses game), F10=quit to shell. Note: `chroma` command registered in source but excluded from build.

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

When running a non-shell program, `board_status_set_program()` shows PROG_ID/state on HEX+LCD instead.

## Key Constraints

- **IMEM**: 64KB via M9K block RAM (`neorv32_imem_rom.vhd`), initialized from MIF. The old VHDL constant array caused OOM — that file is the replacement.
- **SDRAM phase shift**: DRAM_CLK requires `+1.56ns` phase shift for stable operation (empirically determined)
- **XBUS timeout**: 2048 cycles (~41μs @50MHz)
- **ICACHE disabled**: ICACHE_EN=false in de2os_top. Async FIFO CDC path for burst reads is pre-wired in sdram_ctrl but untested.
- **Boot mode 0 only**: bootloader from IMEM (~2KB), loads main app from UART into SDRAM at `0x01000000`. Boot mode 2 (IMEM direct) is deprecated.
- **Quartus parallelism**: `NUM_PARALLEL_PROCESSORS = 8` in QSF. Full build (app+bootloader+Quartus+flash+upload) ~40 min; incremental app-only ~25s.

## Toolchain

| Tool | Version/Path |
|------|-------------|
| Quartus Prime | 23.1std Lite (`/e/Software/intelFPGA_lite/23.1std/`) |
| NEORV32 | v1.13.1 release tag (submodule at `neorv32/`) |
| RISC-V GCC | Docker image `de2extra-builder` |
| Serial monitor | `COM10`, `115200 8N1` |

## Project Status

**V3 active** — de2os (FreeRTOS + SDRAM exec + PS/2 keyboard + VGA pixel GUI). Board verified 2026-06-02, 5 known bugs. Details: `doc/phases/de2os-rtos-status.md`.
