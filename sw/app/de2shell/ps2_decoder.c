/* ps2_decoder.c -- Reusable PS/2 scancode-to-ASCII decoder
 *
 * Handles Set 2 protocol: E0 extended prefix, F0 break prefix.
 * Tracks all modifiers and lock states (caps, num, scroll).
 * Produces ASCII for printable keys and control codes for special keys.
 */
#include "ps2_decoder.h"

/* ── Modifier state ─────────────────────────────────────────────── */

static int shift_l, shift_r;
static int ctrl_l, ctrl_r;
static int alt_l, alt_r;
static int win_l, win_r;
static int caps_lock, num_lock, scroll_lock;

/* ── Prefix state ───────────────────────────────────────────────── */

static int break_prefix;
static int ext_prefix;

/* ── Internal helpers ───────────────────────────────────────────── */

static uint8_t letter_ascii(char lower, int shift_held, int caps, int ctrl_held) {
    uint8_t ascii = (uint8_t)lower;
    if ((shift_held ^ caps) != 0)
        ascii = (uint8_t)(lower - ('a' - 'A'));
    if (ctrl_held != 0)
        ascii = (uint8_t)((lower - 'a') + 1);
    return ascii;
}

typedef struct {
    const char *name;
    uint8_t ascii;
    uint8_t has_ascii;
} key_map_t;

static int decode_main(uint8_t sc, int sh, int caps, int ctrl, int num, ps2_key_t *out) {
    switch (sc) {
        case 0x0e: out->name="GRAVE";  out->ascii=(uint8_t)(sh?'~':'`'); out->has_ascii=1; return 1;
        case 0x16: out->name="1";      out->ascii=(uint8_t)(sh?'!':'1'); out->has_ascii=1; return 1;
        case 0x1e: out->name="2";      out->ascii=(uint8_t)(sh?'@':'2'); out->has_ascii=1; return 1;
        case 0x26: out->name="3";      out->ascii=(uint8_t)(sh?'#':'3'); out->has_ascii=1; return 1;
        case 0x25: out->name="4";      out->ascii=(uint8_t)(sh?'$':'4'); out->has_ascii=1; return 1;
        case 0x2e: out->name="5";      out->ascii=(uint8_t)(sh?'%':'5'); out->has_ascii=1; return 1;
        case 0x36: out->name="6";      out->ascii=(uint8_t)(sh?'^':'6'); out->has_ascii=1; return 1;
        case 0x3d: out->name="7";      out->ascii=(uint8_t)(sh?'&':'7'); out->has_ascii=1; return 1;
        case 0x3e: out->name="8";      out->ascii=(uint8_t)(sh?'*':'8'); out->has_ascii=1; return 1;
        case 0x46: out->name="9";      out->ascii=(uint8_t)(sh?'(':'9'); out->has_ascii=1; return 1;
        case 0x45: out->name="0";      out->ascii=(uint8_t)(sh?')':'0'); out->has_ascii=1; return 1;
        case 0x4e: out->name="MINUS";  out->ascii=(uint8_t)(sh?'_':'-'); out->has_ascii=1; return 1;
        case 0x55: out->name="EQUAL";  out->ascii=(uint8_t)(sh?'+':'='); out->has_ascii=1; return 1;
        case 0x66: out->name="BSP";    out->ascii=0x08; out->has_ascii=1; return 1;
        case 0x0d: out->name="TAB";    out->ascii=0x09; out->has_ascii=1; return 1;
        case 0x15: out->name="Q"; out->ascii=letter_ascii('q',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x1d: out->name="W"; out->ascii=letter_ascii('w',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x24: out->name="E"; out->ascii=letter_ascii('e',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x2d: out->name="R"; out->ascii=letter_ascii('r',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x2c: out->name="T"; out->ascii=letter_ascii('t',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x35: out->name="Y"; out->ascii=letter_ascii('y',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x3c: out->name="U"; out->ascii=letter_ascii('u',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x43: out->name="I"; out->ascii=letter_ascii('i',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x44: out->name="O"; out->ascii=letter_ascii('o',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x4d: out->name="P"; out->ascii=letter_ascii('p',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x54: out->name="LBRK";   out->ascii=(uint8_t)(sh?'{':'['); out->has_ascii=1; return 1;
        case 0x5b: out->name="RBRK";   out->ascii=(uint8_t)(sh?'}':']'); out->has_ascii=1; return 1;
        case 0x5d: out->name="BSLASH";  out->ascii=(uint8_t)(sh?'|':'\\'); out->has_ascii=1; return 1;
        case 0x1c: out->name="A"; out->ascii=letter_ascii('a',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x1b: out->name="S"; out->ascii=letter_ascii('s',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x23: out->name="D"; out->ascii=letter_ascii('d',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x2b: out->name="F"; out->ascii=letter_ascii('f',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x34: out->name="G"; out->ascii=letter_ascii('g',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x33: out->name="H"; out->ascii=letter_ascii('h',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x3b: out->name="J"; out->ascii=letter_ascii('j',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x42: out->name="K"; out->ascii=letter_ascii('k',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x4b: out->name="L"; out->ascii=letter_ascii('l',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x4c: out->name="SEMI";   out->ascii=(uint8_t)(sh?':':';'); out->has_ascii=1; return 1;
        case 0x52: out->name="QUOTE";   out->ascii=(uint8_t)(sh?'"':'\''); out->has_ascii=1; return 1;
        case 0x5a: out->name="ENTER";   out->ascii=0x0d; out->has_ascii=1; return 1;
        case 0x1a: out->name="Z"; out->ascii=letter_ascii('z',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x22: out->name="X"; out->ascii=letter_ascii('x',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x21: out->name="C"; out->ascii=letter_ascii('c',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x2a: out->name="V"; out->ascii=letter_ascii('v',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x32: out->name="B"; out->ascii=letter_ascii('b',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x31: out->name="N"; out->ascii=letter_ascii('n',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x3a: out->name="M"; out->ascii=letter_ascii('m',sh,caps,ctrl); out->has_ascii=1; return 1;
        case 0x41: out->name="COMMA";   out->ascii=(uint8_t)(sh?'<':','); out->has_ascii=1; return 1;
        case 0x49: out->name="DOT";     out->ascii=(uint8_t)(sh?'>':'.'); out->has_ascii=1; return 1;
        case 0x4a: out->name="SLASH";   out->ascii=(uint8_t)(sh?'?':'/'); out->has_ascii=1; return 1;
        case 0x29: out->name="SPACE";   out->ascii=0x20; out->has_ascii=1; return 1;
        case 0x76: out->name="ESC";     out->ascii=0x1b; out->has_ascii=1; return 1;
        /* Function keys F1-F10 */
        case 0x05: out->name="F1";  out->ascii=PS2_VK_F1;  out->has_ascii=0; return 1;
        case 0x06: out->name="F2";  out->ascii=PS2_VK_F2;  out->has_ascii=0; return 1;
        case 0x04: out->name="F3";  out->ascii=PS2_VK_F3;  out->has_ascii=0; return 1;
        case 0x0C: out->name="F4";  out->ascii=PS2_VK_F4;  out->has_ascii=0; return 1;
        case 0x03: out->name="F5";  out->ascii=PS2_VK_F5;  out->has_ascii=0; return 1;
        case 0x0B: out->name="F6";  out->ascii=PS2_VK_F6;  out->has_ascii=0; return 1;
        case 0x83: out->name="F7";  out->ascii=PS2_VK_F7;  out->has_ascii=0; return 1;
        case 0x0A: out->name="F8";  out->ascii=PS2_VK_F8;  out->has_ascii=0; return 1;
        case 0x01: out->name="F9";  out->ascii=PS2_VK_F9;  out->has_ascii=0; return 1;
        case 0x09: out->name="F10"; out->ascii=PS2_VK_F10; out->has_ascii=0; return 1;
        /* Function keys F11-F12 */
        case 0x78: out->name="F11"; out->ascii=PS2_VK_F11; out->has_ascii=0; return 1;
        case 0x07: out->name="F12"; out->ascii=PS2_VK_F12; out->has_ascii=0; return 1;
        /* numpad keys (when num lock on) */
        case 0x70: out->name="KP0"; out->ascii='0'; out->has_ascii=(uint8_t)num; return 1;
        case 0x69: out->name="KP1"; out->ascii='1'; out->has_ascii=(uint8_t)num; return 1;
        case 0x72: out->name="KP2"; out->ascii='2'; out->has_ascii=(uint8_t)num; return 1;
        case 0x7a: out->name="KP3"; out->ascii='3'; out->has_ascii=(uint8_t)num; return 1;
        case 0x6b: out->name="KP4"; out->ascii='4'; out->has_ascii=(uint8_t)num; return 1;
        case 0x73: out->name="KP5"; out->ascii='5'; out->has_ascii=(uint8_t)num; return 1;
        case 0x74: out->name="KP6"; out->ascii='6'; out->has_ascii=(uint8_t)num; return 1;
        case 0x6c: out->name="KP7"; out->ascii='7'; out->has_ascii=(uint8_t)num; return 1;
        case 0x75: out->name="KP8"; out->ascii='8'; out->has_ascii=(uint8_t)num; return 1;
        case 0x7d: out->name="KP9"; out->ascii='9'; out->has_ascii=(uint8_t)num; return 1;
        case 0x71: out->name="KPDOT"; out->ascii='.'; out->has_ascii=(uint8_t)num; return 1;
        case 0x79: out->name="KP+"; out->ascii='+'; out->has_ascii=1; return 1;
        case 0x7b: out->name="KP-"; out->ascii='-'; out->has_ascii=1; return 1;
        case 0x7c: out->name="KP*"; out->ascii='*'; out->has_ascii=1; return 1;
        default: return 0;
    }
}

static int decode_extended(uint8_t sc, ps2_key_t *out) {
    switch (sc) {
        case 0x69: out->name="END";   out->ascii=PS2_VK_END;   out->has_ascii=0; return 1;
        case 0x6b: out->name="LEFT";  out->ascii=PS2_VK_LEFT;  out->has_ascii=0; return 1;
        case 0x6c: out->name="HOME";  out->ascii=PS2_VK_HOME;  out->has_ascii=0; return 1;
        case 0x70: out->name="INS";   out->ascii=PS2_VK_INS;   out->has_ascii=0; return 1;
        case 0x71: out->name="DEL";   out->ascii=0x7f; out->has_ascii=1; return 1;
        case 0x72: out->name="DOWN";  out->ascii=PS2_VK_DOWN;  out->has_ascii=0; return 1;
        case 0x74: out->name="RIGHT"; out->ascii=PS2_VK_RIGHT; out->has_ascii=0; return 1;
        case 0x75: out->name="UP";    out->ascii=PS2_VK_UP;    out->has_ascii=0; return 1;
        case 0x7a: out->name="PGDN";  out->ascii=PS2_VK_PGDN;  out->has_ascii=0; return 1;
        case 0x7d: out->name="PGUP";  out->ascii=PS2_VK_PGUP;  out->has_ascii=0; return 1;
        case 0x5a: out->name="KPENT"; out->ascii=0x0d; out->has_ascii=1; return 1;
        case 0x4a: out->name="KP/";   out->ascii='/'; out->has_ascii=1; return 1;
        default: return 0;
    }
}

/* ── Public API ─────────────────────────────────────────────────── */

void ps2_dec_init(void) {
    shift_l = shift_r = 0;
    ctrl_l = ctrl_r = 0;
    alt_l = alt_r = 0;
    win_l = win_r = 0;
    caps_lock = num_lock = scroll_lock = 0;
    break_prefix = 0;
    ext_prefix = 0;
}

int ps2_dec_feed(uint8_t raw, ps2_key_t *out) {
    int is_release, is_extended;

    if (raw == 0xE0u) { ext_prefix = 1; return 0; }
    if (raw == 0xF0u) { break_prefix = 1; return 0; }

    is_release = break_prefix;
    is_extended = ext_prefix;
    break_prefix = 0;
    ext_prefix = 0;

    out->scancode = raw;
    out->is_press = is_release ? 0 : 1;
    out->is_extended = is_extended ? 1 : 0;
    out->ascii = 0;
    out->has_ascii = 0;
    out->name = "???";

    int sh = shift_l || shift_r;
    int ctrl = ctrl_l || ctrl_r;

    if (is_extended) {
        /* Extended modifier tracking */
        if (raw == 0x14u) { ctrl_r = is_release ? 0 : 1; out->name = "RCTRL"; return 1; }
        if (raw == 0x11u) { alt_r = is_release ? 0 : 1; out->name = "RALT"; return 1; }
        if (raw == 0x1fu) { win_l = is_release ? 0 : 1; out->name = "LWIN"; return 1; }
        if (raw == 0x27u) { win_r = is_release ? 0 : 1; out->name = "RWIN"; return 1; }
        if (raw == 0x2fu) { out->ascii = PS2_VK_MENU; out->name = "MENU"; return 1; }
        return decode_extended(raw, out);
    }

    /* Main block modifier tracking */
    if (raw == 0x12u) { shift_l = is_release ? 0 : 1; out->name = "LSHIFT"; return 1; }
    if (raw == 0x59u) { shift_r = is_release ? 0 : 1; out->name = "RSHIFT"; return 1; }
    if (raw == 0x14u) { ctrl_l = is_release ? 0 : 1; out->name = "LCTRL"; return 1; }
    if (raw == 0x11u) { alt_l = is_release ? 0 : 1; out->name = "LALT"; return 1; }
    if (raw == 0x58u) {
        if (!is_release) caps_lock ^= 1;
        out->name = "CAPS"; return 1;
    }
    if (raw == 0x77u) {
        if (!is_release) num_lock ^= 1;
        out->name = "NUM"; return 1;
    }
    if (raw == 0x7eu) {
        if (!is_release) scroll_lock ^= 1;
        out->name = "SCRLK"; return 1;
    }

    return decode_main(raw, sh, caps_lock, ctrl, num_lock, out);
}

int ps2_dec_shift(void) { return shift_l || shift_r; }
int ps2_dec_ctrl(void)  { return ctrl_l || ctrl_r; }
int ps2_dec_alt(void)   { return alt_l || alt_r; }
int ps2_dec_caps_lock(void) { return caps_lock; }
int ps2_dec_num_lock(void) { return num_lock; }
int ps2_dec_scroll_lock(void) { return scroll_lock; }
