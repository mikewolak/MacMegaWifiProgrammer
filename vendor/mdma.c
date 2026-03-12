#include <stdio.h>
#include <stdlib.h>

#include "mdma.h"
#include "commands.h"
#include "progbar.h"

/// Receives a MemImage pointer with full info in file name (e.g.
/// m->file = "rom.bin:6000:1"). Removes from m->file information other
/// than the file name, and fills the remaining structure fields if info
/// is provided (e.g. info in previous example would cause m = {"rom.bin",
/// 0x6000, 1}).
int ParseMemArgument(MemImage *m)
{
	int i;
	char *addr = NULL;
	char *len  = NULL;
	char *endPtr;

	// Set address and length to default values
	m->len = m->addr = 0;

	// First argument is name. Find where it ends
	for (i = 0; i < (MAX_FILELEN + 1) && m->file[i] != '\0' &&
			m->file[i] != ':'; i++);
	// Check if end reached without finding end of string
	if (i == MAX_FILELEN + 1) return 1;
	if (m->file[i] == '\0') return 0;

	// End of token marker, search address
	m->file[i++] = '\0';
	addr = m->file + i;
	for (; i < (MAX_FILELEN + 1) && m->file[i] != '\0' && m->file[i] != ':';
			i++);
	// Check if end reached without finding end of string
	if (i == MAX_FILELEN + 1) return 1;
	// If end of token marker, search length
	if (m->file[i] == ':') {
		m->file[i++] = '\0';
		len = m->file + i;
		// Verify there's an end of string
		for (; i < (MAX_FILELEN + 1) && m->file[i] != '\0'; i++);
		if (m->file[i] != '\0') return 1;
	}
	// Convert strings to numbers and return
	if (addr && *addr) m->addr = strtol(addr, &endPtr, 0);
	if (m->addr == 0 && addr == endPtr) return 2;
	if (len  && *len)  m->len  = strtol(len, &endPtr, 0);
	if (m->len  == 0 && len  == endPtr) return 3;

	return 0;
}

void PrintMemImage(MemImage *m)
{
	printf("%s", m->file);
	if (m->addr) printf(" at address 0x%06X", m->addr);
	if (m->len ) printf(" (%d bytes)", m->len);
}

void PrintMemError(int code)
{
	switch (code) {
		case 0: printf("Memory range OK.\n"); break;
		case 1: PrintErr("Invalid memory range string.\n"); break;
		case 2: PrintErr("Invalid memory address.\n"); break;
		case 3: PrintErr("Invalid memory length.\n"); break;
		default: PrintErr("Unknown memory specification error.\n");
	}
}

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
int ParseMemRange(char inStr[], uint32_t *addr, uint32_t *len)
{
	int32_t i;
	char *saddr, *endPtr;
	char scratch;
	long val;

	// Seek end of string or field separator (:)
	for (i = 0; (i < (MAX_MEM_RANGE + 1)) && (inStr[i] != '\0') &&
			(inStr[i] != ':'); i++);

	if (i == (MAX_MEM_RANGE + 1)) return 1;
	// Store end of string or separator, and ensure proper end of string
	scratch = inStr[i];
	inStr[i++] = '\0';
	// Convert to long
	val = strtol(inStr, &endPtr, 0);
	if (*endPtr != '\0' || val < 0) return 1;
	*addr = val;
	// If we had field separator, repeat scan for length
	if (scratch == '\0') return 0;
	saddr = inStr + i;
	for (; (i < (MAX_MEM_RANGE + 1)) && (inStr[i] != '\0'); i++);
	if (i == (MAX_MEM_RANGE + 1)) return 1;
	val = strtol(saddr, &endPtr, 0);
	if (*endPtr != '\0' || val < 0) return 1;
	*len = val;
	return 0;
}

// Allocs a buffer, reads a file to the buffer, and flashes the file pointed 
// by the file argument. The buffer must be deallocated when not needed,
// using free() call.
// Note fWr.len is updated if not specified.
// Note buffer is byte swapped before returned.
u8 *AllocAndFlash(MemImage *fWr, int autoErase, int columns)
{
	FILE *rom;
	u8 *writeBuf;
	uint32_t addr;
	uint32_t toWrite;
	uint32_t i;
	// Address string, e.g.: 0x123456
	char addrStr[9];

	// Open the file to flash
	if (!(rom = fopen(fWr->file, "rb"))) {
		perror(fWr->file);
		return NULL;
	}

	// Obtain length if not specified
	if (!fWr->len) {

		fseek(rom, 0, SEEK_END);
		fWr->len = ftell(rom);
		fseek(rom, 0, SEEK_SET);
	}

	writeBuf = malloc(fWr->len);
	if (!writeBuf) {
		perror("Allocating write buffer RAM");
		fclose(rom);
		return NULL;
	}
	fread(writeBuf, fWr->len, 1, rom);
	fclose(rom);

	// If requested, perform auto-erase
	if (autoErase) {
		printf("Auto-erasing range 0x%06X:%06X... ", fWr->addr, fWr->len);
		fflush(stdout);
		if (MDMA_range_erase(fWr->addr, fWr->len)) {
			free(writeBuf);
			PrintErr("Auto-erase failed!\n");
			return NULL;
		}
		printf("OK!\n");
	}

	printf("Flashing ROM %s starting at 0x%06X...\n", fWr->file, fWr->addr);

	for (i = 0, addr = fWr->addr; i < fWr->len;) {
		toWrite = MIN(TRANSFER_LEN_MAX, fWr->len - i);
		if (MDMA_write(toWrite, addr, writeBuf + i)) {
			free(writeBuf);
			PrintErr("Couldn't write to cart!\n");
			return NULL;
		}
		// Update vars and draw progress bar
		i += toWrite;
		addr += toWrite;
		sprintf(addrStr, "0x%06X", addr);
		ProgBarDraw(i, fWr->len, columns, addrStr);
	}
	putchar('\n');
	return writeBuf;
}

// Allocs a buffer and reads from cart. Does NOT save the buffer to a file.
// Buffer must be deallocated using free() when not needed anymore.
u8 *AllocAndRead(MemImage *fRd, int columns)
{
	u8 *readBuf;
	uint32_t toRead;
	uint32_t addr;
	uint32_t i;
	// Address string, e.g.: 0x123456
	char addrStr[9];

	readBuf = (u8*)malloc(fRd->len);
	if (!readBuf) {
		perror("Allocating read buffer RAM");
		return NULL;
	}
	printf("Reading cart starting at 0x%06X...\n", fRd->addr);

	fflush(stdout);
	for (i = 0, addr = fRd->addr; i < fRd->len;) {
		toRead = MIN(TRANSFER_LEN_MAX, fRd->len - i);
		if (MDMA_read(toRead, addr, readBuf + i)) {
			free(readBuf);
			PrintErr("Couldn't read from cart!\n");
			return NULL;
		}
		fflush(stdout);
		// Update vars and draw progress bar
		i += toRead;
		addr += toRead;
		sprintf(addrStr, "0x%06X", addr);
		ProgBarDraw(i, fRd->len, columns, addrStr);
	}
	putchar('\n');
	return readBuf;
}
