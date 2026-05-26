# DE2Extra — NEORV32 RISC-V Full-Peripheral Terminal System

English | [中文](README.md)

> Turn the DE2-115 board into a complete computer: RISC-V CPU + VGA terminal + PS/2 keyboard + SDRAM + crypto acceleration + course lab multiplexer

## AI Disclosure

This project was developed with assistance from: [DeepSeek V4](https://chat.deepseek.com/), [GLM 5.1](https://chatglm.cn/), [GPT 5.4](https://chat.openai.com/). All AI-generated content has been manually reviewed.

## References

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V soft core used in this project
- [FreeRTOS](https://www.freertos.org/) — Real-time OS kernel used by de2shell_rtos
- [DE2-115 System CD](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=506) — Terasic official examples and reference materials

## Overview

Runs the [NEORV32](https://github.com/stnolting/neorv32) RISC-V soft-core on a DE2-115 (Cyclone IV E) with custom Wishbone peripherals driving on-board hardware. V2 (de2shell) is frozen and acceptance-complete; V3 (de2shell_rtos) is the active track.

```
┌─────────────────────────────────────────────────────┐
│  de2shell_rtos — FreeRTOS multi-task terminal (V3) │
│  CLI 16 commands: hello / memtest / crypto / snake  │
│  life / info / expdemo / twm / ps2 / vgadump / ... │
├─────────────────────────────────────────────────────┤
│  de2shell — Bare-metal terminal (V2 frozen)          │
├─────────────────────────────────────────────────────┤
│       NEORV32 RISC-V core (~4000 LUTs)              │
│       RV32IMC + Zicsr + Zicntr + Zk* crypto exts   │
├─────────────────────────────────────────────────────┤
│  Custom VHDL peripherals (Wishbone slaves)           │
│  SDRAM | VGA | PS/2 | LCD | IR | NTT | ExpDemo |    │
│  Conway | PONG | Audio synth | BuildInfo             │
├─────────────────────────────────────────────────────┤
│       DE2-115 FPGA (Cyclone IV E, 114K LEs)         │
└─────────────────────────────────────────────────────┘
```

## Hardware Platform

**Primary**: Terasic DE2-115 (`EP4CE115F29C7`)

- **FPGA**: Cyclone IV E, 114,480 LEs, 266 multipliers, 4 PLLs
- **Memory**: 128MB SDRAM, 2MB SRAM, 8MB Flash, SD card slot
- **Display**: 16×2 LCD, 8 seven-segment displays, 27 LEDs (9G+18R), VGA (8-bit/channel DAC)
- **Comms**: RS-232, PS/2 ×2, IR receiver, USB 2.0, Gigabit Ethernet ×2
- **Audio**: WM8731 24-bit CODEC
- **Input**: 4 push-buttons, 18 slide switches

Pin reference: [`DE2-115_pin_table_backup.md`](DE2-115_pin_table_backup.md)

## CPU Configuration

NEORV32 (v1.13.1) included as a git submodule.

- **ISA**: RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx + Zknd/Zkne/Zknh/Zksed/Zksh
- **Clock**: 50 MHz
- **Memory**: 64KB IMEM (M9K) + 16KB DMEM (M9K) + 128MB SDRAM (external)
- **Built-in**: UART (115200), GPIO (32-bit), TRNG, CLINT, OCD debugger
- **Crypto**: AES, SHA-256/512, SM3/SM4 hardware instructions (Zk*)
- **External bus**: Wishbone with burst support (cti/tag)
- **License**: BSD-3-Clause (submodule)

Local patches: [`doc/reference/neorv32-patches.md`](doc/reference/neorv32-patches.md)

## Peripheral Modules

All custom peripherals are mounted as Wishbone slaves via `wb_intercon` with a unified register interface.

| Module | Address | Description | Status |
|--------|---------|-------------|--------|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM controller, burst support, async FIFO CDC | ✅ Board verified |
| `vga_text_terminal` | `0xF0000000` | 80×30 color text terminal, full CP437 (256 chars), pixel mode (SDRAM FB) | ✅ Board verified |
| `ps2_controller` | `0xF0008000` | PS/2 keyboard + FIFO + IRQ, RTOS primary input | ✅ Board verified |
| `expdemo_wb` | `0xF0010000` | 11 course lab hardware multiplexer | ✅ Board verified |
| `ir_nec_wb` | `0xF000C000` | IR NEC protocol decoder | ✅ Board verified |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD (Wishbone) | ✅ Board verified |
| `ntt_sdf` | `0xF000F000` | NTT accelerator (q=3329, N=256) | 🟡 Sim verified, needs board |
| `pong_engine` | `0xF0011000` | PONG hardware engine, self-contained VGA timing (640×480) | 🟡 VHDL+C done, not integrated |
| `conway_engine` | `0xF0012000` | Conway's Game of Life hardware engine, double-buffered | 🟡 VHDL+C done, not integrated |
| `build_info_wb` | `0xF0009000` | Build info ROM (git hash + timestamp) | ✅ |
| `dds_synth` | `0xF000D000` | DDS audio synthesizer (sine + FM) | 🟡 Sim 7/7 PASS, not integrated |

> Address constants defined in `src/rtl/lib/de2extra_pkg.vhd`.

## Software Applications

| App | Description |
|-----|-------------|
| **de2shell_rtos** (V3 active) | FreeRTOS 4 tasks (uart_input/shell/active/status), 16 CLI commands, SDRAM exec + PS/2 keyboard primary input + VGA pixel GUI (TWM) |
| **de2shell** (V2 frozen) | Bare-metal shell: memtest, crypto, snake, life, dashboard, expdemo, monitor, PS/2. IMEM 64KB, no longer updated |
| **crypto_cli** | Crypto library (AES/SHA/SM4, sources linked into multiple firmware) |
| **hello** | LED chaser |
| **sdram_test** | SDRAM diagnostics (4096-word dense + 31 sparse boundary probes) |
| **ps2_test** | PS/2 scancode dump |
| **ir_test** | IR decoder test |

### de2shell_rtos CLI Commands (16)

| Command | Function |
|---------|----------|
| hello | LED chaser |
| memtest | SDRAM diagnostics |
| crypto | AES/SHA/SM4 CLI |
| ps2 / kbd | PS/2 keyboard test |
| snake | Full-screen snake 78×27 (CP437 border + vblank sync) |
| info | System dashboard |
| expdemo | 11 course experiments |
| twm | Tiling window manager (pixel mode GUI) |
| vgadump | VGA framebuffer diagnostics |
| vgam | VGA mode query |
| stats | FreeRTOS task list + stack HWM |
| heapstat | Heap usage statistics |
| cpustat | Per-task CPU usage |

## Directory Layout

```
DE2Extra/
├── CLAUDE.md                  # AI agent guidelines
├── build.sh                   # V2 one-command build (Git Bash)
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/
│   ├── de2_115_top.vhd        # de2shell top entity (V2 frozen)
│   ├── de2os_top.vhd          # de2os top entity (V3 active, separate Quartus project)
│   ├── neorv32_wrapper.vhd    # CPU config wrapper
│   ├── bus/wb_intercon.vhd    # Wishbone interconnect (1 master, 11 slaves)
│   ├── periph/                # Peripheral controllers
│   ├── exp/                   # Course lab modules + adapters
│   ├── lib/                   # Common packages (de2extra_pkg, font_rom_pkg)
│   └── periph/sim/            # Peripheral simulation testbenches
├── sw/app/
│   ├── de2shell_rtos/         # V3 active firmware (FreeRTOS + SDRAM)
│   ├── de2shell/              # V2 frozen firmware (bare-metal IMEM)
│   ├── crypto_cli/            # Crypto CLI
│   └── ...                    # Other test apps
├── par/
│   ├── de2extra.qpf/qsf       # V2 de2shell Quartus project
│   └── de2os/                 # V3 de2os Quartus project
├── constraints/               # Pin assignments + timing (.sdc)
├── tools/                     # Utility scripts (gen_font_rom.py, etc.)
├── run/                       # Deploy scripts
└── doc/                       # Design docs, acceptance tables, phase plans
```

## Build

### Prerequisites

- Quartus Prime 23.1std Lite
- Docker Desktop (RISC-V cross-compilation)
- Git Bash (Windows)

> **Important**: NEORV32 uses VHDL-2008. On first open, set Quartus: Assignments → Settings → VHDL Input → VHDL 2008.

### de2shell_rtos (V3 — recommended)

Boot mode 0: IMEM holds only a ~2KB bootloader. Firmware is uploaded via UART to SDRAM. Software updates need no Quartus recompile.

```bash
# Incremental (recompile firmware + UART upload, ~48s)
./run/deploy_de2shell_rtos.sh app

# Upload existing bin only (fastest)
./run/deploy_de2shell_rtos.sh upload

# Rebuild bootloader + Quartus + flash (for RTL changes)
./run/deploy_de2shell_rtos.sh fpga

# Full rebuild + flash + upload (~4min)
./run/deploy_de2shell_rtos.sh full
```

Detailed deployment guide: [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

### de2shell (V2 frozen)

```bash
# One-command build (firmware + Quartus)
./build.sh app/de2shell

# Flash
./build.sh --flash app/de2shell
```

## Acceptance Status

### V2 — de2shell (frozen)

**v0.1 (V2) acceptance complete.** See [`doc/de2shell-module-acceptance.md`](doc/de2shell-module-acceptance.md).

- 192/213 items passed ✅
- VGA text terminal board-verified (640×480@60Hz)
- SDRAM 5-test self-check all PASS
- 11 course labs via expdemo multiplexer
- AES/SHA/SM4/SM3 + Zk* hardware acceleration verified
- IR remote channel-switch + passthrough verified
- LCD 16×2 display fix verified

### V3 — de2shell_rtos (in progress)

V3 track: FreeRTOS + SDRAM execution + PS/2 keyboard + VGA pixel GUI.

| Phase | Content | Software | Board |
|-------|---------|----------|-------|
| V3P1 | Foundation: CP437 256 chars, SDRAM exec baseline | ✅ Code complete | ⬜ Pending |
| V3P2 | ExpDemo: 5 code gap fixes | ✅ Code complete | ⬜ Pending |
| V3P3A | Pixel mode + GUI: TWM, full-screen Snake | ✅ Code complete | ⬜ Pending |
| V3P3B | Crypto visualization | Not started | — |
| V3P4A | Conway + PONG hardware engines | 🟡 Not integrated (QSF/stub/CLI) | — |
| V3P4B | Audio synth (DDS + FM) | 🟡 Sim passed, not in QSF | — |
| V3P4C | NTT accelerator | 🟡 Not in RTOS makefile/CLI | — |
| V3P5 | ChromaShader | Deferred (P4 priority) | — |

Detailed progress: [`doc/phases/de2os-rtos-status.md`](doc/phases/de2os-rtos-status.md)

## License

This project is released under the [MIT License](LICENSE). The NEORV32 submodule retains its original BSD-3-Clause license.
