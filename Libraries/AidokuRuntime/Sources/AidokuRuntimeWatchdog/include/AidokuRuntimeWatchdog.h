#ifndef AIDOKU_RUNTIME_WATCHDOG_H
#define AIDOKU_RUNTIME_WATCHDOG_H

#include <stdint.h>
#include <stdbool.h>

typedef struct aidoku_watchdog_context aidoku_watchdog_context;

void aidoku_watchdog_install(void);
aidoku_watchdog_context *aidoku_watchdog_context_create(void);
void aidoku_watchdog_context_destroy(aidoku_watchdog_context *context);
void aidoku_watchdog_context_reset(aidoku_watchdog_context *context);
void aidoku_watchdog_context_cancel(aidoku_watchdog_context *context);
void aidoku_watchdog_prepare_current_thread(aidoku_watchdog_context *context);
void aidoku_watchdog_clear_current_thread(void);
uintptr_t aidoku_watchdog_current_thread(void);
uint64_t aidoku_watchdog_deadline_after(uint64_t nanoseconds);
void aidoku_watchdog_clear_deadline(void);
bool aidoku_watchdog_should_abort(void);
int32_t aidoku_watchdog_interrupt(uintptr_t thread);

#endif
