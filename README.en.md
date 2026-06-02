# DE2Extra — NEORV32 RISC-V Full-Peripheral Terminal System

English | [中文](README.md)

> A complete RISC-V computer on the DE2-115: FreeRTOS multi-task + VGA pixel GUI + PS/2 keyboard + 13 Wishbone peripherals + 22 CLI commands

## References

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V soft core (submodule, v1.13.1)
- [FreeRTOS](https://www.freertos.org/) — Real-time OS kernel

## Overview

```
┌─────────────────────────────────────────────────────┐
│  de2shell_rtos — FreeRTOS multi-task terminal (V3) │
│  22 CLI commands, 4 tasks, SDRAM exec, PS/2 input  │
├─────────────────────────────────────────────────────┤
│       NEORV32 RISC-V core (~4000 LUTs)              │
│       RV32IMC + Zicsr + Zicntr + Zk* crypto exts   │
├─────────────────────────────────────────────────────┤
│  13 Wishbone slave peripherals                      │
│  SDRAM | VGA (RGB565) | PS/2 | LCD | IR | NTT |     │
│  ExpDemo | PONG | Conway | Synth | GPU 2D | BuildInfo│
├─────────────────────────────────────────────────────┤
│       DE2-115 FPGA (Cyclone IV E, 114K LEs)         │
└─────────────────────────────────────────────────────┘
```

## Peripheral Address Map

| Module | Address | Description | Status |
|--------|---------|-------------|--------|
| `sdram_ctrl` | `0x01000000` | 128MB SDRAM, burst, async FIFO CDC | ✅ |
| `vga_text_terminal` | `0xF0000000` | 80×30 text + 640×480 RGB565 pixel mode | ✅ |
| `ps2_controller` | `0xF0008000` | PS/2 keyboard, RTOS primary input | ✅ |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD | ✅ |
| `ntt_sdf` | `0xF000F000` | NTT accelerator (q=3329, N=256) | 🟡 busy-wait |
| `expdemo_wb` | `0xF0010000` | 13 course lab hardware multiplexer | ✅ |
| `pong_engine` | `0xF0011000` | PONG hardware engine | 🟡 Pending verify |
| `conway_engine` | `0xF0012000` | Conway's Game of Life engine | 🟡 Pending verify |
| `synth_engine` | `0xF0013000` | Audio synth (3xOSC + DX7 FM + WM8731) | 🟡 Pending verify |
| `gpu_2d` | `0xF0015000` | 2D GPU, FILL rect burst write | 🟡 Pending verify |

## CLI Commands (22)

hello, memtest, crypto, ps2, snake, life, info, expdemo, twm, conwayhw, ponghw, ntt, synth, pxtest, vgadump, vgam, stats, heapstat, cpustat, clear, monitor, demo

## Directory Layout

```
DE2Extra/
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/                   # VHDL source
│   ├── de2os_top.vhd          # V3 top entity (single Quartus project)
│   ├── bus/wb_intercon.vhd    # 1 master, 13 slaves
│   ├── periph/                # Peripheral controllers
│   └── lib/                   # Common packages
├── sw/
│   ├── lib/                   # Shared library (HAL, program sources, TWM, GFX)
│   ├── app/de2shell_rtos/    # Main firmware (FreeRTOS + SDRAM)
│   └── app/crypto_cli/       # Crypto library (AES/SHA/SM4)
├── par/de2os/                 # Quartus project
├── run/                       # Deploy scripts
├── doc/                       # Documentation
└── doc/archive/               # Archived docs (git ignored)
```

## Build

Detailed guide: [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

> **Bash environment**: All `bash` / `sh` scripts must run in **Git Bash** — not WSL's `bash.exe`, PowerShell, or CMD. Replace `bash` in the commands below with the absolute path to your local Git Bash, e.g. `E:/Software/Scoop/apps/git/current/bin/bash.exe`.

**Software changes (C code)**:
```bash
# Compile (~25s)
docker run --rm -v "E:/Main/JuniorII/NonExam/FPGA/DE2Extra:/work" de2extra-builder bash -c \
  "cd /work && mkdir -p sw/app/de2shell_rtos/build && make -C sw/app/de2shell_rtos all image NEORV32_HOME=/work/neorv32"

# Upload (~5s, board must be in bootloader state)
python run/upload_de2os.py COM10 sw/app/de2shell_rtos/neorv32_raw_exe.bin
```

**RTL changes (VHDL)**: Open `par/de2os/de2os.qpf` in Quartus GUI, Ctrl+L to compile, Programmer to flash `par/de2os/de2os.sof`, then upload firmware.

## Acceptance Status

305/358 items passed (85%). See [`doc/de2shell-module-acceptance.md`](doc/de2shell-module-acceptance.md).

V3 milestones: SDRAM exec ✅ | FreeRTOS 4 tasks ✅ | VGA text+pixel ✅ | TWM window manager ✅ | GPU 2D RTL ✅ | Conway/PONG/NTT/Synth RTL ✅ | 7h+ stability no crash ✅

## License

[MIT License](LICENSE). NEORV32 submodule retains BSD-3-Clause.
