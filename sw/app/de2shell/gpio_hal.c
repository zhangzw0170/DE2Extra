/* gpio_hal.c — GPIO HAL (LOCAL_BUILD simulated values) */
#include "gpio_hal.h"

#ifdef LOCAL_BUILD
  static uint32_t sim_gpio_in  = 0x00000005;  /* SW[2:0]=101 */
  static uint32_t sim_gpio_out = 0x00000000;

  uint32_t gpio_read_in(void)  { return sim_gpio_in; }
  uint32_t gpio_read_out(void) { return sim_gpio_out; }
  void gpio_set_sim_in(uint32_t val)  { sim_gpio_in = val; }
  void gpio_set_sim_out(uint32_t val) { sim_gpio_out = val; }
#endif
