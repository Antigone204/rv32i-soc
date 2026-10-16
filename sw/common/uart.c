#include "soc.h"
#include "uart.h"

void uart_init(void) {
    UART_TXCTRL_REG = 1UL;
    UART_RXCTRL_REG = 1UL;
}

void uart_putc(int ch) {
    /* 轮询等待 TX FIFO 非满 (bit[31] == 0) */
    while (UART_TXDATA_REG & UART_TXFULL_MASK) {
        ;
    }
    UART_TXDATA_REG = (uint32_t)(ch & 0xFF);
}

int uart_getc_nonblock(void) {
    uint32_t val = UART_RXDATA_REG;
    if (val & UART_RXEMPTY_MASK) {
        return -1;
    }
    return (int)(val & 0xFFU);
}

void uart_puts(const char *s) {
    if (!s) return;
    while (*s) {
        uart_putc(*s++);
    }
}

int putchar(int c) {
    uart_putc(c);
    return c;
}

int puts(const char *s) {
    uart_puts(s);
    uart_putc('\n');
    return 0;
}

static int print_uint(uint32_t val, uint32_t base, int upper, int width, char pad_c) {
    char buf[16];
    int i = 0;
    int count = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";

    if (val == 0) {
        buf[i++] = '0';
    } else {
        while (val > 0) {
            buf[i++] = digits[val % base];
            val /= base;
        }
    }

    while (width > i) {
        uart_putc(pad_c);
        width--;
        count++;
    }

    while (i > 0) {
        uart_putc(buf[--i]);
        count++;
    }
    return count;
}

int vprintf(const char *fmt, va_list ap) {
    int count = 0;

    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            uart_putc(*fmt);
            count++;
            continue;
        }

        fmt++; /* 跳过 '%' */
        if (*fmt == '\0') break;

        char pad_c = ' ';
        int width = 0;

        if (*fmt == '0') {
            pad_c = '0';
            fmt++;
        }

        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }

        /* 跳过可选的 'l' 修饰符 (32位下 long 与 int 同宽) */
        if (*fmt == 'l') {
            fmt++;
        }

        switch (*fmt) {
            case 'c': {
                int c = va_arg(ap, int);
                uart_putc(c);
                count++;
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (!s) s = "(null)";
                while (*s) {
                    uart_putc(*s++);
                    count++;
                }
                break;
            }
            case 'd':
            case 'i': {
                int32_t v = va_arg(ap, int32_t);
                uint32_t u;
                if (v < 0) {
                    uart_putc('-');
                    count++;
                    if (width > 0) width--;
                    u = (uint32_t)(-(v + 1)) + 1U;
                } else {
                    u = (uint32_t)v;
                }
                count += print_uint(u, 10U, 0, width, pad_c);
                break;
            }
            case 'u': {
                uint32_t u = va_arg(ap, uint32_t);
                count += print_uint(u, 10U, 0, width, pad_c);
                break;
            }
            case 'x': {
                uint32_t u = va_arg(ap, uint32_t);
                count += print_uint(u, 16U, 0, width, pad_c);
                break;
            }
            case 'X': {
                uint32_t u = va_arg(ap, uint32_t);
                count += print_uint(u, 16U, 1, width, pad_c);
                break;
            }
            case 'p': {
                uint32_t u = (uint32_t)(uintptr_t)va_arg(ap, void *);
                uart_puts("0x");
                count += 2;
                count += print_uint(u, 16U, 0, 8, '0');
                break;
            }
            case '%': {
                uart_putc('%');
                count++;
                break;
            }
            default: {
                uart_putc('%');
                uart_putc(*fmt);
                count += 2;
                break;
            }
        }
    }

    return count;
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}
