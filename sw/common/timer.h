#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

/* 原子读取 64 位 CLINT mtime 计数器（防止 32 位低位进位撕裂） */
uint64_t get_time(void);

/* 快速读取低 32 位 mtime */
uint32_t get_time_lo(void);

/* 阻塞延时指定时钟周期数 */
void delay_cycles(uint32_t cycles);

#endif /* TIMER_H */
