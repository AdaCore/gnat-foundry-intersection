/*
 * hal_zephyr.c — C shims bridging Ada HAL bodies (src/hal/zephyr/hal.adb)
 * to Zephyr APIs.
 *
 * Convention: every function callable from Ada via pragma Import is named
 * `tlc_zephyr_<op>`. The `tlc_` prefix marks the boundary; Ada-side imports
 * use Convention => C and External_Name => "tlc_zephyr_<op>".
 *
 * Many useful Zephyr APIs (gpio_pin_set_dt, zsock_*, ...) are `static inline`
 * in headers and have no linkable symbol — wrapping them here is mandatory,
 * not optional. See the alire skill zephyr.md "Bridging Zephyr's inline APIs
 * to Ada" and the `nm libzephyr.a | grep <name>` diagnostic.
 */

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

void tlc_zephyr_init(void)
{
	printk("[HAL/zephyr] init\n");
	/* TODO: configure GPIOs from device tree, bring up UART for diag,
	 * start the 1 ms tick timer. */
}
