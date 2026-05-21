#!/bin/bash
# DE2Extra software build wrapper (Docker)
# Usage: ./build.sh [app_dir]
#   app_dir defaults to app/hello
set -e

APP_DIR="${1:-app/hello}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_ROOT="$(dirname "$SCRIPT_DIR")"

IMAGE_NAME="de2extra-builder"
DOCKERFILE="$SCRIPT_DIR/Dockerfile"

# Build image if not exists
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building Docker image (first time only)..."
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$SCRIPT_DIR"
fi

# Run build inside container
# MSYS_NO_PATHCONV prevents Git Bash from rewriting /project to a Windows path
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "$PROJ_ROOT:/project" \
    "$IMAGE_NAME" \
    bash -c "cd /project/sw/$APP_DIR && make clean all image NEORV32_HOME=/project/neorv32"

# Copy generated IMEM image to src/rtl/ (outside submodule)
cp "$PROJ_ROOT/neorv32/rtl/core/neorv32_imem_image.vhd" "$PROJ_ROOT/src/rtl/neorv32_imem_image.vhd"
echo "IMEM image copied to src/rtl/neorv32_imem_image.vhd"
echo "Now recompile in Quartus to bake the software into the bitstream."
