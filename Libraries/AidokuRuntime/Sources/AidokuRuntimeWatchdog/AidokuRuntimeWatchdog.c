#include "AidokuRuntimeWatchdog.h"

#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <time.h>

// Provided by Wasm3's MIT-licensed wasm3-support target. The flag is
// thread-local, so the signal writes it directly on the interpreter thread.
extern __thread _Bool should_yield_next;
struct aidoku_watchdog_context {
    atomic_bool cancelled;
};

static __thread aidoku_watchdog_context *current_context = NULL;
static __thread uint64_t deadline_nanoseconds = 0;

static atomic_bool installed = false;

static void aidoku_watchdog_signal_handler(int signal_number) {
    (void)signal_number;
    should_yield_next = true;
}

void aidoku_watchdog_install(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&installed, &expected, true)) {
        return;
    }
    struct sigaction action = {0};
    action.sa_handler = aidoku_watchdog_signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    sigaction(SIGUSR2, &action, NULL);
}

aidoku_watchdog_context *aidoku_watchdog_context_create(void) {
    aidoku_watchdog_context *context = calloc(1, sizeof(aidoku_watchdog_context));
    if (context != NULL) {
        atomic_init(&context->cancelled, false);
    }
    return context;
}

void aidoku_watchdog_context_destroy(aidoku_watchdog_context *context) {
    free(context);
}

void aidoku_watchdog_context_reset(aidoku_watchdog_context *context) {
    if (context != NULL) {
        atomic_store_explicit(&context->cancelled, false, memory_order_release);
    }
}

void aidoku_watchdog_context_cancel(aidoku_watchdog_context *context) {
    if (context != NULL) {
        atomic_store_explicit(&context->cancelled, true, memory_order_release);
    }
}

void aidoku_watchdog_prepare_current_thread(aidoku_watchdog_context *context) {
    current_context = context;
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGUSR2);
    pthread_sigmask(SIG_UNBLOCK, &signals, NULL);
}

void aidoku_watchdog_clear_current_thread(void) {
    current_context = NULL;
    deadline_nanoseconds = 0;
}

uintptr_t aidoku_watchdog_current_thread(void) {
    return (uintptr_t)pthread_self();
}

static uint64_t aidoku_watchdog_now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC_RAW, &time);
    return ((uint64_t)time.tv_sec * 1000000000ULL) + (uint64_t)time.tv_nsec;
}

uint64_t aidoku_watchdog_deadline_after(uint64_t nanoseconds) {
    uint64_t now = aidoku_watchdog_now();
    deadline_nanoseconds = UINT64_MAX - now < nanoseconds ? UINT64_MAX : now + nanoseconds;
    return deadline_nanoseconds;
}

void aidoku_watchdog_clear_deadline(void) {
    deadline_nanoseconds = 0;
}

bool aidoku_watchdog_should_abort(void) {
    bool cancelled = current_context != NULL
        && atomic_load_explicit(&current_context->cancelled, memory_order_acquire);
    return cancelled || (deadline_nanoseconds != 0 && aidoku_watchdog_now() >= deadline_nanoseconds);
}

int32_t aidoku_watchdog_interrupt(uintptr_t thread) {
    if (thread == 0) {
        return -1;
    }
    return pthread_kill((pthread_t)thread, SIGUSR2);
}
