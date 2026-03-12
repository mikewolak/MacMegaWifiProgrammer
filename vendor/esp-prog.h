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
 *
 * \defgroup esp-prog ESP8288 firmware programmer for MeGaWiFi.
 * \{
 ****************************************************************************/

#ifndef _ESP_PROG_H_
#define _ESP_PROG_H_

#include <stdint.h>

/// Flash chip type. Compatible with EpSpiIf enum
enum esp_flash_mode {
	ESP_FLASH_QIO = 0,
	ESP_FLASH_QOUT,
	ESP_FLASH_DIO,
	ESP_FLASH_DOUT,
	ESP_FLASH_UNCHANGED,
	ESP_FLASH_MAX
};

/// Commandline flags (for arguments without parameters).
typedef struct {
	union {
		uint16_t all;
		struct {
			uint16_t verify:1;		/// Verify flash write if TRUE
			uint16_t verbose:1;		/// Print extra information on screen
			uint16_t flashId:1;		/// Show flash chip id
			uint16_t layout:1;		/// Show flash memory layout
			uint16_t erase:1;		/// Erase flash
			uint16_t pushbutton:1;	/// Read pushbutton status
			uint16_t dry:1;			/// Dry run
			uint16_t boot:1;			/// Enter bootloader
			uint16_t auto_erase:1;	/// Automatically erase flash
		};
	};
	enum esp_flash_mode flash_mode;	/// SPI flash mode
	int cols;				/// Number of columns of the terminal
} Flags;

/// Prints text only if (verbose==TRUE)
#define PrintVerb(...)	do{if(f.verbose)printf(__VA_ARGS__);}while(0)

/// Initial magic byte used for checksum calculation
#define EP_CSUM_MAGIC			0xEF

/// Number of sync retries before giving up
#define EP_SYNC_RETRIES			100

/// Flash sector length (4 KiB)
#define EP_FLASH_SECT_LEN		(4 * 1024)

/// Block size is 64 KiB
#define EP_SECTORS_PER_BLOCK		16

/// Header for each flash segment packet
#define EP_FLASH_PKT_HEAD_LEN	(4 * sizeof(uint32_t))

/// Size of each flash segment packet, including header plus data
#define EP_FLASH_PKT_LEN		(EP_FLASH_PKT_HEAD_LEN + EP_FLASH_SECT_LEN)

/** \addtogroup esp-prog EpSpiIf Supported SPI flash interfaces.
 *  \{ */
typedef enum {
	EP_SPI_IF_QIO	= 0x00,
	EP_SPI_IF_QOUT	= 0x01,
	EP_SPI_IF_DIO	= 0x02,
	EP_SPI_IF_DOUT	= 0x03
} EpSpiIf;
/** \} */

/** \addtogroup esp-prog flashLengh Supported flash sizes. For
 *              using with the macro EP_FLASH_PARAM().
 *  \{ */
#define EP_SPI_LEN_512K		0x00	///< 512 KiB
#define EP_SPI_LEN_256K		0x10	///< 256 KiB
#define EP_SPI_LEN_1M		0x20	///< 1 MiB
#define EP_SPI_LEN_2M		0x30	///< 2 MiB
#define EP_SPI_LEN_4M		0x40	///< 4 MiB
/** \} */

/** \addtogroup esp-prog flashSpeed Supported flash speeds. For
 *              using with the macro EP_FLASH_PARAM().
 *  \{ */
#define EP_SPI_SPEED_40M	0x00
#define EP_SPI_SPEED_26M	0x01
#define EP_SPI_SPEED_20M	0x02
#define EP_SPI_SPEED_80M	0x0F
/** \} */


/** \addtogroup esp-prog EpDir Direction codes for requests/responses.
 *  \{ */
typedef enum {
	EP_DIR_REQ = 0x00,		///< Request code.
	EP_DIR_RESP				///< Response code.
} EpDir;
/** \} */

/// Direction for command requests
#define EP_DIR_REQ			0x00
/// Direction for command responses
#define EP_DIR_RESP			0x01

/// Macro to build the flashParam byte of the EpBlobHdr structure.
/// Use one constant in EP_SPI_LEN_XXXX for len parameter, and one constant
/// in EP_SPI_SPEED_XXX for the speed parameter.
#define EP_FLASH_PARAM(len, speed)	((len) | (speed))

/** \addtogroup esp-prog EpCmdOp Command opcodes supported by ESP8266 chip.
 *  \{ */
typedef enum
{
	/// Start firmware flash process
    EP_OP_FLASH_DOWNLOAD_START	= 0x02,
	/// Send firmware data
    EP_OP_FLASH_DOWNLOAD_DATA 	= 0x03,
	/// End firmware flash process
    EP_OP_FLASH_DOWNLOAD_FINISH	= 0x04,
	/// Start RAM data download process
    EP_OP_RAM_DOWNLOAD_START  	= 0x05,
	/// End RAM data download process
    EP_OP_RAM_DOWNLOAD_FINISH  	= 0x06,
	/// Sen RAM data
    EP_OP_RAM_DOWNLOAD_DATA   	= 0x07,
	/// Sync communications interface
    EP_OP_SYNC_FRAME          	= 0x08,
	/// Write ESP8266 register
    EP_OP_WRITE_REGISTER      	= 0x09,
	/// Read ESP8266 register
    EP_OP_READ_REGISTER       	= 0x0A,
	/// Set SPI parameters
    EP_OP_CONFIGURE_SPI_PARAMS 	= 0x0B,
} EpCmdOp;
/** \} */

/** \addtogroup esp-prog EpReqHdr Header of a request command.
 *  \{ */
typedef struct {
	uint8_t dir;		///< Direction (always 0x00 for requests).
	uint8_t cmd;		///< Command opcode
	uint16_t bLen;		///< Body length
	uint32_t csum;		///< Payload checksum (only for block transfers).
} EpReqHdr;
/** \} */

/** \addtogroup esp-prog EpRespHdr Header of a response command.
 *  \{ */
typedef struct {
	uint8_t dir;		///< Direction (always 0x01 for responses).
	uint8_t cmd;		///< Command opcode (the same used in request).
	uint16_t bLen;		///< Body length (usually 2).
	uint32_t resp;		///< Response data for some operations.
	uint8_t status;		///< Status code (0 = success, 1 = failure).
	uint8_t lastErr;	///< Last error code (not reset on success).
} EpRespHdr;
/** \} */

/** \addtogroup esp-prog EpBuf Buffer used for command requests and responses.
 *  \{ */
typedef union {
	/// Access as byte array.
	uint8_t data[sizeof(EpReqHdr) + EP_FLASH_PKT_LEN];
	/// Access as request
	struct {
		EpReqHdr hdr;
		union {
			uint8_t data[EP_FLASH_PKT_LEN];
			uint32_t dwData[EP_FLASH_PKT_LEN/4];
		};
	} req;
	/// Access as response.
	struct {
		EpRespHdr hdr;
		uint8_t data[sizeof(EpReqHdr)+EP_FLASH_PKT_LEN-sizeof(EpRespHdr)];
	} resp;
} EpBuf;
/** \} */

/** \addtogroup esp-prog EpBlobHdr Header of the firmware blobs.
 *  \{ */
typedef struct {
	uint8_t magic;			///< Magic number (always 0xE9).
	uint8_t numSegs;		///< Number of segments.
	uint8_t spiIf;			///< SPI flash interface.
	uint8_t flashParam;		///< Flash parameters for the SPI chip.
	uint32_t entryPoint;	///< Firmware entry point.
} EpBlobHdr;
/** \} */

/** \addtogroup esp-prog EpSegHdr Header of each blob segment
 *  \{ */
typedef struct {
	uint32_t memOffset;		///< Blob segment offset in memory.
	uint32_t segSize;		///< Blob segment size.
}EpSegHdr;
/** \} */

typedef struct {
	char *data;
	uint32_t addr;
	uint32_t len;
	int sect;
	int sect_total;
	int cols;
} EpBlobData ;

typedef enum {
	EP_FLASH_ERR = -1,
	EP_FLASH_DONE = 0,
	EP_FLASH_REMAINING = 1
} EpFlashStatus;

#ifdef __cplusplus
extern "C" {
#endif

int EpBlobFlash(const char *file_name, uint32_t addr, const Flags *f);

EpBlobData *EpBlobLoad(const char *file_name, uint32_t addr, const Flags *f);
void EpBlobFree(EpBlobData *b);
int EpSync(void);
int EpErase(EpBlobData *b);
EpFlashStatus EpFlashNext(EpBlobData *b);
int EpFinish(uint32_t reboot);

#define EpReset()		MDMA_WiFiCtrl(MDMA_WIFI_CTRL_RST)

#define EpRun()			MDMA_WiFiCtrl(MDMA_WIFI_CTRL_RUN)

#define EpBootloader()	MDMA_WiFiCtrl(MDMA_WIFI_CTRL_BLOAD)

#define EpProgStart()	MDMA_WiFiCtrl(MDMA_WIFI_CTRL_APP)

#define EpProgSync()	MDMA_WiFiCtrl(MDMA_WIFI_CTRL_SYNC)

#ifdef __cplusplus
}
#endif

#endif /*_ESP_PROG_H_*/

/** \} */

