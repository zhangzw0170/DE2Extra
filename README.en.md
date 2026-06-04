<p align="center">
  <img src="doc/promo/banner.svg" alt="DE2Extra Banner" width="100%">
</p>

<h3 align="center">
  DE2Extra: A RISC-V SoC on the DE2-115
</h3>

<p align="center">
  <img src="https://img.shields.io/badge/CPU-NEORV32_RV32IMC-e94560" alt="CPU">
  <img src="https://img.shields.io/badge/FPGA-Cyclone_IV_E-00d4ff" alt="FPGA">
  <img src="https://img.shields.io/badge/RTOS-FreeRTOS_V11.3-f39c12" alt="RTOS">
  <img src="https://img.shields.io/badge/Peripherals-10_Active_Wishbone-66f4a0" alt="Peripherals">
  <img src="https://img.shields.io/badge/License-MIT-66f4a0" alt="License">
</p>

<p align="center">
  English | <a href="README.md">中文</a>
</p>

---

## Overview

DE2Extra is a complete RISC-V SoC system built around the [NEORV32](https://github.com/stnolting/neorv32) soft core, running on the Altera DE2-115 (Cyclone IV E, 114K LEs) FPGA. Around the open-source CPU core, we developed 10 active Wishbone peripheral IPs, SoC interconnect, FreeRTOS firmware, and 22 CLI applications.

| | |
|---|---|
| **CPU** | NEORV32 v1.13.1 · RV32IMC + Zicsr + Zicntr + Zbkb/Zbkc/Zbkx/Zknd/Zkne/Zknh/Zksed/Zksh |
| **Bus** | Wishbone B4 · 1 master / 12 slaves (10 active, 2 stub) · 32-bit · combinational address decode |
| **Firmware** | FreeRTOS V11.3 · 4 tasks (uart_input/shell/active/status) · ~207KB |
| **Boot** | Boot mode 0: 2KB IMEM bootloader → UART upload → SDRAM @ `0x01000000` |
| **Display** | VGA 640×480 @60Hz · 80×30 text mode + RGB565 pixel mode · GPU 2D FILL |
| **Input** | PS/2 keyboard (primary) · UART 115200 · IR NEC remote |
| **Acceleration** | AES-128 hardware **107.6×** speedup · Conway 64×25 hardware engine |
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
| `build_info_wb` | `0xF0009000` | HW/SW version ROM | ✅ |
| `lcd_wb` | `0xF000B000` | HD44780 16×2 LCD | ✅ |
| `ir_nec_wb` | `0xF000C000` | NEC IR decoder | ✅ |
| `ntt_sdf` | `0xF000F000` | NTT accelerator (HW removed from synthesis, SW fallback) | ⚠️ |
| `expdemo_wb` | `0xF0010000` | 13 course lab hardware multiplexer | ✅ |
| `conway_engine` | `0xF0011000` | Conway 64×25 hardware engine | ✅ |
| `synth_engine` | `0xF0012000` | 3×OSC + DX7 FM, WM8731 *(HW removed)* | — |
| `gpu_2d` | `0xF0015000` | FILL rect, SDRAM burst write | ✅ |

Full board verification status: [`doc/phases/de2os-rtos-status.md`](doc/phases/de2os-rtos-status.md)

## CLI Commands (22)

**Interactive programs** (F1=help, F10=quit):

`hello` · `crypto` · `ps2` · `snake` · `conway` · `info` · `riscvasm` · `expdemo` · `twm` · `ntt` · ~~`synth`~~ · `pforth` · `cryptoviz`

**Utility commands**:

`selfcheck` · `postverify` · `stats` · `ver` · `clear` · `pxtest` · `vgadump` · `vgamon`

## Directory Layout

```
DE2Extra/
├── neorv32/                   # NEORV32 RISC-V CPU (submodule, v1.13.1)
├── src/rtl/                   # VHDL source
│   ├── de2os_top.vhd          # Top entity (single Quartus project)
│   ├── bus/wb_intercon.vhd    # 1 master / 12 slave address decode
│   ├── periph/                # 12 peripheral controllers (10 active, 2 removed)
│   └── lib/                   # Common packages (de2extra_pkg, build_info_pkg, etc.)
├── sw/
│   ├── lib/                   # Shared library (HAL, programs, TWM, GFX, pForth)
│   ├── app/de2shell_rtos/    # Main firmware (FreeRTOS + SDRAM)
│   └── app/crypto_cli/       # Crypto library (AES/SHA/SM4)
├── par/de2os/                 # Quartus project
├── run/                       # Deploy scripts (deploy, upload)
└── doc/                       # Documentation + promo materials
    └── promo/                 # Architecture diagram, slides, banner
```

## Build

Detailed guide (Chinese): [`doc/编译烧录前必看.md`](doc/编译烧录前必看.md)

**CLI tool (cross-platform)**:
```bash
pip install pyserial                                                    # First-time setup
python run/de2extra.py sw-build && python run/de2extra.py sw-upload    # Software changes (~45s)
python run/de2extra.py hw-build && python run/de2extra.py hw-flash     # Hardware changes (~15min)
```

**Legacy scripts (Git Bash only)**:
```bash
./run/deploy_de2shell_rtos.sh inc    # Incremental: recompile app + upload
./run/deploy_de2shell_rtos.sh full   # Full: app + bootloader + Quartus + flash + upload
```

**Local simulation** (no FPGA needed):
```bash
cd sw/lib && make run    # SDL2 pixel-mode shell, requires GCC 15+ and SDL2
```

## Performance

| Metric | Value |
|--------|-------|
| Clock | 50 MHz |
| FPGA utilization | ~47% (53.5K / 114.5K LEs) |
| AES hardware speedup | 100+x (vs software) |
| Firmware size | ~207KB (SDRAM exec) |
| Software incremental deploy | ~45s (compile ~25s + upload ~20s) |
| Hardware full build | ~15min (bootloader + Quartus synthesis) |
| Stability test | 7h38m no crash |

## References

- [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) — RISC-V soft core (v1.13.1 + local patches, BSD-3-Clause)
- [FreeRTOS](https://www.freertos.org/) — Real-time OS kernel (MIT)
- [Wishbone B4 Specification](https://opencores.org/howto/wishbone) — On-chip bus protocol
- [DE2-115 User Manual](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502) — Development board docs
- [RISC-V Privileged Specification](https://riscv.org/specifications/) — ISA specification

## NEORV32 Local Patches

The submodule is pinned at upstream **v1.13.1** with 1 local commit (`72fbfc57`). Changes are confined to the bootloader only; the CPU core RTL is unmodified.

| Change | File | Detail |
|--------|------|--------|
| UART baud: 19200 → 115200 | `sw/bootloader/config.h` | Match our board setup |
| Auto-boot timeout: 8s → 1s | `sw/bootloader/config.h` | Faster boot cycle |
| SPI flash: disabled | `sw/bootloader/config.h` | Not used on DE2-115 |
| SDRAM self-test on boot | `sw/bootloader/main.c` + `hal/` | Validates SDRAM before upload |
| SDRAM resume after KEY0 reset | `sw/bootloader/main.c` | Reads marker at `0x018FFFF0` to re-boot last uploaded image without re-download |
| VGA mirror + upload progress | `hal/source/uart.c`, `system.c` | Mirrors bootloader output to VGA, shows upload progress bar |

## AI Usage Declaration

This project used AI-assisted development throughout its lifecycle. All AI-generated code was reviewed, tested on hardware, and modified as needed before inclusion.

| Category | Tools Used |
|----------|-----------|
| Models | GLM 5.1, DeepSeek V4, GPT 5.4 |
| Harness | Claude Code, DeepSeek TUI, Codex |

## Disclaimer

This project is for learning and research purposes only. Following this guide involves FPGA bitstream flashing, SDRAM read/write, and other hardware operations — **make sure you know what you are doing**. The author is not responsible for any damage to development boards, data loss, or other losses caused by improper operation.

## License

This project is released under the [MIT License](LICENSE).

Third-party components:

| Component | License |
|-----------|---------|
| [NEORV32](https://github.com/stnolting/neorv32) RISC-V Processor (v1.13.1 + local patches) | BSD-3-Clause |
| [FreeRTOS](https://www.freertos.org/) V11.3 Kernel | MIT |
| [RISC-V ISA](https://riscv.org) Specifications | CC-BY-4.0 |
| [Wishbone B4](https://opencores.org/howto/wishbone) Specification | OpenCores License |
