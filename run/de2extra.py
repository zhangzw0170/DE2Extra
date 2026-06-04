#!/usr/bin/env python3
"""DE2Extra build & deploy CLI.

Subcommands:
  sw-build    Cross-compile firmware (Docker)
  sw-upload   Upload firmware via UART
  hw-build    Quartus synthesis (FPGA bitstream)
  hw-flash    Program FPGA via JTAG
  full        hw-build + hw-flash + sw-build + sw-upload
  inc         sw-build + sw-upload (incremental, no Quartus)

Usage:
  python run/de2extra.py sw-build
  python run/de2extra.py sw-upload [--port PORT]
  python run/de2extra.py hw-build
  python run/de2extra.py hw-flash
  python run/de2extra.py full [--port PORT]
  python run/de2extra.py inc [--port PORT]
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCKER_IMAGE = "de2extra-builder"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(msg, flush=True)


def step(name: str) -> None:
    print(f"\n{'='*60}\n  {name}\n{'='*60}", flush=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run command, raise on failure."""
    log(f"  $ {' '.join(str(c) for c in cmd)}")
    try:
        result = subprocess.run(cmd, cwd=str(ROOT), **kwargs)
    except FileNotFoundError:
        log(f"ERROR: Command not found: {cmd[0]}")
        sys.exit(1)
    if result.returncode != 0:
        sys.exit(result.returncode)
    return result


def project_root() -> Path:
    return ROOT


# ---------------------------------------------------------------------------
# Auto-detect
# ---------------------------------------------------------------------------

def detect_serial_port() -> str:
    """Auto-detect the first likely DE2-115 serial port."""
    env = os.getenv("DE2OS_COM")
    if env:
        return env

    system = platform.system()
    if system == "Windows":
        # Try COM ports 2..20
        import serial.tools.list_ports as lp
        for p in sorted(lp.comports(), key=lambda x: x.device):
            return p.device
        return "COM10"
    elif system == "Darwin":
        # macOS: /dev/cu.usbserial-*
        for p in sorted(Path("/dev").glob("cu.usbserial*")):
            return str(p)
        return "/dev/cu.usbserial-0001"
    else:
        # Linux: /dev/ttyUSB*
        for p in sorted(Path("/dev").glob("ttyUSB*")):
            return str(p)
        return "/dev/ttyUSB0"


def detect_quartus() -> Path | None:
    """Find Quartus installation directory (containing quartus_sh)."""
    env = os.getenv("QUARTUS_ROOTDIR")
    if env:
        p = Path(env)
        if (p / "bin" / "quartus_sh").exists() or (p / "bin64" / "quartus_sh").exists():
            return p
        if (p / "quartus_sh").exists():
            return p

    system = platform.system()
    if system == "Windows":
        candidates: list[Path] = []
        # Scan all drives for standard install locations
        for drive in (f"{d}:" for d in "CDEFGH" if Path(f"{d}:").exists()):
            for edition in ("intelFPGA_lite", "intelFPGA"):
                for ver in ("23.1std", "24.1std", "22.1std"):
                    for parent in ("", "Software/"):
                        candidates.append(Path(f"{drive}/{parent}{edition}/{ver}/quartus"))
    elif system == "Linux":
        candidates = [
            Path.home() / "intelFPGA_lite" / "23.1std" / "quartus",
            Path("/opt/intelFPGA_lite/23.1std/quartus"),
            Path("/opt/intelFPGA/23.1std/quartus"),
        ]
    elif system == "Darwin":
        candidates = []
    else:
        candidates = []

    for c in candidates:
        if c.exists():
            return c

    # Try PATH
    qsh = shutil.which("quartus_sh")
    if qsh:
        return Path(qsh).parent.parent

    return None


def quartus_bin(quartus_root: Path, name: str) -> str:
    """Return the path to a Quartus binary, preferring bin64 on Windows."""
    system = platform.system()
    if system == "Windows":
        p64 = quartus_root / "bin64" / f"{name}.exe"
        if p64.exists():
            return str(p64)
        p32 = quartus_root / "bin" / f"{name}.exe"
        if p32.exists():
            return str(p32)
    else:
        for sub in ("bin", "bin64"):
            p = quartus_root / sub / name
            if p.exists():
                return str(p)
    # Fallback: hope it's on PATH
    return name


def detect_docker() -> str | None:
    """Return docker executable path, or None if unavailable."""
    return shutil.which("docker")


def root_for_docker() -> str:
    """Return project root as a Docker-mountable path."""
    system = platform.system()
    r = str(ROOT).replace("\\", "/")
    if system == "Windows":
        # Git Bash / MSYS2 path conversion; also works for Docker Desktop
        if len(r) >= 2 and r[1] == ":":
            return f"/{r[0].lower()}{r[2:]}"
    return r


# ---------------------------------------------------------------------------
# Build info generation
# ---------------------------------------------------------------------------

def gen_build_info(mode: str = "sync") -> None:
    """Run gen_hw_build_info.py and gen_sw_build_info.py."""
    hw = ROOT / "run" / "gen_hw_build_info.py"
    sw = ROOT / "run" / "gen_sw_build_info.py"
    subprocess.run([sys.executable, str(hw), mode], check=True, cwd=str(ROOT))
    subprocess.run([sys.executable, str(sw)], check=True, cwd=str(ROOT))


# ---------------------------------------------------------------------------
# Docker cross-compile
# ---------------------------------------------------------------------------

def docker_make(rel_dir: str, target: str) -> None:
    """Run make inside the de2extra-builder Docker container."""
    docker = detect_docker()
    if not docker:
        log("ERROR: Docker not found. Install Docker Desktop and retry.")
        sys.exit(1)

    mount_src = root_for_docker()
    mount_dst = "/project"

    cmd = [
        docker, "run", "--rm",
        "-e", "TZ=Asia/Shanghai",
        "-v", f"{mount_src}:{mount_dst}",
        DOCKER_IMAGE,
        "bash", "-c",
        f"cd {mount_dst}/{rel_dir} && "
        f"make clean NEORV32_HOME={mount_dst}/neorv32 "
        f"RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf- && "
        f"mkdir -p build && "
        f"make {target} NEORV32_HOME={mount_dst}/neorv32 "
        f"RISCV_PREFIX=/opt/riscv/bin/riscv-none-elf-",
    ]
    try:
        run(cmd)
    except SystemExit as e:
        # Re-run just to capture stderr for a friendlier Docker message
        check = subprocess.run(
            [docker, "info"], capture_output=True, text=True,
        )
        if check.returncode != 0:
            log("ERROR: Docker daemon is not running. Start Docker Desktop and retry.")
        sys.exit(e.code)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_sw_build(args: argparse.Namespace) -> None:
    """Cross-compile the firmware using Docker."""
    step("Software Build (Docker cross-compile)")
    t0 = time.time()

    gen_build_info("sync")
    docker_make("sw/app/de2shell_rtos", "exe")

    binfile = ROOT / "sw" / "app" / "de2shell_rtos" / "neorv32_exe.bin"
    if binfile.exists():
        size = binfile.stat().st_size
        log(f"  -> {size:,} bytes ({size/1024:.1f} KB)")
    else:
        log("  -> WARNING: neorv32_exe.bin not found")
    log(f"  -> {time.time()-t0:.1f}s")


def cmd_sw_upload(args: argparse.Namespace) -> None:
    """Upload firmware to board via UART."""
    step("Software Upload (UART)")
    t0 = time.time()

    port = args.port or detect_serial_port()
    upload_script = ROOT / "run" / "upload_de2os.py"
    binfile = ROOT / "sw" / "app" / "de2shell_rtos" / "neorv32_exe.bin"

    if not binfile.exists():
        log(f"ERROR: {binfile} not found. Run 'sw-build' first.")
        sys.exit(1)

    upload_args = [sys.executable, str(upload_script), port, str(binfile)]
    upload_args.append("--wait")

    log(f"  -> port: {port}")
    run(upload_args)
    log(f"  -> {time.time()-t0:.1f}s")


def cmd_hw_build(args: argparse.Namespace) -> None:
    """Run Quartus synthesis to produce .sof bitstream."""
    step("Hardware Build (Quartus synthesis)")
    t0 = time.time()

    quartus_root = detect_quartus()
    if not quartus_root:
        log("ERROR: Quartus not found. Set QUARTUS_ROOTDIR or install Quartus Prime.")
        sys.exit(1)

    # Build bootloader first (its output goes into IMEM image)
    step("Rebuilding NEORV32 bootloader")
    docker_make("neorv32/sw/bootloader", "bootloader")

    step("Hardware Build (Quartus synthesis)")
    qsh = quartus_bin(quartus_root, "quartus_sh")
    qpf = ROOT / "par" / "de2os" / "de2os.qpf"
    logfile = ROOT / "par" / "de2os" / "quartus_build.log"

    log(f"  -> Quartus: {quartus_root}")
    log(f"  -> Project: {qpf}")
    log(f"  -> Log: {logfile}")

    # Run Quartus compile in background, poll log for progress
    with open(logfile, "w") as lf:
        proc = subprocess.Popen(
            [qsh, "--flow", "compile", str(qpf), "-c", "de2os"],
            stdout=lf, stderr=subprocess.STDOUT,
            cwd=str(ROOT),
        )

    checkpoints = [
        ("Analysis & Synthesis was successful", "Analysis & Synthesis"),
        ("Fitter was successful", "Fitter"),
        ("Timing Analyzer was successful", "Timing Analyzer"),
        ("Assembler was successful", "Assembler"),
    ]
    shown = [False] * len(checkpoints)
    last_tick = -1

    while proc.poll() is None:
        try:
            text = logfile.read_text(encoding="utf-8", errors="replace") if logfile.exists() else ""
            for i, (pattern, label) in enumerate(checkpoints):
                if not shown[i] and pattern in text:
                    log(f"  -> {label} done")
                    shown[i] = True
            elapsed = int(time.time() - t0)
            tick = elapsed // 15
            if tick != last_tick:
                last_tick = tick
                log(f"  -> Quartus running... ({elapsed}s)")
        except Exception:
            pass
        time.sleep(5)

    if proc.returncode != 0:
        log("  -> Quartus FAILED. Last 30 lines of log:")
        if logfile.exists():
            for line in logfile.read_text(encoding="utf-8", errors="replace").splitlines()[-30:]:
                log(f"     {line}")
        sys.exit(proc.returncode)

    sof = ROOT / "par" / "de2os" / "de2os.sof"
    if sof.exists():
        log(f"  -> {sof.name} OK ({sof.stat().st_size:,} bytes)")
    else:
        log("  -> WARNING: de2os.sof not found")

    log(f"  -> {time.time()-t0:.1f}s")


def cmd_hw_flash(args: argparse.Namespace) -> None:
    """Program FPGA with .sof via JTAG."""
    step("Hardware Flash (JTAG programming)")
    t0 = time.time()

    quartus_root = detect_quartus()
    if not quartus_root:
        log("ERROR: Quartus not found. Set QUARTUS_ROOTDIR or install Quartus Prime.")
        sys.exit(1)

    sof = ROOT / "par" / "de2os" / "de2os.sof"
    if not sof.exists():
        log(f"ERROR: {sof} not found. Run 'hw-build' first.")
        sys.exit(1)

    pgm = quartus_bin(quartus_root, "quartus_pgm")
    run([pgm, "-c", "1", "-m", "JTAG", "-o", f"P;{sof}"])
    log(f"  -> {time.time()-t0:.1f}s")


def cmd_full(args: argparse.Namespace) -> None:
    """Full deploy: hw-build + hw-flash + sw-build + sw-upload."""
    log("=" * 60)
    log("  Full Deploy (Quartus + Flash + Firmware + Upload)")
    log("=" * 60)
    t0 = time.time()

    cmd_hw_build(args)
    cmd_hw_flash(args)
    cmd_sw_build(args)
    cmd_sw_upload(args)

    log(f"\n  Total: {time.time()-t0:.1f}s")


def cmd_inc(args: argparse.Namespace) -> None:
    """Incremental deploy: sw-build + sw-upload (no Quartus)."""
    log("=" * 60)
    log("  Incremental Deploy (Firmware + Upload)")
    log("=" * 60)
    t0 = time.time()

    cmd_sw_build(args)
    cmd_sw_upload(args)

    log(f"\n  Total: {time.time()-t0:.1f}s")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="de2extra",
        description="DE2Extra build & deploy CLI",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # sw-build
    p = sub.add_parser("sw-build", help="Cross-compile firmware (Docker)")
    p.set_defaults(func=cmd_sw_build)

    # sw-upload
    p = sub.add_parser("sw-upload", help="Upload firmware via UART (soft reboot)")
    p.add_argument("--port", "-p", help="Serial port (auto-detect if omitted)")
    p.set_defaults(func=cmd_sw_upload)

    # hw-build
    p = sub.add_parser("hw-build", help="Quartus synthesis (FPGA bitstream)")
    p.set_defaults(func=cmd_hw_build)

    # hw-flash
    p = sub.add_parser("hw-flash", help="Program FPGA via JTAG")
    p.set_defaults(func=cmd_hw_flash)

    # full
    p = sub.add_parser("full", help="Full deploy: hw-build + hw-flash + sw-build + sw-upload")
    p.add_argument("--port", "-p", help="Serial port (auto-detect if omitted)")
    p.set_defaults(func=cmd_full)

    # inc
    p = sub.add_parser("inc", help="Incremental deploy: sw-build + sw-upload")
    p.add_argument("--port", "-p", help="Serial port (auto-detect if omitted)")
    p.set_defaults(func=cmd_inc)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)
    log("\n  Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
