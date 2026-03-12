#ifndef _MDMA_H_
#define _MDMA_H_

#include <stdint.h>
#include "util.h"

/// Maximum length of a file
#define MAX_FILELEN		255
/// Maximum length of a memory range.
#define MAX_MEM_RANGE	24
#define VERSION_MAJOR	0x1
#define VERSION_MINOR	0x0

#define TRANSFER_LEN_MAX 65536

/// Structure containing a memory image (file, address and length)
typedef struct {
	char *file;
	uint32_t addr;
	uint32_t len;
} MemImage;

#ifdef __cplusplus
extern "C" {
#endif

/// Receives a MemImage pointer with full info in file name (e.g.
/// m->file = "rom.bin:6000:1"). Removes from m->file information other
/// than the file name, and fills the remaining structure fields if info
/// is provided (e.g. info in previous example would cause m = {"rom.bin",
/// 0x6000, 1}).
int ParseMemArgument(MemImage *m);

void PrintMemImage(MemImage *m);

void PrintMemError(int code);

/************************************************************************//**
 * Parses an input string containing a memory range, obtaining the address
 * and length. If any of these parameters is not present, they are set to
 * 0. Parameters are separated by colon character.
 *
 * \param[in]  inStr Input string containing the memory range.
 * \param[out] addr  Parsed address.
 * \param[out] len   Parsed length.
 *
 * \return 0 if OK, 1 if error.
 ****************************************************************************/
int ParseMemRange(char inStr[], uint32_t *addr, uint32_t *len);

// Allocs a buffer, reads a file to the buffer, and flashes the file pointed 
// by the file argument. The buffer must be deallocated when not needed,
// using free() call.
// Note fWr.len is updated if not specified.
// Note buffer is byte swapped before returned.
u8 *AllocAndFlash(MemImage *fWr, int autoErase, int columns);

// Allocs a buffer and reads from cart. Does NOT save the buffer to a file.
// Buffer must be deallocated using free() when not needed anymore.
u8 *AllocAndRead(MemImage *fRd, int columns);

#ifdef __cplusplus
}
#endif

#endif /*_MDMA_H_*/

