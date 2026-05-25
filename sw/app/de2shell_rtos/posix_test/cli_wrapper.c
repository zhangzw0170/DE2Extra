/* cli_wrapper.c — Includes FreeRTOS_CLI.c with stub headers
 *
 * This wrapper ensures FreeRTOS_CLI.c sees our stub FreeRTOS.h
 * instead of the real kernel headers. The -I. flag ensures our
 * stub dir is searched before -I..
 */
#include "../FreeRTOS_CLI.c"
