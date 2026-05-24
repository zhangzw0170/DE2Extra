#!/bin/bash
# switch_hw.sh — Toggle de2_115_top.vhd between de2shell and de2os configs
#
# Usage:
#   ./switch_hw.sh de2os      # Patch for FreeRTOS + SDRAM (boot mode 0, icache on)
#   ./switch_hw.sh de2shell   # Revert to bare-metal (boot mode 2, no icache)
#   ./switch_hw.sh status     # Show current config
#
# The committed default is de2shell. Run with 'de2os' before Quartus synthesis,
# then 'de2shell' to revert after.

TOP_FILE="../../src/rtl/de2_115_top.vhd"

case "${1:-status}" in
    de2os)
        echo "Switching to de2os config (BOOT_MODE=0, ICACHE_EN=true)..."
        sed -i \
            -e 's/BOOT_MODE       => 2,/BOOT_MODE       => 0,/' \
            -e 's/ICACHE_EN       => false/ICACHE_EN       => true/' \
            "$TOP_FILE"

        # Check if ICACHE generics already present
        if ! grep -q 'ICACHE_BLOCKS' "$TOP_FILE"; then
            # Insert ICACHE generics after ICACHE_EN line
            sed -i '/ICACHE_EN.*=> true/a\
        ICACHE_BLOCKS   => 64,\
        ICACHE_BLOCK_SZ => 32,\
        ICACHE_BURSTS   => false' "$TOP_FILE"
        fi
        echo "Done. Run Quartus synthesis now."
        ;;
    de2shell)
        echo "Switching to de2shell config (BOOT_MODE=2, ICACHE_EN=false)..."
        sed -i \
            -e 's/BOOT_MODE       => 0,/BOOT_MODE       => 2,/' \
            -e 's/ICACHE_EN       => true/ICACHE_EN       => false/' \
            "$TOP_FILE"

        # Remove ICACHE detail generics (keep ICACHE_EN => false)
        sed -i \
            -e '/ICACHE_BLOCKS.*=> 64,/d' \
            -e '/ICACHE_BLOCK_SZ.*=> 32,/d' \
            -e '/ICACHE_BURSTS.*=> false/d' \
            "$TOP_FILE"
        echo "Done. Config matches committed default."
        ;;
    status)
        if grep -q 'BOOT_MODE.*=> 0' "$TOP_FILE"; then
            echo "Current: de2os (BOOT_MODE=0, SDRAM boot + ICACHE)"
        else
            echo "Current: de2shell (BOOT_MODE=2, IMEM direct)"
        fi
        ;;
    *)
        echo "Usage: $0 {de2os|de2shell|status}"
        exit 1
        ;;
esac
