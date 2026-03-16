# Makefile — MegaDrive Programmer (native macOS Obj-C)
#
# Builds MegaDriveProgrammer.app in ./build/
#
# Requires only Xcode Command Line Tools — no Homebrew dependencies.
# libusb 1.0.29 is vendored in third_party/ and built from source.

APP_NAME    = MegaWifiProgrammer
BUNDLE_NAME = $(APP_NAME).app
BUILD_DIR   = build
OBJ_DIR     = $(BUILD_DIR)/obj
APP_BUNDLE  = $(BUILD_DIR)/$(BUNDLE_NAME)
BINARY      = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

# --------------------------------------------------------------------------
# Toolchain
# --------------------------------------------------------------------------
CC      = clang
CFLAGS  = -Wall -O2 -fobjc-arc \
          -Ithird_party/libusb-1.0.29 \
          -Ithird_party/libusb-1.0.29/libusb \
          -Ivendor -Isrc -Isrc/tabs \
          -mmacosx-version-min=11.0

LDFLAGS = -framework Cocoa \
          -framework IOKit \
          -framework CoreFoundation \
          -framework Security \
          -framework SceneKit \
          -framework QuartzCore \
          $(BUILD_DIR)/libusb.a

# --------------------------------------------------------------------------
# libusb 1.0.29 — built from source, macOS/Darwin backend
# --------------------------------------------------------------------------
LIBUSB_DIR = third_party/libusb-1.0.29
LIBUSB_A   = $(BUILD_DIR)/libusb.a

LIBUSB_SRCS = \
    $(LIBUSB_DIR)/libusb/core.c \
    $(LIBUSB_DIR)/libusb/descriptor.c \
    $(LIBUSB_DIR)/libusb/hotplug.c \
    $(LIBUSB_DIR)/libusb/io.c \
    $(LIBUSB_DIR)/libusb/strerror.c \
    $(LIBUSB_DIR)/libusb/sync.c \
    $(LIBUSB_DIR)/libusb/os/darwin_usb.c \
    $(LIBUSB_DIR)/libusb/os/events_posix.c \
    $(LIBUSB_DIR)/libusb/os/threads_posix.c

LIBUSB_OBJS = $(patsubst $(LIBUSB_DIR)/%.c,$(OBJ_DIR)/libusb/%.o,$(LIBUSB_SRCS))

LIBUSB_CFLAGS = -O2 \
    -I$(LIBUSB_DIR) \
    -I$(LIBUSB_DIR)/libusb \
    -mmacosx-version-min=11.0 \
    -Wno-deprecated-declarations

# --------------------------------------------------------------------------
# App sources
# --------------------------------------------------------------------------
VENDOR_C = vendor/commands.c \
           vendor/mdma.c \
           vendor/esp-prog.c \
           vendor/progbar.c

SRC_M = src/main.m \
        src/AppDelegate.m \
        src/AboutWindowController.m \
        src/MDMADevice.m \
        src/MainWindowController.m \
        src/tabs/BaseTabViewController.m \
        src/tabs/WriteTabViewController.m \
        src/tabs/ReadTabViewController.m \
        src/tabs/EraseTabViewController.m \
        src/tabs/WiFiTabViewController.m \
        src/tabs/InfoTabViewController.m \
        src/tabs/FlashRecoveryTabViewController.m

OBJS_C = $(patsubst %.c,$(OBJ_DIR)/%.o,$(VENDOR_C))
OBJS_M = $(patsubst %.m,$(OBJ_DIR)/%.o,$(SRC_M))
OBJS   = $(OBJS_C) $(OBJS_M)

# --------------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------------
DMG_NAME    = MegaWifiProgrammer
DMG_OUT     = $(BUILD_DIR)/$(DMG_NAME).dmg

.PHONY: all clean run dmg

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(BINARY) Resources/Info.plist Resources/wflash.bin Resources/AppIcon.icns me_floyd.png
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Resources/Info.plist    $(APP_BUNDLE)/Contents/Info.plist
	@cp Resources/wflash.bin    $(APP_BUNDLE)/Contents/Resources/wflash.bin
	@cp Resources/AppIcon.icns  $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp me_floyd.png            $(APP_BUNDLE)/Contents/Resources/me_floyd.png
	@echo "Built $(APP_BUNDLE)"

$(BINARY): $(OBJS) $(LIBUSB_A)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJS) $(LDFLAGS) -o $@

# libusb static library
$(LIBUSB_A): $(LIBUSB_OBJS)
	@mkdir -p $(BUILD_DIR)
	libtool -static -o $@ $^

$(OBJ_DIR)/libusb/%.o: $(LIBUSB_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(LIBUSB_CFLAGS) -c $< -o $@

# App object files
$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

run: all
	open $(APP_BUNDLE)

# --------------------------------------------------------------------------
# DMG distribution package
# --------------------------------------------------------------------------
DMG_STAGING = $(BUILD_DIR)/dmg-staging

dmg: all
	@rm -f $(DMG_OUT)
	@rm -rf $(DMG_STAGING)
	@mkdir -p $(DMG_STAGING)
	@cp -R $(APP_BUNDLE) $(DMG_STAGING)/
	@ln -s /Applications $(DMG_STAGING)/Applications
	@echo "Creating DMG…"
	@hdiutil create \
	    -volname "MegaWifi Programmer" \
	    -srcfolder $(DMG_STAGING) \
	    -ov -format UDZO \
	    $(DMG_OUT)
	@rm -rf $(DMG_STAGING)
	@echo "DMG ready: $(DMG_OUT)"

clean:
	rm -rf $(BUILD_DIR)
