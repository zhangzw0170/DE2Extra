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

void ps2_dec_init(void);

/* Feed one raw scancode byte. Returns 1 when a complete key event
 * is decoded (including modifier state changes), 0 if more bytes
 * are needed (E0/F0 prefix consumed). */
int ps2_dec_feed(uint8_t raw_scancode, ps2_key_t *out);

/* Query modifier state */
int ps2_dec_shift(void);
int ps2_dec_ctrl(void);
int ps2_dec_alt(void);

#endif /* PS2_DECODER_H */
