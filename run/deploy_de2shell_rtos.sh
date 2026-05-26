#!/bin/bash
# deploy_de2shell_rtos.sh — bootloader-first incremental deployment
#
# 用法 (Git Bash):
#   ./run/deploy_de2shell_rtos.sh inc        # 推荐: 增量更新 = app
#   ./run/deploy_de2shell_rtos.sh app        # 默认: 仅重编 app + 串口上传
#   ./run/deploy_de2shell_rtos.sh upload     # 仅上传当前 app
#   ./run/deploy_de2shell_rtos.sh fpga       # 重编 bootloader + Quartus + 烧录
#   ./run/deploy_de2shell_rtos.sh full       # fpga + app upload
#
# 说明:
# - V3 使用 sw/app/de2shell_rtos/ 作为固件目标
# - 板级工程仍是 par/de2os/de2os.qpf
# - 正常改 app 不需要 Quartus
# - 只有 bootloader / CPU IMEM 配置 / 顶层 RTL 改动才需要重建 FPGA

set -e
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_WIN="$(cygpath -w "$ROOT")"
QUARTUS="/e/Software/intelFPGA_lite/23.1std/quartus/bin64"
SOF="$ROOT/par/de2os/de2os.sof"
BIN="$ROOT/sw/app/de2shell_rtos/neorv32_exe.bin"
UPLOAD_COM="$ROOT/run/upload_de2os.py"
UPLOAD_JTAG="$ROOT/run/upload_de2os_jtag.tcl"
SCONSOLE="/e/Software/intelFPGA_lite/23.1std/quartus/sopc_builder/bin/system-console.exe"
PORT_RELEASE="$ROOT/run/release_de2os_ports.ps1"
HW_BUILD_INFO="$ROOT/run/gen_hw_build_info.py"
SW_BUILD_INFO="$ROOT/run/gen_sw_build_info.py"
COMPORT="${DE2OS_COM:-COM10}"
UPLOAD_MODE="${DE2OS_UPLOAD_MODE:-uart}"

step() { echo ""; echo "=== $1 ==="; }
timer_start() { STAGE_T0=$SECONDS; }
timer_end() { echo "  -> elapsed: $((SECONDS - STAGE_T0))s"; }
release_ports() { powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w "$PORT_RELEASE")" >/dev/null 2>&1 || true; }

trap release_ports EXIT

quartus_compile_with_progress() {
    local log="$ROOT/par/de2os/quartus_build.log"
    local pid
    local shown_map=0
    local shown_fit=0
    local shown_sta=0
    local shown_asm=0
    local last_tick=-1

    rm -f "$log"
    echo "  -> log: $log"
    echo "  -> checkpoint: Quartus compile started"

    "$QUARTUS/quartus_sh" --flow compile "$ROOT/par/de2os/de2os.qpf" -c de2os >"$log" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        if [ -f "$log" ]; then
            if [ "$shown_map" -eq 0 ] && grep -q "Analysis & Synthesis was successful" "$log"; then
                echo "  -> checkpoint: Analysis & Synthesis done"
                shown_map=1
            fi
            if [ "$shown_fit" -eq 0 ] && grep -q "Fitter was successful" "$log"; then
                echo "  -> checkpoint: Fitter done"
                shown_fit=1
            fi
            if [ "$shown_sta" -eq 0 ] && grep -q "Timing Analyzer was successful" "$log"; then
                echo "  -> checkpoint: Timing Analyzer done"
                shown_sta=1
            fi
            if [ "$shown_asm" -eq 0 ] && grep -q "Assembler was successful" "$log"; then
                echo "  -> checkpoint: Assembler done"
                shown_asm=1
            fi
        fi

        if [ $((SECONDS / 15)) -ne "$last_tick" ]; then
            last_tick=$((SECONDS / 15))
            echo "  -> checkpoint: Quartus still running (${SECONDS}s elapsed)"
        fi

        sleep 5
    done

    wait "$pid"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  -> checkpoint: Quartus failed, last 40 log lines:"
        tail -40 "$log"
        return "$rc"
    fi

    tail -5 "$log"
}

docker_make() {
    local rel_dir="$1"
    local target="$2"
    MSYS_NO_PATHCONV=1 docker run --rm -e TZ=Asia/Shanghai -v "$ROOT_WIN:/project" de2extra-builder \
        bash -c "cd /project/$rel_dir && \
        /usr/bin/make clean NEORV32_HOME=/project/neorv32 RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf- && \
        mkdir -p build && \
        /usr/bin/make $target NEORV32_HOME=/project/neorv32 RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf-"
}

build_firmware() {
    step "Cross-compiling de2shell_rtos"
    timer_start
    release_ports
    python "$HW_BUILD_INFO" sync
    python "$SW_BUILD_INFO"
    docker_make "sw/app/de2shell_rtos" "exe"
    echo "  -> $(wc -c < "$BIN") bytes"
    timer_end
}

build_bootloader() {
    step "Rebuilding NEORV32 bootloader"
    timer_start
    docker_make "neorv32/sw/bootloader" "bootloader"
    echo "  -> boot ROM image refreshed"
    timer_end
}

build_quartus() {
    step "Quartus synthesis"
    timer_start
    quartus_compile_with_progress
    timer_end
}

flash_fpga() {
    step "Programming FPGA"
    timer_start
    local win_sof="$(cygpath -w "$SOF")"
    "$QUARTUS/quartus_pgm" -c 1 -m JTAG -o "P;$win_sof" 2>&1 | tail -5
    timer_end
}

upload_uart() {
    local wait_bootloader="$1"
    step "Uploading firmware via $COMPORT"
    timer_start
    release_ports
    if [ "$UPLOAD_MODE" = "uart" ]; then
        if [ "$wait_bootloader" = "wait" ]; then
            echo "  Press KEY0 to reset, then upload starts..."
            python "$UPLOAD_COM" "$COMPORT" "$BIN" --wait
        else
            echo "  Bootloader should be ready after JTAG config..."
            python "$UPLOAD_COM" "$COMPORT" "$BIN"
        fi
    else
        local win_script="$(cygpath -w "$UPLOAD_JTAG")"
        local win_bin="$(cygpath -w "$BIN")"
        if [ "$wait_bootloader" = "wait" ]; then
            echo "  Waiting for bootloader via JTAG UART. Press KEY0 to reset..."
            "$SCONSOLE" --script="$win_script" "$win_bin" --wait
        else
            echo "  Bootloader should be ready after JTAG config..."
            "$SCONSOLE" --script="$win_script" "$win_bin"
        fi
    fi
    release_ports
    timer_end
}

case "${1:-app}" in
    inc|app)
        build_firmware
        upload_uart "wait"
        ;;
    full)
        python "$HW_BUILD_INFO" regen
        build_firmware
        build_bootloader
        build_quartus
        flash_fpga
        upload_uart "nowait"
        ;;
    fpga)
        build_bootloader
        build_quartus
        flash_fpga
        ;;
    upload)
        upload_uart "wait"
        ;;
    *)
        echo "Usage: $0 {inc|app|upload|fpga|full}"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
