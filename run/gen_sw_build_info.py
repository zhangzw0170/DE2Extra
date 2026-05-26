#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HDR_PATH = ROOT / "sw" / "app" / "de2shell_rtos" / "sw_build_info.h"


def main() -> int:
    now = datetime.now()
    tag = now.strftime("%Y-%m-%d %H:%M:%S")
    HDR_PATH.write_text(
        f"""#ifndef SW_BUILD_INFO_H
#define SW_BUILD_INFO_H

#define SW_BUILD_TAG "{tag}"

#endif
""",
        encoding="ascii",
    )
    print(f"Software build info: {tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
