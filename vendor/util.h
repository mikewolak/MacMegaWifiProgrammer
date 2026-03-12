#ifndef _UTIL_H_
#define _UTIL_H_

#if defined(_WIN32) || defined(WIN32) || defined(__CYGWIN__) || defined(__MINGW32__) || defined(__BORLANDC__)
#define __OS_WIN
#include <windows.h>
#else
#include <unistd.h>
#endif

#include <stdint.h>

//=============================================================================
// TYPES
//=============================================================================
typedef char s8;
typedef int16_t s16;
typedef int32_t s32;
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef MAX
#define MAX(a,b)	((a)>(b)?(a):(b))
#endif
#ifndef MIN
#define MIN(a,b)	((a)<(b)?(a):(b))
#endif

/// printf-like macro that writes on stderr instead of stdout
#define PrintErr(...)	do{fprintf(stderr, __VA_ARGS__);}while(0)

// Delay ms function, compatible with both Windows and Unix
#ifdef __OS_WIN
#define DelayMs(ms) Sleep(ms)
#else
#define DelayMs(ms) usleep((ms)*1000)
#endif

#endif //_UTIL_H_

