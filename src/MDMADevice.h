//  MDMADevice.h — USB device abstraction with auto-reconnect and retry logic

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MDMADeviceConnectedNotification;
extern NSString *const MDMADeviceDisconnectedNotification;

typedef void (^MDMAProgressBlock)(double fraction, NSString *status);
typedef void (^MDMACompletionBlock)(NSError * _Nullable error);
typedef void (^MDMADataCompletionBlock)(NSData * _Nullable data, NSError * _Nullable error);

@interface MDMAInitInfo : NSObject
@property (nonatomic) uint8_t verMajor, verMinor, verMicro;
@property (nonatomic) uint8_t numDrivers;
@property (nonatomic, copy) NSArray<NSNumber*> *driverKeys;
@end

@interface MDMAFlashRegion : NSObject
@property (nonatomic) uint32_t startAddr;
@property (nonatomic) uint16_t numSectors;
@property (nonatomic) uint32_t sectorLen;
@end

@interface MDMAFlashLayout : NSObject
@property (nonatomic) uint32_t totalLen;
@property (nonatomic, copy) NSArray<MDMAFlashRegion*> *regions;
@end

@interface MDMADevice : NSObject

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly, nullable) MDMAInitInfo *deviceInfo;
@property (nonatomic) NSUInteger maxRetries;        // default 3
@property (nonatomic) NSTimeInterval retryDelay;    // default 0.5s

+ (instancetype)sharedDevice;

// Connection management
- (void)startMonitoring;   // begin IOKit USB watch + auto-connect
- (void)stopMonitoring;
- (void)connectWithCompletion:(nullable MDMACompletionBlock)completion;
- (void)disconnect;

// Cartridge type (1=MegaWiFi, 2=FrugalMapper)
- (void)setCartType:(uint8_t)type completion:(nullable MDMACompletionBlock)completion;

// Info queries
- (void)queryFlashIDsWithCompletion:(void(^)(uint8_t manId, uint8_t d0, uint8_t d1, uint8_t d2, NSError * _Nullable))completion;
- (void)queryFlashLayoutWithCompletion:(void(^)(MDMAFlashLayout * _Nullable, NSError * _Nullable))completion;
- (BOOL)readPushbuttonState:(uint8_t *)outState;

// Flash operations
- (void)readFlashAtAddress:(uint32_t)addr
                    length:(uint32_t)len
                  progress:(nullable MDMAProgressBlock)progress
                completion:(MDMADataCompletionBlock)completion;

- (void)writeFlashData:(NSData *)data
             atAddress:(uint32_t)addr
             autoErase:(BOOL)autoErase
                verify:(BOOL)verify
              progress:(nullable MDMAProgressBlock)progress
            completion:(MDMACompletionBlock)completion;

- (void)eraseFullChipWithProgress:(nullable MDMAProgressBlock)progress
                       completion:(MDMACompletionBlock)completion;

- (void)eraseRangeAtAddress:(uint32_t)addr
                     length:(uint32_t)len
                   progress:(nullable MDMAProgressBlock)progress
                 completion:(MDMACompletionBlock)completion;

// WiFi ROM transfer — macOS is TCP client, Genesis wflash ROM is server on port 1989.
// The Genesis accepts exactly ONE connection per session; the caller must establish
// the socket with connectToWflashHost:port:completion: and pass it to writeFlash.
// After the write the socket is closed automatically.
- (void)connectToWflashHost:(NSString *)host
                       port:(uint16_t)port
                 completion:(void(^)(int sock, NSError * _Nullable error))completion;

- (void)writeFlashOnSocket:(int)sock
                      data:(NSData *)data
                 atAddress:(uint32_t)addr
                  progress:(nullable MDMAProgressBlock)progress
                completion:(MDMACompletionBlock)completion;

// Bootloader entry (device disconnects after this)
- (void)enterBootloaderWithCompletion:(nullable MDMACompletionBlock)completion;

// Cancel the current in-progress operation
- (void)cancelCurrentOperation;

@end

NS_ASSUME_NONNULL_END
