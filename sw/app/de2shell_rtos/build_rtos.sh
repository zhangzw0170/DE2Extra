#!/bin/bash
# build_rtos.sh — Build de2shell_rtos (firmware + de2os Quartus compile)
#
# Usage: ./build_rtos.sh           (compile only)
#        ./build_rtos.sh --flash   (compile + JTAG program)

set -e

PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="app/de2shell_rtos"
FLASH=false

if [ "$1" = "--flash" ]; then
    FLASH=true
fi

# Step 1: Firmware (Docker)
echo "====== [1/3] Building firmware: $APP ======"
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${PROJ_ROOT}:/project" \
    de2extra-builder \
    bash -lc "export PATH=/opt/riscv/bin:\$PATH && \
        cd /project/sw/${APP} && \
        make clean NEORV32_HOME=/project/neorv32 && \
        mkdir -p build && \
        make image NEORV32_HOME=/project/neorv32"

# Image is already in neorv32/rtl/core/ — verify
IMGSZ=$(wc -c < "${PROJ_ROOT}/neorv32/rtl/core/neorv32_imem_image.vhd")
echo "  IMEM image: ${IMGSZ} bytes"

# Step 2: Quartus (de2os project)
echo ""
echo "====== [2/3] Quartus compile (de2os) ======"
QPF="par/de2os/de2os.qpf"
QUARTUS_SH="/e/Software/intelFPGA_lite/23.1std/quartus/bin64/quartus_sh.exe"
"${QUARTUS_SH}" --flow compile "$(cygpath -w "${PROJ_ROOT}/${QPF}")" -c de2os

echo "  Bitstream: par/de2os/output_files/de2os.sof"

# Step 3: Save build
BUILDDIR="builds/de2shell_rtos"
mkdir -p "${PROJ_ROOT}/${BUILDDIR}"
cp "${PROJ_ROOT}/par/de2os/output_files/de2os.sof" \
   "${PROJ_ROOT}/${BUILDDIR}/de2shell_rtos.sof"
echo ""
echo "  Saved: ${BUILDDIR}/de2shell_rtos.sof"

# Step 4: Flash (optional)
if [ "$FLASH" = true ]; then
    echo ""
    echo "====== [3/3] Programming FPGA ======"
    /e/Software/intelFPGA_lite/23.1std/quartus/bin64/quartus_pgm.exe \
        -m JTAG -o "p;${PROJ_ROOT}/${BUILDDIR}/de2shell_rtos.sof"
    echo "Done."
fi
