# BUG-001: VGA Scroll Region Causes Silent Display Shift

**Date:** 2026-06-02
**Severity:** High
**Status:** Fixed
**Affected:** snake, conway_hw (all full-screen programs with 80-char rows)
**Found by:** User (2-3 day investigation)

## Symptom

VGA display shows the game border shifted up by 1 row compared to serial output.
HUD text (e.g. "SNAKE EASY P1:") is invisible on VGA — overwritten by the shifted top border.
Game cells appear at correct positions (continuously redrawn), but static elements (border, HUD) are wrong.
Serial mirror output looks perfectly correct, making the bug nearly impossible to spot from UART alone.

## Root Cause

`vga_set_scroll_region(0, VGA_ROWS-2)` is called during shell init to reserve row 29 for the status bar.
This sets `scroll_bottom = 28`.

When a full-screen program draws an 80-character border on row 28 (= scroll_bottom):
```
vga_goto(0, 28);
vga_putc('+'); // ... 78 dashes ... vga_putc('+'); // 80th char at col 79
```

After the 80th character, `advance_cursor()` increments `cur_col` to 80, which triggers:
```c
cur_col = 0;
cur_row++;        // 28 → 29
if (cur_row > scroll_bottom) {   // 29 > 28 = TRUE
    hw_scroll_up_region();       // <-- SILENT SCROLL!
    cur_row = scroll_bottom;
}
```

`hw_scroll_up_region()` shifts the entire VGA text buffer up by 1 row.
The serial mirror receives NO notification of this scroll — it still thinks content is at the original positions.

## Fix

`vga_clear()` now resets `scroll_top = 0, scroll_bottom = VGA_ROWS - 1` (full 30-row screen).
Every program calling `vga_clear()` gets the full screen. The shell re-sets its restricted region after init.

**File:** `sw/lib/vga_hal.c` — both LOCAL_BUILD and NEORV32 versions of `vga_clear()`.

## Lessons

1. Serial mirror and VGA buffer can diverge — never assume they're identical.
2. Scroll region side effects are invisible in serial output.
3. Writing exactly 80 chars on `scroll_bottom` row triggers a scroll; this is easy to miss during code review.
4. Full-screen programs must ensure the scroll region covers all 30 rows before drawing.
