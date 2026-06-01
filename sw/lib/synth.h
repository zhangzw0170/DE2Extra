/* synth.h -- Audio synth driver for DE2-115 WM8731
 *
 * Register map at 0xF0013000 (Wishbone slave s11):
 *   0x00 CTRL    [0]=mute, [2:1]=mode(00=3xOSC,01=DX7), [4:3]=volume
 *   0x01 STATUS  [0]=codec_ready (R)
 *   0x02 T1_NOTE full 32-bit tuning word (0=release)
 *   0x03 T1_OSC1 [1:0]=wave, [3:2]=octave, [15:8]=vol
 *   0x04 T1_OSC2 (same layout)
 *   0x05 T1_OSC3 (same layout)
 *   0x06 T1_DX7  [7:0]=ratio, [15:8]=mod_index
 *   0x07 T1_ADSR [3:0]=AR, [7:4]=DR, [11:8]=SL, [15:12]=RR
 *   0x08 T2_NOTE ... 0x0D T2_ADSR (same layout as T1)
 *
 * Firmware writes precomputed tuning word to NOTE register.
 * gate = (NOTE != 0), so write 0 to release.
 */
#ifndef SYNTH_H
#define SYNTH_H

#include <stdint.h>
#include "vga_hal.h"

extern const program_t prog_synth;

#endif /* SYNTH_H */
