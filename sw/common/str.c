#include "str.h"
#include <stdint.h>

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    while (n--) {
        *d++ = *s++;
    }
    return dst;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s;
    uint8_t v = (uint8_t)c;
    while (n--) {
        *p++ = v;
    }
    return s;
}

void *memmove(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    if (d < s) {
        while (n--) {
            *d++ = *s++;
        }
    } else if (d > s) {
        d += n;
        s += n;
        while (n--) {
            *--d = *--s;
        }
    }
    return dst;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *p1 = (const uint8_t *)s1;
    const uint8_t *p2 = (const uint8_t *)s2;
    while (n--) {
        if (*p1 != *p2) {
            return (int)(*p1) - (int)(*p2);
        }
        p1++;
        p2++;
    }
    return 0;
}

size_t strlen(const char *s) {
    const char *p = s;
    while (*p) {
        p++;
    }
    return (size_t)(p - s);
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return (int)((unsigned char)*s1) - (int)((unsigned char)*s2);
}

int strncmp(const char *s1, const char *s2, size_t n) {
    if (n == 0) return 0;
    while (--n && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return (int)((unsigned char)*s1) - (int)((unsigned char)*s2);
}

char *strcpy(char *dst, const char *src) {
    char *r = dst;
    while ((*dst++ = *src++) != '\0') {
        ;
    }
    return r;
}
