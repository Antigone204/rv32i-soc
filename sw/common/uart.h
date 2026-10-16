#ifndef UART_H
#define UART_H

#include <stdint.h>
#include <stdarg.h>

void uart_init(void);
void uart_putc(int ch);
int  uart_getc_nonblock(void);
void uart_puts(const char *s);

/* 标准 / CoreMark 兼容格式化输出接口 */
int putchar(int c);
int puts(const char *s);
int vprintf(const char *fmt, va_list ap);
int printf(const char *fmt, ...);
int ee_printf(const char *fmt, ...);

#endif /* UART_H */
