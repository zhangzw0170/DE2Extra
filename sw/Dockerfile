FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY riscv-gcc.tar.gz /tmp/riscv-gcc.tar.gz
RUN mkdir -p /opt/riscv \
    && tar -xzf /tmp/riscv-gcc.tar.gz -C /opt/riscv --strip-components=1 \
    && rm /tmp/riscv-gcc.tar.gz

ENV PATH="/opt/riscv/bin:${PATH}"

WORKDIR /build
