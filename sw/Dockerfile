FROM debian:bookworm-slim

ARG XPACK_VERSION=14.3.0-1

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VERSION}/xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-x64.tar.gz" \
    -O /tmp/riscv-gcc.tar.gz \
    && mkdir -p /opt/riscv \
    && tar -xzf /tmp/riscv-gcc.tar.gz -C /opt/riscv --strip-components=1 \
    && rm /tmp/riscv-gcc.tar.gz

ENV PATH="/opt/riscv/bin:${PATH}"

WORKDIR /build
