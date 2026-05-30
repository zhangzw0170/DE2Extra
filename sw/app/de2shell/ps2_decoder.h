/* ps2_decoder.h -- Reusable PS/2 scancode-to-ASCII decoder
 *
 * Extracted from ps2.c for shared use between the PS/2 monitor
 * and the GUI keyboard input system.
 *
 * Usage:
 *   ps2_dec_init();
 *   // feed raw scancodes from PS/2 hardware:
 *   ps2_key_t key;
 *   if (ps2_dec_feed(scancode, &key)) { // got a complete event }
 */
#ifndef PS2_DECODER_H
#define PS2_DECODER_H

#include <stdint.h>

typedef struct {
    uint8_t ascii;       /* 0 if non-printable (modifier, arrow, etc.) */
    uint8_t scancode;    /* raw set 2 scancode byte */
    uint8_t is_press;    /* 1 = key down, 0 = key up */
    uint8_t is_extended; /* 1 = E0 prefix (nav cluster, numpad/) */
    uint8_t has_ascii;   /* 1 = ascii field is valid */
    const char *name;    /* human-readable: "Enter", "A", "LEFT", etc. */
} ps2_key_t;

/* Virtual keycodes for non-ASCII keys (0x80+).
 * Use with (uint8_t)c == PS2_VK_xxx in program input handlers. */
#define PS2_VK_F1    0x80
#define PS2_VK_F2    0x81
#define PS2_VK_F3    0x82
#define PS2_VK_F4    0x83
#define PS2_VK_F5    0x84
#define PS2_VK_F6    0x85
#define PS2_VK_F7    0x86
#define PS2_VK_F8    0x87
#define PS2_VK_F9    0x88
#define PS2_VK_F10   0x89
#define PS2_VK_F11   0x8A
#define PS2_VK_F12   0x8B

#define PS2_VK_UP    0x90
#define PS2_VK_DOWN  0x91
#define PS2_VK_LEFT  0x92
#define PS2_VK_RIGHT 0x93
#define PS2_VK_HOME  0x94
#define PS2_VK_END   0x95
#define PS2_VK_PGUP  0x96
#define PS2_VK_PGDN  0x97
#define PS2_VK_INS   0x98
#define PS2_VK_MENU  0x99

void ps2_dec_init(void);

/* Feed one raw scancode byte. Returns 1 when a complete key event
 * is decoded (including modifier state changes), 0 if more bytes
 * are needed (E0/F0 prefix consumed). */
int ps2_dec_feed(uint8_t raw_scancode, ps2_key_t *out);

/* Query modifier state */
int ps2_dec_shift(void);
int ps2_dec_ctrl(void);
int ps2_dec_alt(void);
int ps2_dec_caps_lock(void);
int ps2_dec_num_lock(void);
int ps2_dec_scroll_lock(void);

#endif /* PS2_DECODER_H */
