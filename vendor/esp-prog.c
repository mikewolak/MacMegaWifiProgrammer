/************************************************************************//**
 * \file
 * \brief Reads ESP8266 firmware blobs and sends to the MeGaWiFi programmer
 * the required commands to flash the blobs.
 *
 * Implementation based on the information and code of the original
 * esptool: https://github.com/themadinventor/esptool
 *
 * \author Jesús Alonso (doragasu)
 * \date   2016
 *
 * \warning Module is NOT reentrant!
 ****************************************************************************/

#include "esp-prog.h"
#include "commands.h"
#include "util.h"
#include <sys/stat.h>
#include "progbar.h"

// Buffer with a flash block
static EpBuf buf;

void EpInit(void) {
}

static uint32_t EpCsum(const char *data, uint16_t len) {
	uint8_t csum = EP_CSUM_MAGIC;
	uint16_t i;

	for (i = 0; i < len; i++) {
		csum ^= data[i];
	}

	return csum;
}

static int EpSendCmd(EpCmdOp cmd, char data[], uint16_t len, uint32_t csum) {
	int ret;
	uint16_t i;

	if (len > EP_FLASH_PKT_LEN) return -1;

	buf.req.hdr.dir = EP_DIR_REQ;
	buf.req.hdr.cmd = cmd;
	/// \warning check if length must be in bytes or dwords
	buf.req.hdr.bLen = len;
	buf.req.hdr.csum = csum;
	// Copy data
	for (i = 0; i < len; i++) buf.req.data[i] = data[i];
	// Depending on the command, use the appropiate method to send data
	if ((EP_OP_RAM_DOWNLOAD_DATA == cmd) ||
			(EP_OP_FLASH_DOWNLOAD_DATA) == cmd) {
		ret = MDMA_WiFiCmdLong(buf.data, len + sizeof(EpReqHdr), buf.data);
	} else {
		ret = MDMA_WiFiCmd(buf.data, len + sizeof(EpReqHdr), buf.data);
	}
	if (0 > ret) return -1;
	
	return buf.resp.hdr.resp;
}

static uint32_t EraseSize(unsigned int num_sect, unsigned int start_sect)
{
	unsigned int head_sectors = EP_SECTORS_PER_BLOCK -
		(start_sect % EP_SECTORS_PER_BLOCK);

	if (num_sect < head_sectors) {
		head_sectors = num_sect;
	}

	if (num_sect < (2 * head_sectors)) {
		return (num_sect + 1) / 2 * EP_FLASH_SECT_LEN;
	} else {
		return (num_sect - head_sectors) * EP_FLASH_SECT_LEN;
	}
}

/// Starts download process (deletes flash and prepares for data download).
static int EpDownloadStart(size_t fLen, uint32_t addr) {
	uint32_t data[4];
	// Command requires total size (including padding), number of blocks,
	// block size and offset (address).
	// First compute number of blocks (rounding up!).
	data[1] = (fLen + EP_FLASH_SECT_LEN - 1) / EP_FLASH_SECT_LEN;
	// Now compute total size and fill block size and address.
	data[0] = EraseSize(data[1], addr / EP_FLASH_SECT_LEN);
	data[2] = EP_FLASH_SECT_LEN;
	data[3] = addr;

	// Send prepared command
	return EpSendCmd(EP_OP_FLASH_DOWNLOAD_START, (char*)data, sizeof(data),
			0);
	
	return 0;
}

EpBlobData *EpBlobLoad(const char *file_name, uint32_t addr, const Flags *f)
{
	struct stat st = {};
	FILE *fi = NULL;
	size_t totalLen;
	uint16_t seq;
	uint32_t readed;
	uint32_t pos;
	uint16_t toRead;
	EpBlobHdr *blobHdr;

	EpBlobData *b = (EpBlobData*)calloc(1, sizeof(EpBlobData));
	b->cols = f->cols;
	b->addr = addr;

	// Get file length
	if (stat(file_name, &st)) {
		perror(file_name);
		goto err;
	}
	b->len = st.st_size;
	
	// Allocate memory for each flash packet along with its packet header
	// and read the file. Round length up to an EP_FLASH_SECT multiple
	totalLen = (b->len + EP_FLASH_SECT_LEN - 1) & (~(EP_FLASH_SECT_LEN - 1));
	b->sect_total = totalLen / EP_FLASH_SECT_LEN;
	b->data = (char*) calloc(b->sect_total, EP_FLASH_PKT_LEN);
	if (!b->data) {
		perror("Allocating RAM for firmware");
			goto err;
	}

	// Open and read file
	if (!(fi = fopen(file_name, "rb"))) {
		perror(file_name);
		goto err;
	}
	for (pos = 0, seq = 0, readed = 0; readed < b->len; seq++,
			readed += EP_FLASH_SECT_LEN) {
		// Fill header (length, seq, 0, 0) for this packet
		*((uint32_t*)(b->data + pos)) = EP_FLASH_SECT_LEN;
		pos += sizeof(uint32_t);
		*((uint32_t*)(b->data + pos)) = seq;
		pos += 3 * sizeof(uint32_t);
		// Read a sector
		toRead = MIN(EP_FLASH_SECT_LEN, b->len - readed);
		if (fread(&b->data[pos], toRead, 1, fi) != 1) {
			PrintErr("Reading firmware pos 0x%X, %d bytes: ", readed, toRead);
			perror(NULL);
			fclose(fi);
			goto err; 
		}
		pos += toRead;
	}
	fclose(fi);

	// 0xFF pad the buffer
	memset(b->data + pos, 0xFF, b->sect_total * EP_FLASH_PKT_LEN - pos);

	b->len = totalLen;

	// Check if this is the first blob and correct flash parameters
	// if requested by user
	if (0 == addr && f->flash_mode < ESP_FLASH_UNCHANGED) {
	blobHdr = (EpBlobHdr*)(b->data + EP_FLASH_PKT_HEAD_LEN);
		if (0xE9 == blobHdr->magic) {
			blobHdr->spiIf = f->flash_mode;
			// TODO Allow also configuring these
			blobHdr->flashParam = EP_FLASH_PARAM(EP_SPI_LEN_4M,
					EP_SPI_SPEED_40M);
		}
	}
	
	return b;

err:
	EpBlobFree(b);

	return NULL;
}

void EpBlobFree(EpBlobData *b)
{
	if (b) {
		if (b->data) {
			free(b->data);
		}
		free(b);
	}
}

int EpSync(void)
{
	// Enter bootloader. Delays timing from esptool.py
	EpReset();
	DelayMs(50);
	EpBootloader();
	DelayMs(50);
	EpRun();
	DelayMs(50);

	// Sync WiFi chip
	return EpProgSync();
}

int EpErase(EpBlobData *b)
{
	return EpDownloadStart(b->len, b->addr);
}

EpFlashStatus EpFlashNext(EpBlobData *b)
{
	uint16_t csum;
	uint32_t flashed = b->sect * EP_FLASH_PKT_LEN;

	// Calculate data checksum and send command with data and header
	csum = EpCsum(b->data + flashed + EP_FLASH_PKT_HEAD_LEN, EP_FLASH_SECT_LEN);
	if (0 > EpSendCmd(EP_OP_FLASH_DOWNLOAD_DATA, b->data + flashed,
				EP_FLASH_PKT_LEN, csum)) {
		PrintErr("Error flashing blob at 0x%X\n", flashed);
		return EP_FLASH_ERR;
	}
	b->sect++;
	return (b->sect < b->sect_total) ? EP_FLASH_REMAINING : EP_FLASH_DONE;
}

int EpFinish(uint32_t reboot)
{
	return EpSendCmd(EP_OP_FLASH_DOWNLOAD_FINISH, (char*)&reboot,
			sizeof(uint32_t), 0);
}

// TODO: This function is a mess and should be split
int EpBlobFlash(const char *file_name, uint32_t addr, const Flags *f) {
	EpBlobData *b = NULL;
	EpFlashStatus st;

	// Address string, e.g.: 0x12345678
	char addrStr[12];
	int err = -1;

	b = EpBlobLoad(file_name, addr, f);
	if (!b) {
		goto err;
	}

	// Erase flash and prepare for data download
	printf("Erasing WiFi module, 0x%08X bytes at 0x%08X... ",
			(unsigned int) b->len, addr); fflush(stdout);
	err = EpSync();
	if (err) {
		PrintErr("Error: Could not sync ESP8266!\n");
		goto err;
	}
	err = EpErase(b);
	if (err) {
		PrintErr("Error, Could not erase flash!\n");
		goto err;
	}
	printf("OK\n");

	// Flash blob, one sector at a time.
	// TODO: WARNING, might need to unlock DIO
   	printf("Flashing WiFi firmware %s at 0x%06X...\n", file_name, addr);
	do {
		sprintf(addrStr, "0x%08X", b->sect * EP_FLASH_SECT_LEN);
		ProgBarDraw(b->sect, b->sect_total, b->cols, addrStr);
		st = EpFlashNext(b);
	} while (EP_FLASH_REMAINING == st);
	sprintf(addrStr, "0x%08X", b->sect * EP_FLASH_SECT_LEN);
	ProgBarDraw(b->sect, b->sect_total, b->cols, addrStr);
	if (EP_FLASH_DONE != st) {
		PrintErr("Flash failed!");
		goto err;
	}

	// Send download finish command
	EpFinish(TRUE);

err:
	// Free memory and return
	EpBlobFree(b);
	return err;
}

