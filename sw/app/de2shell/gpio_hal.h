/* gpio_hal.h — GPIO Hardware Abstraction Layer
 *
 * LOCAL_BUILD: simulated values
 * NEORV32:     real GPIO registers
 */

#ifndef GPIO_HAL_H
#define GPIO_HAL_H

#include <stdint.h>

#ifdef LOCAL_BUILD
  /* Simulated values for local testing */
  uint32_t gpio_read_in(void);
  uint32_t gpio_read_out(void);
  void     gpio_write_out(uint32_t val);
  void     gpio_set_sim_in(uint32_t val);
  void     gpio_set_sim_out(uint32_t val);
#else
  #include <neorv32.h>
  static inline uint32_t gpio_read_in(void) {
      return neorv32_gpio_port_get();
  }
  static inline uint32_t gpio_read_out(void) {
      return NEORV32_GPIO->PORT_OUT;
  }
  static inline void gpio_write_out(uint32_t val) {
      neorv32_gpio_port_set(val);
  }
#endif

#endif /* GPIO_HAL_H */
