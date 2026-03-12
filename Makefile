# Makefile — MegaDrive Programmer (native macOS Obj-C)
#
# Builds MegaDriveProgrammer.app in ./build/
#
# Requires:
#   - Xcode Command Line Tools  (clang, actool, etc.)
#   - libusb-1.0  (brew install libusb)

APP_NAME    = MegaDriveProgrammer
BUNDLE_NAME = $(APP_NAME).app
BUILD_DIR   = build
OBJ_DIR     = $(BUILD_DIR)/obj
APP_BUNDLE  = $(BUILD_DIR)/$(BUNDLE_NAME)
BINARY      = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

# --------------------------------------------------------------------------
# Toolchain
# --------------------------------------------------------------------------
HOMEBREW    = /Users/MWOLAK/homebrew
CC          = clang
CFLAGS      = -Wall -O2 -fobjc-arc \
              -I$(HOMEBREW)/Cellar/libusb/1.0.29/include \
              -Ivendor -Isrc -Isrc/tabs \
              -mmacosx-version-min=11.0

LDFLAGS     = -framework Cocoa \
              -framework IOKit \
              -framework CoreFoundation \
              -L$(HOMEBREW)/lib -lusb-1.0

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
VENDOR_C = vendor/commands.c \
           vendor/mdma.c \
           vendor/esp-prog.c \
           vendor/progbar.c

SRC_M = src/main.m \
        src/AppDelegate.m \
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
.PHONY: all clean run

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(BINARY) Resources/Info.plist Resources/wflash.bin
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Resources/Info.plist   $(APP_BUNDLE)/Contents/Info.plist
	@cp Resources/wflash.bin   $(APP_BUNDLE)/Contents/Resources/wflash.bin
	@echo "Built $(APP_BUNDLE)"

$(BINARY): $(OBJS)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJS) $(LDFLAGS) -o $@

$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

run: all
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)
