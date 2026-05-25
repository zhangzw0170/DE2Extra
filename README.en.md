# DE2Extra — NEORV32 RISC-V Full-Peripheral Terminal System

English | [中文](README.md)

> Turn the DE2-115 board into a complete computer: RISC-V CPU + VGA terminal + PS/2 keyboard + SDRAM + crypto acceleration + course lab multiplexer

## AI Disclosure

This project was developed with assistance from: [DeepSeek V4](https://chat.deepseek.com/), [GLM 5.1](https://chatglm.cn/), [GPT 5.4](https://chat.openai.com/). All AI-generated content has been manually reviewed.

## References

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V soft core used in this project
- [FreeRTOS](https://www.freertos.org/) — Real-time OS kernel used by de2os
- [DE2-115 System CD](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=506) — Terasic official examples and reference materials

## Overview

Runs the [NEORV32](https://github.com/stnolting/neorv32) RISC-V soft-core on a DE2-115 (Cyclone IV E) with custom Wishbone peripherals driving on-board hardware, running bare-metal C firmware as a multi-channel terminal system.

```
┌──────────────────────────────────────────────────┐
│  de2shell — Multi-channel terminal (bare-metal C)│
│  help / memtest / crypto / snake / life / dash   │
│  expdemo (11 course labs) / monitor / ps2 / ...  │
├──────────────────────────────────────────────────┤
│     NEORV32 RISC-V core (~4000 LUTs)             │
│     RV32IMC + Zicsr + Zicntr + Zk* crypto exts   │
├──────────────────────────────────────────────────┤
│  Custom VHDL peripherals (generic register IF)   │
│  VGA | PS/2 | LCD | IR | NTT | ExpDemo | ...     │
├──────────────────────────────────────────────────┤
│     DE2-115 FPGA (Cyclone IV E, 114K LEs)        │
└──────────────────────────────────────────────────┘
```

## Hardware Platform

**Primary**: Terasic DE2-115 (`EP4CE115F29C7`)

- **FPGA**: Cyclone IV E, 114,480 LEs, 266 multipliers, 4 PLLs
- **Memory**: 128MB SDRAM, 2MB SRAM, 8MB Flash, SD card slot
- **Display**: 16×2 LCD, 8 seven-segment displays, 27 LEDs (9G+18R), VGA (24-bit)
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

All custom peripherals use a generic register interface — not tied to any bus. Porting to a different board only requires changing the adapter layer.

| Module | Address | Description | Status |
|--------|---------|-------------|--------|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM controller, burst support | ✅ |
| `vga_text_terminal` | `0xF0000000` | 80×25 color text terminal, 640×480@60Hz | ✅ |
| `ps2_controller` | `0xF0002000` | PS/2 keyboard + FIFO + IRQ | ✅ |
| `ir_nec_wb` | `0xF0009000` | IR NEC protocol decoder | ✅ |
| `lcd_status` / `lcd_wb` | `0xF0008000` | HD44780 16×2 LCD | ✅ |
| `expdemo_wb` | `0xF000D000` | 11 course lab hardware multiplexer | ✅ |
| `ntt_sdf` | `0xF000C000` | NTT accelerator (q=3329, N=256) | 🟡 Compiles, needs board verify |
| `timer_wb` | `0xF0004000` | System timer | 🟡 Reserved |
| `intc_wb` | `0xF0006000` | Interrupt controller | 🟡 Reserved |

## Software Applications

| App | Description |
|-----|-------------|
| **de2shell** | Main firmware: CLI shell, memtest, crypto (AES/SHA/SM4+Zk* accel), snake, life, dashboard, expdemo, monitor, PS/2 |
| **de2os** | Experimental: FreeRTOS + SDRAM execution + ICACHE burst |
| **crypto_cli** | Standalone crypto CLI |
| **hello** | Phase 0 verification: LED chaser |
| **sdram_test** | SDRAM diagnostics |
| **ps2_test** | PS/2 scancode dump |
| **ir_test** | IR decoder test |

## Directory Layout

```
DE2Extra/
├── CLAUDE.md                  # AI agent guidelines
├── build.sh                   # One-command build (Git Bash)
├── neorv32/                   # NEORV32 RISC-V CPU (submodule)
├── src/rtl/
│   ├── de2_115_top.vhd        # de2shell top entity
│   ├── de2os_top.vhd          # de2os top entity (separate project)
│   ├── neorv32_wrapper.vhd    # CPU config wrapper
│   ├── bus/wb_intercon.vhd    # Wishbone interconnect
│   ├── periph/                # Peripheral controllers
│   ├── exp/                   # Course lab modules + adapters
│   └── lib/                   # Common packages (de2extra_pkg)
├── sw/app/
│   ├── de2shell/              # Main firmware
│   ├── de2os/                 # FreeRTOS firmware
│   ├── crypto_cli/            # Crypto CLI
│   └── ...                    # Other test apps
├── par/
│   ├── de2extra.qpf/qsf       # de2shell Quartus project
│   └── de2os/                 # de2os separate Quartus project
├── constraints/               # Pin assignments + timing (.sdc)
├── run/                       # Deploy scripts
└── doc/                       # Design docs, acceptance, phase plans
```

## Build

### Prerequisites

- Quartus Prime 23.1std Lite
- Docker Desktop (RISC-V cross-compilation)
- Git Bash (Windows)

### de2shell

```bash
# One-command build (firmware + Quartus)
./build.sh app/de2shell

# Flash
./build.sh --flash app/de2shell
```

Or manual steps:

```bash
# 1. Compile firmware
docker run --rm -v "$(pwd):/project" de2extra-builder bash -lc \
  'export PATH=/opt/riscv/bin:$PATH; cd /project/sw/app/de2shell && make clean && make image NEORV32_HOME=/project/neorv32'

# 2. Copy IMEM image
cp sw/app/de2shell/neorv32_imem_image.vhd src/rtl/

# 3. Quartus compile (GUI: Ctrl+L or CLI)
quartus_sh --flow compile par/de2extra -c de2extra
```

> **Important**: NEORV32 uses VHDL-2008. On first open, set Quartus: Assignments → Settings → VHDL Input → VHDL 2008.

### de2os (Experimental)

```bash
# Separate project, see doc/phases/de2os-debug.md
cd par/de2os && quartus_sh --flow compile de2os
```

## V2 Acceptance Status

**v0.1 (V2) acceptance complete.** See [`doc/de2shell-module-acceptance.md`](doc/de2shell-module-acceptance.md).

- 192/213 items passed ✅
- VGA text terminal board-verified (640×480@60Hz)
- SDRAM 5-test self-check all PASS
- 11 course labs via expdemo multiplexer
- AES/SHA/SM4/SM3 + Zk* hardware acceleration verified
- IR remote channel-switch + passthrough verified
- LCD 16×2 display fix verified

Deferred to V3 (de2os): NTT hardware acceleration, VGA pixel mode (Win 3.0 GUI), Exp6/7 gallery, snake Game Over display, audio subsystem, Conway/PONG/ChromaShader hardware engines, crypto visualization. V3 does not update de2shell — all new work goes to de2os (SDRAM exec + FreeRTOS + PS/2 keyboard primary input).

## License

This project is released under the [MIT License](LICENSE). The NEORV32 submodule retains its original BSD-3-Clause license.
