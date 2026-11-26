#ifndef TRUVER_ATOMICS_H
#define TRUVER_ATOMICS_H

#include <stdint.h>
#include <stdatomic.h>

// C11 atomics for the real-time path (iOS 17 / macOS 14 have no Swift Atomic type).
// The storage is a plain int64_t allocated by Swift; 64-bit atomics are lock-free on all Apple targets.

static inline int64_t truver_load_acquire(const int64_t *p) {
    return atomic_load_explicit((const _Atomic int64_t *)p, memory_order_acquire);
}

static inline void truver_store_release(int64_t *p, int64_t value) {
    atomic_store_explicit((_Atomic int64_t *)p, value, memory_order_release);
}

static inline int64_t truver_load_relaxed(const int64_t *p) {
    return atomic_load_explicit((const _Atomic int64_t *)p, memory_order_relaxed);
}

static inline void truver_store_relaxed(int64_t *p, int64_t value) {
    atomic_store_explicit((_Atomic int64_t *)p, value, memory_order_relaxed);
}

#endif
