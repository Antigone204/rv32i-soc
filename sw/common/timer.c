#include "soc.h"
#include "timer.h"

__attribute__((weak)) uint64_t get_time(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = CLINT_MTIME_HI_REG;
        lo  = CLINT_MTIME_LO_REG;
        hi2 = CLINT_MTIME_HI_REG;
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

uint32_t get_time_lo(void) {
    return CLINT_MTIME_LO_REG;
}

void delay_cycles(uint32_t cycles) {
    uint32_t start = CLINT_MTIME_LO_REG;
    while ((CLINT_MTIME_LO_REG - start) < cycles) {
        ;
    }
}
