/* -----------------------------------------------------------------------------
 * core_portme.h — EEMBC CoreMark 平台移植头文件 (RV32I SoC 裸机环境)
 * -------------------------------------------------------------------------- */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>
#include "uart.h"

/* 1. 无浮点与无宿主头文件配置 */
#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif

#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif

#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif

#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif

#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

/* 2. 编译器版本与编译选项 */
#ifndef COMPILER_VERSION
 #ifdef __GNUC__
  #define COMPILER_VERSION "GCC " __VERSION__
 #else
  #define COMPILER_VERSION "GCC"
 #endif
#endif

#ifndef COMPILER_FLAGS
 #ifdef FLAGS_STR
  #define COMPILER_FLAGS FLAGS_STR
 #else
  #define COMPILER_FLAGS "-O2"
 #endif
#endif

#ifndef MEM_LOCATION
#define MEM_LOCATION "STATIC"
#endif

/* 3. 数据类型定义 (确保满足 8b/16b/32b 及指针校验) */
typedef int8_t         ee_s8;
typedef uint8_t        ee_u8;
typedef int16_t        ee_s16;
typedef uint16_t       ee_u16;
typedef int32_t        ee_s32;
typedef uint32_t       ee_u32;
typedef uint32_t       ee_ptr_int;
typedef size_t         ee_size_t;
typedef double         ee_f32;

#ifndef NULL
#define NULL ((void *)0)
#endif

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* 4. 计时器类型对接与防符号冲突 */
#define CORETIMETYPE uint64_t
typedef uint64_t CORE_TICKS;
typedef uint64_t CORETICKS;

#define EE_TICKS_PER_SEC 1000

/* 5. 迭代次数与内存配置 */
#ifndef ITERATIONS
#define ITERATIONS 2
#endif

#define MEM_METHOD MEM_STATIC
#ifndef TOTAL_DATA_SIZE
#define TOTAL_DATA_SIZE (2 * 1000)
#endif

/* 6. 标准种子配置 (Performance Run) */
#define SEED_METHOD SEED_VOLATILE
#define PERFORMANCE_RUN 1

/* 7. 单核执行与 main 参数配置 */
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0

#define MAIN_HAS_NOARGC 0
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
void portable_free(void *p);

#endif /* CORE_PORTME_H */
