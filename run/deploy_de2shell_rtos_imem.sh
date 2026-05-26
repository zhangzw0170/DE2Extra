#!/bin/bash
# deploy_de2shell_rtos_imem.sh — V3 IMEM bring-up
#
# 目标:
# - 直接把 de2shell_rtos 安装为 128KB IMEM 镜像
# - 使用 de2os_imem_top 直启，绕过当前板外 RS-232 上传链路

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_WIN="$(cygpath -w "$ROOT")"
QUARTUS="/e/Software/intelFPGA_lite/23.1std/quartus/bin64"
SOF="$ROOT/par/de2os/de2os.sof"

step() { echo ""; echo "=== $1 ==="; }

build_imem_firmware() {
    step "Building de2shell_rtos IMEM image"
    docker run --rm -v "$ROOT_WIN:/project" de2extra-builder \
        bash -lc "cd /project/sw/app/de2shell_rtos && \
        /usr/bin/make clean NEORV32_HOME=/project/neorv32 RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf- && \
        mkdir -p build && \
        /usr/bin/make install NEORV32_HOME=/project/neorv32 RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf- \
        USER_FLAGS='-DDE2SHELL_RTOS -Wl,--defsym,__neorv32_rom_size=128k -Wl,--defsym,__neorv32_ram_size=16k -T de2shell_rtos.ld'"
}

build_quartus() {
    step "Quartus synthesis"
    local log_file="$ROOT/par/de2os/quartus_imem_build.log"
    "$QUARTUS/quartus_sh" --flow compile "$ROOT/par/de2os/de2os.qpf" -c de2os >"$log_file" 2>&1
    tail -5 "$log_file"
}

flash_fpga() {
    step "Programming FPGA"
    local win_sof="$(cygpath -w "$SOF")"
    local log_file="$ROOT/par/de2os/quartus_imem_flash.log"
    "$QUARTUS/quartus_pgm" -c 1 -m JTAG -o "P;$win_sof" >"$log_file" 2>&1
    tail -5 "$log_file"
}

case "${1:-all}" in
    all)
        build_imem_firmware
        build_quartus
        flash_fpga
        ;;
    build)
        build_imem_firmware
        build_quartus
        ;;
    flash)
        flash_fpga
        ;;
    *)
        echo "Usage: $0 {all|build|flash}"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
