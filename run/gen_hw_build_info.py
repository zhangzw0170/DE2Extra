#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
PKG_PATH = ROOT / "src" / "rtl" / "lib" / "build_info_pkg.vhd"
HDR_PATH = ROOT / "sw" / "app" / "de2shell_rtos" / "hw_build_info.h"


def bcd_date(dt: datetime) -> str:
    return f"{dt.year:04d}{dt.month:02d}{dt.day:02d}"


def bcd_time(dt: datetime) -> str:
    return f"00{dt.hour:02d}{dt.minute:02d}{dt.second:02d}"


def format_tag(date_hex: str, time_hex: str) -> str:
    return (
        f"{date_hex[0:4]}-{date_hex[4:6]}-{date_hex[6:8]} "
        f"{time_hex[2:4]}:{time_hex[4:6]}:{time_hex[6:8]}"
    )


def write_pkg(date_hex: str, time_hex: str) -> None:
    PKG_PATH.write_text(
        f"""library ieee;
use ieee.std_logic_1164.all;

package build_info_pkg is
    constant HW_BUILD_MAGIC_C : std_logic_vector(31 downto 0) := x"42494E46";
    constant HW_BUILD_DATE_C  : std_logic_vector(31 downto 0) := x"{date_hex}";
    constant HW_BUILD_TIME_C  : std_logic_vector(31 downto 0) := x"{time_hex}";
end package build_info_pkg;
""",
        encoding="ascii",
    )


def write_header(tag: str) -> None:
    HDR_PATH.write_text(
        f"""#ifndef HW_BUILD_INFO_H
#define HW_BUILD_INFO_H

#define HW_BUILD_TAG "{tag}"

#endif
""",
        encoding="ascii",
    )


def read_pkg() -> tuple[str, str]:
    text = PKG_PATH.read_text(encoding="ascii")
    date_match = re.search(r'HW_BUILD_DATE_C\s*:\s*std_logic_vector\(31 downto 0\)\s*:=\s*x"([0-9A-Fa-f]{8})"', text)
    time_match = re.search(r'HW_BUILD_TIME_C\s*:\s*std_logic_vector\(31 downto 0\)\s*:=\s*x"([0-9A-Fa-f]{8})"', text)
    if not date_match or not time_match:
        raise RuntimeError(f"failed to parse {PKG_PATH}")
    return date_match.group(1).upper(), time_match.group(1).upper()


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "regen"

    if mode == "regen":
        now = datetime.now()
        date_hex = bcd_date(now)
        time_hex = bcd_time(now)
        write_pkg(date_hex, time_hex)
    elif mode == "sync":
        date_hex, time_hex = read_pkg()
    else:
        raise RuntimeError("usage: gen_hw_build_info.py [regen|sync]")

    tag = format_tag(date_hex, time_hex)
    write_header(tag)
    print(f"HW build info: {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
