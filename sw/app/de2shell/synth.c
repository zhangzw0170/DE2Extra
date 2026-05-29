/* synth.c -- Audio synth driver + PS/2 keyboard piano
 *
 * Dual-track synthesizer controlled by PS/2 keyboard:
 *   Track 1 (left ch):  main keyboard area (A-;)
 *   Track 2 (right ch): numpad area
 *
 * Modes: 3xOSC (3 DDS oscillators per track) or DX7 FM.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "synth.h"
#include "vga_hal.h"
#include "ps2_decoder.h"

/* ── Hardware registers ──────────────────────────────────── */
#define SYNTH_BASE  ((volatile uint32_t *)0xF0013000u)

#define SYNTH_CTRL       (*(SYNTH_BASE + 0))
#define SYNTH_STATUS     (*(SYNTH_BASE + 1))
#define SYNTH_T1_NOTE    (*(SYNTH_BASE + 2))
#define SYNTH_T1_OSC1    (*(SYNTH_BASE + 3))
#define SYNTH_T1_OSC2    (*(SYNTH_BASE + 4))
#define SYNTH_T1_OSC3    (*(SYNTH_BASE + 5))
#define SYNTH_T1_DX7     (*(SYNTH_BASE + 6))
#define SYNTH_T1_ADSR    (*(SYNTH_BASE + 7))
#define SYNTH_T2_NOTE    (*(SYNTH_BASE + 8))
#define SYNTH_T2_OSC1    (*(SYNTH_BASE + 9))
#define SYNTH_T2_OSC2    (*(SYNTH_BASE + 10))
#define SYNTH_T2_OSC3    (*(SYNTH_BASE + 11))
#define SYNTH_T2_DX7     (*(SYNTH_BASE + 12))
#define SYNTH_T2_ADSR    (*(SYNTH_BASE + 13))

#define PS2_MMIO_BASE  ((volatile uint32_t *)0xF0008000u)
#define PS2_REG_DATA   0u
#define PS2_REG_STAT   1u
#define PS2_STAT_READY 0x01u

/* ── Tuning table: MIDI 21 (A0) .. 108 (C8) ──────────────── */
/* TW = f * 2^32 / 48000, f = 440 * 2^((note-69)/12) */
#define MIDI_LO 21
#define MIDI_HI 108

static const uint32_t tuning_table[88] = {
    /*  21 A0   */ 0x00258BF2, 0x0027C781, 0x002A250C, 0x002CA698,
    /*  25 C#1  */ 0x002F4E4B, 0x00321E69, 0x00351958, 0x003841A6,
    /*  29 F1   */ 0x003B9A04, 0x003F254E, 0x0042E68B, 0x0046E0F0,
    /*  33 A1   */ 0x004B17E5, 0x004F8F01, 0x00544A17, 0x00594D31,
    /*  37 C#2  */ 0x005E9C96, 0x00643CD2, 0x006A32B1, 0x0070834C,
    /*  41 F2   */ 0x00773407, 0x007E4A9B, 0x0085CD15, 0x008DC1E1,
    /*  45 A2   */ 0x00962FC9, 0x009F1E03, 0x00A8942E, 0x00B29A62,
    /*  49 C#3  */ 0x00BD392D, 0x00C879A3, 0x00D46562, 0x00E10697,
    /*  53 F3   */ 0x00EE680F, 0x00FC9536, 0x010B9A2B, 0x011B83C2,
    /*  57 A3   */ 0x012C5F93, 0x013E3C06, 0x0151285D, 0x016534C3,
    /*  61 C#4  */ 0x017A725A, 0x0190F347, 0x01A8CAC3, 0x01C20D2F,
    /*  65 F4   */ 0x01DCD01D, 0x01F92A6D, 0x02173456, 0x02370783,
    /*  69 A4   */ 0x0258BF26, 0x027C780B, 0x02A250BA, 0x02CA6987,
    /*  73 C#5  */ 0x02F4E4B4, 0x0321E68D, 0x03519586, 0x03841A5D,
    /*  77 F5   */ 0x03B9A03A, 0x03F254D9, 0x042E68AC, 0x046E0F07,
    /*  81 A5   */ 0x04B17E4B, 0x04F8F017, 0x0544A173, 0x0594D30D,
    /*  85 C#6  */ 0x05E9C968, 0x0643CD1B, 0x06A32B0D, 0x070834BA,
    /*  89 F6   */ 0x07734075, 0x07E4A9B2, 0x085CD157, 0x08DC1E0D,
    /*  93 A6   */ 0x0962FC96, 0x09F1E02D, 0x0A8942E7, 0x0B29A61A,
    /*  97 C#7  */ 0x0BD392D0, 0x0C879A35, 0x0D46561A, 0x0E106974,
    /* 101 F7   */ 0x0EE680E9, 0x0FC95364, 0x10B9A2AF, 0x11B83C1A,
    /* 105 A7   */ 0x12C5F92C, 0x13E3C05A, 0x151285CE, 0x16534C35,
};

/* ── Scancode → semitone offset from base note ───────────── */
/* PS/2 Set 2 make codes:
 * A=0x1C B=0x32 C=0x21 D=0x23 E=0x24 F=0x2B G=0x34
 * H=0x33 I=0x43 J=0x3B K=0x42 L=0x4B M=0x3A N=0x31
 * O=0x44 P=0x4D Q=0x15 R=0x2D S=0x1B T=0x2E U=0x3C
 * V=0x2A W=0x1D X=0x22 Y=0x35 Z=0x1A
 * ;=0x41 Tab=0x0D CapsLock=0x58
 * NumLock=0x77 Num7=0x6C Num8=0x75 Num9=0x7D Num4=0x6B
 * Num5=0x73 Num6=0x74 Num1=0x69 Num2=0x72 Num3=0x7A Num0=0x70
 */
typedef struct { uint8_t scancode; int8_t semi; } key_map_t;

/* Track 1: main keyboard piano layout
 *   Black keys: W  E     T  Y  U     O  P
 *   White keys: A  S  D  F  G  H  J  K  L  ;
 */
static const key_map_t t1_keys[] = {
    /* White keys */
    { 0x1C,  0 }, /* A → C   */
    { 0x1B,  2 }, /* S → D   */
    { 0x23,  4 }, /* D → E   */
    { 0x2B,  5 }, /* F → F   */
    { 0x34,  7 }, /* G → G   */
    { 0x33,  9 }, /* H → A   */
    { 0x3B, 11 }, /* J → B   */
    { 0x42, 12 }, /* K → C+1 */
    { 0x4B, 14 }, /* L → D+1 */
    { 0x41, 16 }, /* ; → E+1 */
    /* Black keys */
    { 0x1D,  1 }, /* W → C#  */
    { 0x24,  3 }, /* E → D#  */
    { 0x2D,  6 }, /* R → F#  */
    { 0x2E,  8 }, /* T → G#  */
    { 0x35, 10 }, /* Y → A#  */
    { 0x43, 13 }, /* I → C#+1 */
    { 0x44, 15 }, /* O → D#+1 */
};
#define T1_COUNT (sizeof(t1_keys) / sizeof(t1_keys[0]))

/* Track 2: numpad */
static const key_map_t t2_keys[] = {
    { 0x6C,  0 }, /* Num7 → C   */
    { 0x75,  2 }, /* Num8 → D   */
    { 0x7D,  4 }, /* Num9 → E   */
    { 0x6B,  5 }, /* Num4 → F   */
    { 0x73,  7 }, /* Num5 → G   */
    { 0x74,  9 }, /* Num6 → A   */
    { 0x69, 11 }, /* Num1 → B   */
    { 0x72, 12 }, /* Num2 → C+1 */
    { 0x7A, 14 }, /* Num3 → D+1 */
    { 0x70, 16 }, /* Num0 → E+1 */
};
#define T2_COUNT (sizeof(t2_keys) / sizeof(t2_keys[0]))

/* ── State ───────────────────────────────────────────────── */
static int initialized;
static int t1_base;       /* base MIDI note (default 60=C4) */
static int t2_base;
static int mode;          /* 0=3xOSC, 1=DX7 */
static int t1_held;       /* currently held semitone (-1=none) */
static int t2_held;

/* ── Helpers ─────────────────────────────────────────────── */
static int ps2_available(void) {
    return (int)(PS2_MMIO_BASE[PS2_REG_STAT] & PS2_STAT_READY);
}

static uint8_t ps2_read(void) {
    return (uint8_t)(PS2_MMIO_BASE[PS2_REG_DATA] & 0xFFu);
}

static uint32_t midi_to_tw(int midi) {
    if (midi < MIDI_LO || midi > MIDI_HI) return 0;
    return tuning_table[midi - MIDI_LO];
}

static void note_on(int track, int midi) {
    uint32_t tw = midi_to_tw(midi);
    if (track == 1) SYNTH_T1_NOTE = tw;
    else            SYNTH_T2_NOTE = tw;
}

static void note_off(int track) {
    if (track == 1) SYNTH_T1_NOTE = 0;
    else            SYNTH_T2_NOTE = 0;
}

static void set_osc(int track, int osc, int wave, int octave, int vol) {
    uint32_t val = ((uint32_t)(vol & 0xFF) << 8)
                 | ((uint32_t)(octave & 0x3) << 2)
                 | ((uint32_t)(wave & 0x3));
    int idx = (track == 1) ? 3 + osc : 9 + osc;
    *(SYNTH_BASE + idx) = val;
}

static void set_dx7(int track, int ratio, int mod_index) {
    uint32_t val = ((uint32_t)(mod_index & 0xFF) << 8)
                 | ((uint32_t)(ratio & 0xFF));
    if (track == 1) SYNTH_T1_DX7 = val;
    else            SYNTH_T2_DX7 = val;
}

static void set_adsr(int track, int ar, int dr, int sl, int rr) {
    uint32_t val = ((uint32_t)(rr & 0xF) << 12)
                 | ((uint32_t)(sl & 0xF) << 8)
                 | ((uint32_t)(dr & 0xF) << 4)
                 | ((uint32_t)(ar & 0xF));
    if (track == 1) SYNTH_T1_ADSR = val;
    else            SYNTH_T2_ADSR = val;
}

static int lookup_semi(const key_map_t *map, int count, uint8_t sc) {
    for (int i = 0; i < count; i++) {
        if (map[i].scancode == sc) return map[i].semi;
    }
    return -1;
}

/* ── Presets ─────────────────────────────────────────────── */
static void preset_3xosc(void) {
    set_osc(1, 0, 0, 0, 200);   /* sine, base, vol 200 */
    set_osc(1, 1, 2, 0, 100);   /* saw, base, vol 100 */
    set_osc(1, 2, 3, 0, 80);    /* tri, base, vol 80 */
    set_osc(2, 0, 1, 0, 200);   /* square */
    set_osc(2, 1, 0, 0, 120);   /* sine */
    set_osc(2, 2, 0, 0, 0);     /* off */
}

static void preset_dx7(void) {
    set_dx7(1, 2, 64);
    set_adsr(1, 12, 6, 8, 4);
    set_dx7(2, 1, 100);
    set_adsr(2, 10, 4, 10, 6);
}

/* ── Program interface ───────────────────────────────────── */
static void init(void) {
    t1_base = 60;  /* C4 */
    t2_base = 60;
    mode = 0;
    t1_held = -1;
    t2_held = -1;

    SYNTH_CTRL = 0;   /* unmute, 3xOSC, max volume */
    preset_3xosc();
    initialized = 1;

    vga_clear();
    vga_puts("=== Audio Synth ===\n", VGA_CYAN);
    vga_puts("T1(L): A-; piano  Tab/Caps octave\n", VGA_WHITE);
    vga_puts("T2(R): Numpad     NumLock octave\n", VGA_WHITE);
    vga_puts("M=mode  Q=quit\n", VGA_YELLOW);
}

static void update(void) {
    if (!initialized) return;

    while (ps2_available()) {
        uint8_t sc = ps2_read();
        ps2_key_t key;
        if (!ps2_dec_feed(sc, &key)) continue;

        if (!key.is_press) {
            if (t1_held >= 0) {
                int semi = lookup_semi(t1_keys, (int)T1_COUNT, key.scancode);
                if (semi == t1_held) { note_off(1); t1_held = -1; }
            }
            if (t2_held >= 0) {
                int semi = lookup_semi(t2_keys, (int)T2_COUNT, key.scancode);
                if (semi == t2_held) { note_off(2); t2_held = -1; }
            }
            continue;
        }

        /* Octave shift */
        if (key.scancode == 0x0D) { /* Tab */
            t1_base = (t1_base > 36) ? t1_base - 12 : t1_base;
            continue;
        }
        if (key.scancode == 0x58) { /* CapsLock */
            t1_base = (t1_base < 96) ? t1_base + 12 : t1_base;
            continue;
        }
        if (key.scancode == 0x77) { /* NumLock */
            t2_base = (t2_base < 96) ? t2_base + 12 : t2_base;
            continue;
        }

        /* Quit */
        if (key.ascii == 'q' || key.ascii == 'Q') {
            SYNTH_CTRL = 1;  /* mute */
            SYNTH_T1_NOTE = 0;
            SYNTH_T2_NOTE = 0;
            initialized = 0;
            return;
        }

        /* Mode toggle */
        if (key.ascii == 'm' || key.ascii == 'M') {
            mode = 1 - mode;
            SYNTH_CTRL = (SYNTH_CTRL & ~0x06u) | ((uint32_t)mode << 1);
            if (mode == 0) preset_3xosc();
            else           preset_dx7();
            continue;
        }

        /* Track 1 note */
        {
            int semi = lookup_semi(t1_keys, (int)T1_COUNT, key.scancode);
            if (semi >= 0) {
                t1_held = semi;
                note_on(1, t1_base + semi);
                continue;
            }
        }

        /* Track 2 note */
        {
            int semi = lookup_semi(t2_keys, (int)T2_COUNT, key.scancode);
            if (semi >= 0) {
                t2_held = semi;
                note_on(2, t2_base + semi);
                continue;
            }
        }
    }
}

static void input(char c) {
    (void)c;
}

static int finish(void) { return !initialized; }

const program_t prog_synth = {
    "Synth", "Audio synth — PS/2 piano (M=mode, Tab/Caps octave, Q quit)",
    init, update, input, NULL, finish
};
