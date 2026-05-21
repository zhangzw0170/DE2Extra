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
docker run --rm \
    -v "$PROJ_ROOT:/project" \
    "$IMAGE_NAME" \
    bash -c "cd /project/sw/$APP_DIR && make clean all image NEORV32_HOME=/project/neorv32"
