#!/bin/bash
# deploy_de2os.sh — de2os 全自动部署
#
# 用法 (Git Bash):
#   ./run/deploy_de2os.sh all      # 编译固件 + 综合 + 烧录 + 上传
#   ./run/deploy_de2os.sh flash    # 烧录 + 上传 (跳过编译)
#   ./run/deploy_de2os.sh upload   # 仅上传 (板子已在跑 bootloader)
#
# 烧录后自动上传，无需手动按键。
# 如果板子已在跑 bootloader，用 upload 即可 (需先按 KEY0)。

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUARTUS="/e/Software/intelFPGA_lite/23.1std/quartus/bin64"
SOF="$ROOT/par/de2os/de2os.sof"
BIN="$ROOT/sw/app/de2os/neorv32_exe.bin"
UPLOAD="$ROOT/run/upload_de2os.py"
COMPORT="${DE2OS_COM:-COM10}"

step() { echo ""; echo "=== $1 ==="; }

build_firmware() {
    step "Cross-compiling firmware"
    cd "$ROOT"
    MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/project" de2extra-builder \
        bash -lc "export PATH=/opt/riscv/bin:\$PATH && \
        cd /project/sw/app/de2os && \
        make clean NEORV32_HOME=/project/neorv32 && \
        make exe NEORV32_HOME=/project/neorv32" 2>&1 | tail -5
    echo "  -> $(wc -c < "$BIN") bytes"
}

build_quartus() {
    step "Quartus synthesis"
    "$QUARTUS/quartus_sh" --flow compile "$ROOT/par/de2os/de2os.qpf" 2>&1 | tail -3
}

flash_fpga() {
    step "Programming FPGA"
    # quartus_pgm needs Windows-style path
    local win_sof="$(cygpath -w "$SOF")"
    "$QUARTUS/quartus_pgm" -c 1 -m JTAG -o "P;$win_sof" 2>&1 | tail -5
}

upload_uart() {
    local wait_bootloader="$1"
    step "Uploading firmware via $COMPORT"
    if [ "$wait_bootloader" = "wait" ]; then
        echo "  Press KEY0 to reset, then upload starts..."
        python "$UPLOAD" "$COMPORT" "$BIN" --wait
    else
        echo "  Bootloader should be ready after JTAG config..."
        python "$UPLOAD" "$COMPORT" "$BIN"
    fi
}

case "${1:-all}" in
    all)
        build_firmware
        build_quartus
        flash_fpga
        upload_uart "nowait"
        ;;
    flash)
        flash_fpga
        upload_uart "nowait"
        ;;
    upload)
        upload_uart "wait"
        ;;
    *)
        echo "Usage: $0 {all|flash|upload}"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
