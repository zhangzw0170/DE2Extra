<p align="center">
  <img src="doc/promo/banner.svg" alt="DE2Extra Banner" width="100%">
</p>

<h3 align="center">
  DE2Extra: From DE2-115 to a RISC-V Computer
</h3>

<p align="center">
  <img src="https://img.shields.io/badge/CPU-NEORV32_RV32IMC-e94560" alt="CPU">
  <img src="https://img.shields.io/badge/FPGA-Cyclone_IV_E-00d4ff" alt="FPGA">
  <img src="https://img.shields.io/badge/RTOS-FreeRTOS_V11.3-f39c12" alt="RTOS">
  <img src="https://img.shields.io/badge/Peripherals-10_Wishbone-66f4a0" alt="Peripherals">
  <img src="https://img.shields.io/badge/License-MIT-66f4a0" alt="License">
</p>

<p align="center">
  English | <a href="README.md">中文</a>
</p>

---

## Overview

DE2Extra is a complete RISC-V SoC system built around the [NEORV32](https://github.com/stnolting/neorv32) soft core, running on the Altera DE2-115 (Cyclone IV E, 114K LEs) FPGA. Around the open-source CPU core, we developed 12 Wishbone peripheral IPs, SoC interconnect, FreeRTOS firmware, and 20 CLI applications.

| | |
|---|---|
| **CPU** | NEORV32 v1.13.1 · RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh |
| **Bus** | Wishbone B4 · 1 master / 12 slaves (10 active) · 32-bit · combinational address decode |
| **Firmware** | FreeRTOS V11.3 · 4 tasks (uart_input/shell/active/status) |
| **Boot** | Boot mode 0: 2KB IMEM bootloader → UART upload → SDRAM @ `0x01000000` (~206KB) |
| **Display** | VGA 640×480 @60Hz · 80×30 text mode + RGB565 pixel mode · GPU 2D FILL |
| **Input** | PS/2 keyboard (primary) · UART 115200 · IR NEC remote |
| **Audio** | 3×OSC + DX7 FM synthesis · WM8731 I2S DAC *(disabled)* |
| **Acceleration** | AES-128 hardware **107.6×** speedup · Conway HW engine |
| **Board** | SDRAM 128MB · HD44780 LCD 16×2 · 7-SEG ×8 · LED ×24 |

## System Architecture

<p align="center">
  <img src="doc/promo/architecture.svg" alt="System Architecture">
</p>

See also: [Interactive Architecture Diagram](doc/promo/architecture.html) · [Presentation Slides](doc/promo/slides.html)

## Peripheral Map

| Peripheral | Address | Description | Board |
|------------|---------|-------------|:-----:|
| `sdram_ctrl` | `0x01000000` | 128MB, burst, async FIFO CDC | ✅ |
| `vga_text_terminal` | `0xF0000000` | 80×30 text + 640×480 RGB565 pixel | ✅ |
| `ps2_controller` | `0xF0008000` | PS/2 keyboard, scancode + IRQ | ✅ |
| `build_info_wb` | `0xF0009000` | HW/SW version ROM | ⚠️ |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD | ✅ |
| `ir_nec_wb` | `0xF000C000` | NEC IR decoder | ✅ |
| `ntt_sdf` | `0xF000F000` | Software NTT (HW disabled) | ⚠️ |
| `expdemo_wb` | `0xF0010000` | 13 course lab hardware multiplexer | ✅ |
| `conway_engine` | `0xF0011000` | Conway 64×25 hardware engine | ✅ |
| `synth_engine` | `0xF0012000` | 3×OSC + DX7 FM, WM8731 *(disabled)* | — |
| `gpu_2d` | `0xF0015000` | FILL rect, SDRAM burst write | ✅ |

Full board verification status: [`doc/phases/de2os-rtos-status.md`](doc/phases/de2os-rtos-status.md)

## CLI Commands (20 + help)

**Interactive programs** (F1=help, F10=quit):

`hello` · `crypto` · `ps2` · `snake` · `conway` · `info` · `riscvasm` · `expdemo` · `twm` · `ntt` · ~~`synth`~~ · `pforth` · `cryptoviz`

**Utility commands**:

`selfcheck` · `stats` · `ver` · `clear` · `pxtest` · `vgadump` · `vgamon`

## Directory Layout

```
DE2Extra/
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/                   # VHDL source
│   ├── de2os_top.vhd          # Top entity (single Quartus project)
│   ├── bus/wb_intercon.vhd    # 1 master / 12 slave address decode
│   ├── periph/                # 12 peripheral controllers
│   └── lib/                   # Common packages (de2extra_pkg, etc.)
├── sw/
│   ├── lib/                   # Shared library (HAL, programs, TWM, GFX)
│   ├── app/de2shell_rtos/    # Main firmware (FreeRTOS + SDRAM)
│   └── app/crypto_cli/       # Crypto library (AES/SHA/SM4)
├── par/de2os/                 # Quartus project
├── run/                       # Deploy scripts
├── doc/                       # Documentation + promo materials
│   └── promo/                 # Architecture diagram, slides, banner
└── sw/app/common/             # Shared headers
```

## Build

Detailed guide (Chinese): [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

> **Bash environment**: All `bash` / `sh` scripts must run in **Git Bash** — not WSL's `bash.exe`, PowerShell, or CMD. Replace `bash` in the commands below with the absolute path to your local Git Bash, e.g. `E:/Software/Scoop/apps/git/current/bin/bash.exe`.

**Quick deploy**:
```bash
./run/deploy_de2shell_rtos.sh inc    # Incremental: recompile app + upload (~25s)
./run/deploy_de2shell_rtos.sh full   # Full: app + bootloader + Quartus + flash + upload
```

**Manual build & upload**:
```bash
docker run --rm -v "E:/Main/JuniorII/NonExam/FPGA/DE2Extra:/work" de2extra-builder bash -c \
  "cd /work && mkdir -p sw/app/de2shell_rtos/build && make -C sw/app/de2shell_rtos all image NEORV32_HOME=/work/neorv32"

python run/upload_de2os.py --wait
```

## Performance

| Metric | Value |
|--------|-------|
| Clock | 50 MHz |
| FPGA utilization | ~24% (27K / 114K LEs) |
| AES hardware speedup | 107.6× (vs software) |
| Firmware size | ~206KB (SDRAM exec) |
| Incremental deploy | ~25s (compile + upload) |
| Stability test | 7h38m no crash |

## References

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V soft core (v1.13.1, BSD-3-Clause)
- [FreeRTOS](https://www.freertos.org/) — Real-time OS kernel (MIT)
- [Wishbone B4 Specification](https://opencores.org/) — On-chip bus protocol
- [DE2-115 User Manual](https://www.terasic.com.tw) — Development board docs
- [WM8731 Datasheet](https://www.cirrus.com) — Audio CODEC
- [RISC-V Privileged Specification](https://riscv.org) — ISA specification

## License

This project is released under the [MIT License](LICENSE).

Third-party components:

| Component | License |
|-----------|---------|
| [NEORV32](https://github.com/stnolting/neorv32) RISC-V Processor | BSD-3-Clause |
| [FreeRTOS](https://www.freertos.org/) V11.3 Kernel | MIT |
| [RISC-V ISA](https://riscv.org) Specifications | CC-BY-4.0 |
| [Wishbone B4](https://opencores.org/) Specification | OpenCores License |
