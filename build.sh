#!/bin/bash
# DE2Extra 一键构建脚本
# 用法:
#   ./build.sh [app]          — 固件+Quartus增量编译（默认 sdram_test）
#   ./build.sh app/hello    — 编译 hello 固件
#   ./build.sh --flash [app]  — 编译后自动烧录
set -e

APP="${1:-app/sdram_test}"
FLASH=false
if [ "$APP" = "--flash" ]; then
    FLASH=true
    APP="${2:-app/sdram_test}"
fi

PROJ_ROOT="$(cd "$(dirname "$0")" && pwd)"
# Windows native path for Quartus (avoids MSYS double-conversion)
PROJ_ROOT_WIN="$(cygpath -w "$PROJ_ROOT")"
QPF="par/de2extra.qpf"
QUARTUS_SH="/e/Software/intelFPGA_lite/23.1std/quartus/bin64/quartus_sh.exe"

# ================================================================
# Step 1: 固件编译 (Docker)
# ================================================================
echo "====== [1/3] Building firmware: $APP ======"
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${PROJ_ROOT}:/project" \
    de2extra-builder \
    bash -c "cd /project/sw/${APP} && make clean all image NEORV32_HOME=/project/neorv32"

cp "${PROJ_ROOT}/neorv32/rtl/core/neorv32_imem_image.vhd" "${PROJ_ROOT}/src/rtl/neorv32_imem_image.vhd"

ACTUAL=$(grep -o 'image_size_c : natural := [0-9]*' "${PROJ_ROOT}/src/rtl/neorv32_imem_image.vhd" | head -1 | grep -o '[0-9]*')
echo "  IMEM image: ${ACTUAL} bytes"

# ================================================================
# Step 2: Quartus 增量编译
# ================================================================
echo ""
echo "====== [2/3] Quartus incremental compile ======"
"${QUARTUS_SH}" --flow compile "${PROJ_ROOT_WIN}\\par\\de2extra" -c de2extra

echo "  Bitstream: par/de2extra.sof"

# ================================================================
# Step 3: 烧录 (可选)
# ================================================================
if [ "$FLASH" = true ]; then
    echo ""
    echo "====== [3/3] Programming FPGA ======"
    "${QUARTUS_SH%/*}/quartus_pgm.exe" -m jtag -o "p;${PROJ_ROOT_WIN}\\par\\de2extra.sof"
    echo "  Done."
else
    echo ""
    echo "  Run ./build.sh --flash $APP to also program the FPGA."
fi

echo ""
echo "====== Done ======"
