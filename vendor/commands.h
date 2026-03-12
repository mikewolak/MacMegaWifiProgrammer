#ifndef _COMMANDS_H_
#define _COMMANDS_H_


//=============================================================================
// LIBS
//=============================================================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libusb-1.0/libusb.h>

#include "util.h"

/// Maximum number of driver keys supported
#define CMD_KEYS_MAX 32

//=============================================================================
// CONSTANTS
//=============================================================================
// Supported MDMAP commands
enum {
	MDMA_OK = 0,            ///< Used to report OK status during replies
	MDMA_MANID_GET,         ///< Flash chip manufacturer ID request.
	MDMA_DEVID_GET,         ///< Flash chip device ID request.
	MDMA_READ,              ///< Flash data read command.
	MDMA_CART_ERASE,        ///< Cartridge Flash erase command.
	MDMA_SECT_ERASE,        ///< Flash sector erase command.
	MDMA_WRITE,             ///< Flash write (program) command.
	MDMA_MAN_CTRL,          ///< Manual GPIO pin control command.
	MDMA_BOOTLOADER,        ///< Puts board in bootloader mode.
	MDMA_BUTTON_GET,        ///< Gets pushbutton status.
	MDMA_WIFI_CMD,          ///< Command forwarded to the WiFi chip.
	MDMA_WIFI_CMD_LONG,     ///< Long command forwarded to the WiFi chip.
	MDMA_WIFI_CTRL,         ///< WiFi chip control action (using GPIO).
	MDMA_RANGE_ERASE,       ///< Erase a memory range of the flash chip
	MDMA_FEATURES_GET,      ///< Get programmer version and supported features
	MDMA_CART_TYPE_QUERY,   ///< Try guessing the installed cartridge type
	MDMA_CART_TYPE_SET,     ///< Set the cartridge type to use
	MDMA_CART_FLASH_LAYOUT, ///< Get cartridge flash memory layout
	__MDMA_CMD_MAX,		///< Maximum number of commands
	MDMA_ERR = 255          ///< Used to report ERROR during replies.
};

typedef enum {
	MDMA_WIFI_CTRL_RST = 0,	// Hold chip in reset state.
	MDMA_WIFI_CTRL_RUN,		// Reset the chip.
	MDMA_WIFI_CTRL_BLOAD,	// Enter bootloader mode.
	MDMA_WIFI_CTRL_APP,		// Start application.
	MDMA_WIFI_CTRL_SYNC 	// Perform a sync attemp.
} MdmaWifiCtrlCode;

typedef enum {
	MDMA_CART_TYPE_MEGAWIFI = 1,
	MDMA_CART_TYPE_GHETTO_MAPPER = 2
} MdmaCartType;

#define MeGaWiFi_VID                0x03EB
#define MeGaWiFi_PID                0x206C

#define MeGaWiFi_BOOTLOADER_VID     0x03EB
#define MeGaWiFi_BOOTLOADER_PID     0x2FF9

#define MeGaWiFi_ENDPOINT_IN        0x83
#define MeGaWiFi_ENDPOINT_OUT       0x04

#define MeGaWiFi_CONFIG             1
#define MeGaWiFi_INTERF             0

#define PAYLOAD_OFFSET			6

#define WIFI_PAYLOAD_OFFSET		4

#define ENDPOINT_LENGTH			64

#define MAX_PAYLOAD_BYTES		(ENDPOINT_LENGTH - PAYLOAD_OFFSET)

#define MAX_WIFI_PAYLOAD_BYTES 	(ENDPOINT_LENGTH - WIFI_PAYLOAD_OFFSET)

// Can be up to 512 bytes, but it looks like 384 is the
// optimum value to maximize speed
#define MAX_USB_TRANSFER_LEN	384

#define FLASH_REGION_MAX 4

/// Metadata of a flash region, consisting of several sectors.
struct flash_region {
	u32 start_addr;    //< Sector start address
	u16 num_sectors;   //< Number of sectors
	u16 sector_len;	   //< Sector length in 256 byte units
};

/// Metadata of a flash chip, describing memory layout.
struct flash_layout {
	u32 len;                  //< Length of chip in bytes
	u16 num_regions;          //< Number of regions in chip
	struct flash_region region[FLASH_REGION_MAX]; //< Region data array
} __attribute__((packed));

typedef union
{
	u8 bytes[MAX_PAYLOAD_BYTES + 6];

	struct {
		u8 cmd;
		u8 data[MAX_PAYLOAD_BYTES + 5];
	} raw;

	struct
	{
		u8 cmd;
		u8 len[3];
		u8 addr[3];

	} frame; // For read and write command

	struct {
		u8 cmd;
		u8 addr[3];
		u8 dwlen[4];
	} erase;

	struct {
		u8 cmd;
		u8 len[2];
		u8 pad;
		u8 data[MAX_WIFI_PAYLOAD_BYTES];
	} WiFiFrame;

	struct {
		u8 cmd;
		u8 pad[2];
		u8 len;
		struct flash_layout layout;
	} flash;

} Command;

typedef struct {
	uint8_t ver_major;
	uint8_t ver_minor;
	uint8_t ver_micro;
	uint8_t num_drivers;
	uint8_t key[CMD_KEYS_MAX];
} InitData;

#ifdef __cplusplus
extern "C" {
#endif

//=============================================================================
// FUNCTION PROTOTYPES
//=============================================================================
int UsbInit(void);

/// Ends USB session with device (normal close — releases interface first)
void UsbClose(void);

/// Safe teardown after physical device removal — skips libusb_release_interface
/// which asserts when the device is already gone from the OS.
void UsbCloseOnRemoval(void);

u16 MDMA_manId_get(uint8_t *manId);

u16 MDMA_devId_get(uint8_t *dev_id, uint8_t *num_ids);

u16 MDMA_cartFlashLayout(struct flash_layout *layout);

u16 MDMA_read(u32 len, int addr, u8 *data );

u16 MDMA_cart_erase();

u16 MDMA_sect_erase( int addr );

u16 MDMA_range_erase(uint32_t addr, uint32_t length);

u16 MDMA_write(u32 len, int addr, const u8 *data);

u16 MDMA_bootloader();

u16 MDMA_button_get(uint8_t *button_status);

u16 MDMA_cart_init(InitData *d);

u16 MDMA_cart_type_set(MdmaCartType cart_type);

int MDMA_WiFiCmd(uint8_t *payload, uint8_t len, uint8_t *reply);

int MDMA_WiFiCmdLong(uint8_t *payload, uint16_t len, uint8_t *reply);

int MDMA_WiFiCtrl(MdmaWifiCtrlCode code);

#ifdef __cplusplus
}
#endif

#endif // _COMMANDS_H_
