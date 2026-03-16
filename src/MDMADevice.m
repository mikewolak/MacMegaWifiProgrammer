//  MDMADevice.m — USB device abstraction with auto-reconnect and retry

#import "MDMADevice.h"
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOKitLib.h>

// Include C backend
#include "../vendor/commands.h"
#include "../vendor/mdma.h"


// ── Transfer stats helper ──────────────────────────────────────────────────────
// Tracks bytes/sec and ETA; embedded in status string passed to progress block.
@interface MDMATransferStats : NSObject
- (instancetype)initWithTotalBytes:(uint32_t)total;
- (NSString *)statusWithBytesDone:(uint32_t)done label:(NSString *)label;
@end
@implementation MDMATransferStats {
    uint32_t    _total;
    NSDate     *_startTime;
    uint32_t    _lastDone;
    NSDate     *_lastTime;
    double      _smoothBps;  // exponential moving average
}
- (instancetype)initWithTotalBytes:(uint32_t)total {
    self = [super init];
    _total     = total;
    _startTime = [NSDate date];
    _lastTime  = _startTime;
    _lastDone  = 0;
    _smoothBps = 0;
    return self;
}
- (NSString *)statusWithBytesDone:(uint32_t)done label:(NSString *)label {
    NSDate  *now     = [NSDate date];
    double   elapsed = [now timeIntervalSinceDate:_startTime];
    double   delta_t = [now timeIntervalSinceDate:_lastTime];
    uint32_t delta_b = done - _lastDone;

    if (delta_t > 0.1) {
        double instantBps = delta_b / delta_t;
        // EMA alpha = 0.3
        _smoothBps = (_smoothBps == 0) ? instantBps : (0.3 * instantBps + 0.7 * _smoothBps);
        _lastTime  = now;
        _lastDone  = done;
    }

    double bps = _smoothBps > 0 ? _smoothBps : (elapsed > 0 ? done / elapsed : 0);
    double eta = (bps > 0 && _total > done) ? (_total - done) / bps : 0;

    NSString *bpsStr = bps >= 1024*1024
        ? [NSString stringWithFormat:@"%.1f MB/s", bps/1048576.0]
        : [NSString stringWithFormat:@"%.0f KB/s", bps/1024.0];

    NSString *etaStr = eta > 0
        ? [NSString stringWithFormat:@"ETA %ds", (int)ceil(eta)]
        : @"";

    return [NSString stringWithFormat:@"%@  |  %@  |  %.0fs elapsed  %@",
            label, bpsStr, elapsed, etaStr];
}
@end


NSString *const MDMADeviceConnectedNotification    = @"MDMADeviceConnected";
NSString *const MDMADeviceDisconnectedNotification = @"MDMADeviceDisconnected";

#define MDMA_DOMAIN @"com.megawifi.mdma"

static NSError *MDMAError(NSInteger code, NSString *msg) {
    return [NSError errorWithDomain:MDMA_DOMAIN code:code
                          userInfo:@{NSLocalizedDescriptionKey: msg}];
}

@implementation MDMAInitInfo @end
@implementation MDMAFlashRegion @end
@implementation MDMAFlashLayout @end

// ─────────────────────────────────────────────────────────────────────────────

@interface MDMADevice () {
    IONotificationPortRef  _notifyPort;
    io_iterator_t          _addedIter;
    io_iterator_t          _removedIter;
    CFRunLoopSourceRef     _runLoopSource;
    dispatch_queue_t       _usbQueue;
    BOOL                   _cancelled;
    // Incremented on every removal (main thread). Retry blocks capture this
    // value at dispatch time and bail immediately if it has changed, so no
    // retry ever outlives the removal event that should cancel it.
    NSUInteger             _connectGeneration;
}
@property (nonatomic, readwrite) BOOL connected;
@property (nonatomic, readwrite, nullable) MDMAInitInfo *deviceInfo;
@end

@implementation MDMADevice

+ (instancetype)sharedDevice {
    static MDMADevice *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MDMADevice new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _usbQueue   = dispatch_queue_create("com.megawifi.usb", DISPATCH_QUEUE_SERIAL);
    _maxRetries = 3;
    _retryDelay = 0.5;
    _connected  = NO;
    // Hold a permanent libusb reference for the app's lifetime.
    // libusb_exit(NULL) inside UsbClose/UsbCloseOnRemoval only decrements
    // the ref count — it never reaches zero, so the darwin event thread is
    // never joined (pthread_join). Without this, libusb_exit blocks for up
    // to REGULAR_TIMEOUT (7 s) waiting for the thread to wake up after each
    // device removal, freezing _usbQueue and preventing replug detection.
    libusb_init(NULL);
    return self;
}

// ── IOKit monitoring ──────────────────────────────────────────────────────────

static void deviceAdded(void *ctx, io_iterator_t iter) {
    io_service_t svc;
    BOOL any = NO;
    while ((svc = IOIteratorNext(iter))) { IOObjectRelease(svc); any = YES; }
    NSLog(@"[USB] deviceAdded fired — any=%d", any);
    MDMADevice *dev = (__bridge MDMADevice *)ctx;
    dispatch_async(dev->_usbQueue, ^{ [dev _tryConnect]; });
}

static void deviceRemoved(void *ctx, io_iterator_t iter) {
    io_service_t svc;
    BOOL anyRemoved = NO;
    while ((svc = IOIteratorNext(iter))) { IOObjectRelease(svc); anyRemoved = YES; }
    NSLog(@"[USB] deviceRemoved fired — anyRemoved=%d", anyRemoved);
    if (!anyRemoved) return;  // startup drain — no real removal

    MDMADevice *dev = (__bridge MDMADevice *)ctx;

    dev->_connectGeneration++;
    dev->_connected = NO;
    dev->_cancelled = YES;   // abort any in-flight _retryBlock so _usbQueue drains fast
    NSLog(@"[USB] removal: gen now %lu", (unsigned long)dev->_connectGeneration);

    // UsbCloseOnRemoval must run on _usbQueue (serial), which guarantees it
    // completes before any subsequent _tryConnect that is also queued there.
    dispatch_async(dev->_usbQueue, ^{ UsbCloseOnRemoval(); });

    // Post the UI notification directly to main — not through _usbQueue —
    // so it fires immediately and isn't delayed by in-progress USB operations.
    dispatch_async(dispatch_get_main_queue(), ^{
        dev.deviceInfo = nil;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MDMADeviceDisconnectedNotification object:dev];
    });
}

- (void)startMonitoring {
    _notifyPort    = IONotificationPortCreate(kIOMasterPortDefault);
    _runLoopSource = IONotificationPortGetRunLoopSource(_notifyPort);
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopDefaultMode);

    NSMutableDictionary *m1 = (NSMutableDictionary *)
        CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
    m1[@"idVendor"]  = @(MeGaWiFi_VID);
    m1[@"idProduct"] = @(MeGaWiFi_PID);
    CFRetain((__bridge CFTypeRef)m1);
    IOServiceAddMatchingNotification(_notifyPort, kIOFirstMatchNotification,
        (__bridge CFDictionaryRef)m1, deviceAdded, (__bridge void*)self, &_addedIter);
    deviceAdded((__bridge void*)self, _addedIter);

    NSMutableDictionary *m2 = (NSMutableDictionary *)
        CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
    m2[@"idVendor"]  = @(MeGaWiFi_VID);
    m2[@"idProduct"] = @(MeGaWiFi_PID);
    CFRetain((__bridge CFTypeRef)m2);
    IOServiceAddMatchingNotification(_notifyPort, kIOTerminatedNotification,
        (__bridge CFDictionaryRef)m2, deviceRemoved, (__bridge void*)self, &_removedIter);
    deviceRemoved((__bridge void*)self, _removedIter);
}

- (void)stopMonitoring {
    if (_runLoopSource)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopDefaultMode);
    if (_notifyPort)  IONotificationPortDestroy(_notifyPort);
    if (_addedIter)   IOObjectRelease(_addedIter);
    if (_removedIter) IOObjectRelease(_removedIter);
}

// ── Connection ────────────────────────────────────────────────────────────────

- (void)_tryConnect {
    if (self.connected) return;
    // Capture generation at the moment this connect attempt starts.
    // If a removal fires before we finish, generation is incremented on the
    // main thread and our next check bails — no blocking, no stale open.
    [self _tryConnectGeneration:_connectGeneration attempt:0];
}

- (void)_tryConnectGeneration:(NSUInteger)gen attempt:(int)attempt {
    NSLog(@"[USB] _tryConnectGeneration gen=%lu attempt=%d curGen=%lu connected=%d",
          (unsigned long)gen, attempt, (unsigned long)_connectGeneration, self.connected);
    if (_connectGeneration != gen) { NSLog(@"[USB] gen mismatch — aborting"); return; }
    if (self.connected) return;
    if (attempt >= 10) { NSLog(@"[USB] gave up after 10 attempts"); return; }

    int r = UsbInit();
    NSLog(@"[USB] UsbInit attempt %d → %d", attempt, r);
    if (r != 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       _usbQueue, ^{
            [self _tryConnectGeneration:gen attempt:attempt + 1];
        });
        return;
    }

    // UsbInit succeeded — clear the cancellation flag so post-connect queries run normally
    self->_cancelled = NO;

    // Give the programmer firmware 200 ms to settle after USB enumeration
    // before sending the first bulk command. Firing immediately can cause
    // FEATURES_GET to time out even though the device is physically present.
    usleep(200000);

    // Bail if a removal fired during the sleep
    if (_connectGeneration != gen) { NSLog(@"[USB] gen changed during settle delay — aborting"); return; }

    InitData id;
    memset(&id, 0, sizeof(id));
    int cartInitRet = MDMA_cart_init(&id);
    NSLog(@"[USB] MDMA_cart_init → %d (attempt %d)", cartInitRet, attempt);
    if (cartInitRet != 0) {
        UsbClose();
        // Cart may not be seated yet — retry
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       _usbQueue, ^{
            [self _tryConnectGeneration:gen attempt:attempt + 1];
        });
        return;
    }
    // Use the first key reported by the device; fall back to MegaWiFi
    MdmaCartType autoType = (id.num_drivers > 0 && id.key[0] == MDMA_CART_TYPE_GHETTO_MAPPER)
                          ? MDMA_CART_TYPE_GHETTO_MAPPER : MDMA_CART_TYPE_MEGAWIFI;
    int cartTypeRet = MDMA_cart_type_set(autoType);
    NSLog(@"[USB] MDMA_cart_type_set(%d) → %d", autoType, cartTypeRet);
    if (cartTypeRet != 0) { UsbClose(); return; }

    MDMAInitInfo *info = [MDMAInitInfo new];
    info.verMajor  = id.ver_major;
    info.verMinor  = id.ver_minor;
    info.verMicro  = id.ver_micro;
    info.numDrivers = id.num_drivers;
    NSMutableArray *keys = [NSMutableArray array];
    for (int i = 0; i < id.num_drivers; i++)
        [keys addObject:@(id.key[i])];
    info.driverKeys = keys;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.deviceInfo = info;
        self.connected  = YES;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MDMADeviceConnectedNotification object:self];
    });
}

- (void)connectWithCompletion:(nullable MDMACompletionBlock)completion {
    dispatch_async(_usbQueue, ^{
        [self _tryConnect];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(self.connected ? nil :
                MDMAError(1, @"Device not found. Connect the programmer and try again."));
        });
    });
}

- (void)disconnect {
    dispatch_async(_usbQueue, ^{ UsbClose(); });
    self.connected  = NO;
    self.deviceInfo = nil;
}

- (void)setCartType:(uint8_t)type completion:(nullable MDMACompletionBlock)completion {
    if (!self.connected) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(MDMAError(1, @"No device connected."));
        });
        return;
    }
    dispatch_async(_usbQueue, ^{
        NSError *err = nil;
        if (MDMA_cart_type_set((MdmaCartType)type) != 0)
            err = MDMAError(2, @"Failed to set cartridge type.");
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}

// ── Retry helper ──────────────────────────────────────────────────────────────

- (BOOL)_retryBlock:(BOOL(^)(void))block error:(NSError **)outErr message:(NSString*)msg {
    for (NSUInteger i = 0; i <= _maxRetries; i++) {
        if (_cancelled) {
            if (outErr) *outErr = MDMAError(-1, @"Operation cancelled.");
            return NO;
        }
        if (block()) return YES;
        if (i < _maxRetries) [NSThread sleepForTimeInterval:_retryDelay * (i+1)];
    }
    if (outErr) *outErr = MDMAError(3, msg);
    return NO;
}

// ── Flash info queries ────────────────────────────────────────────────────────

- (void)queryFlashIDsWithCompletion:(void(^)(uint8_t,uint8_t,uint8_t,uint8_t,NSError*_Nullable))completion {
    dispatch_async(_usbQueue, ^{
        uint8_t manId = 0;
        uint8_t devIds[3] = {0, 0, 0};
        NSError *err = nil;

        if (MDMA_manId_get(&manId) != 0) {
            err = MDMAError(10, @"Failed to read manufacturer ID.");
        } else {
            uint8_t cnt = 0;
            // MDMA_devId_get(dev_id_buf, num_ids_out)
            MDMA_devId_get(devIds, &cnt);
        }

        // Copy to locals so the block captures scalars, not array
        uint8_t d0 = devIds[0], d1 = devIds[1], d2 = devIds[2];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(manId, d0, d1, d2, err); });
    });
}

- (void)queryFlashLayoutWithCompletion:(void(^)(MDMAFlashLayout*_Nullable,NSError*_Nullable))completion {
    dispatch_async(_usbQueue, ^{
        struct flash_layout fl;
        memset(&fl, 0, sizeof(fl));
        NSError *err = nil;
        MDMAFlashLayout *layout = nil;

        if (MDMA_cartFlashLayout(&fl) == 0) {
            layout = [MDMAFlashLayout new];
            layout.totalLen = fl.len;
            NSMutableArray *regions = [NSMutableArray array];
            for (int i = 0; i < fl.num_regions; i++) {
                MDMAFlashRegion *r = [MDMAFlashRegion new];
                r.startAddr  = fl.region[i].start_addr;
                r.numSectors = fl.region[i].num_sectors;
                r.sectorLen  = (uint32_t)fl.region[i].sector_len * 256;
                [regions addObject:r];
            }
            layout.regions = regions;
        } else {
            err = MDMAError(11, @"Failed to read flash layout.");
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(layout, err); });
    });
}

- (BOOL)readPushbuttonState:(uint8_t *)outState {
    uint8_t st = 0;
    BOOL ok = (MDMA_button_get(&st) == 0);
    if (ok && outState) *outState = st;
    return ok;
}

// ── Flash read ────────────────────────────────────────────────────────────────

- (void)readFlashAtAddress:(uint32_t)addr length:(uint32_t)len
                  progress:(nullable MDMAProgressBlock)progress
                completion:(MDMADataCompletionBlock)completion {
    _cancelled = NO;
    dispatch_async(_usbQueue, ^{
        NSMutableData *buf = [NSMutableData dataWithLength:len];
        NSError *err = nil;
        uint32_t done = 0;
        const uint32_t chunk = 65536;
        MDMATransferStats *stats = [[MDMATransferStats alloc] initWithTotalBytes:len];

        while (done < len && !self->_cancelled) {
            uint32_t sz   = (uint32_t)MIN(chunk, len - done);
            uint32_t aOff = addr + done;
            uint8_t *dPtr = (uint8_t*)buf.mutableBytes + done;
            NSError *retryErr = nil;
            BOOL ok = [self _retryBlock:^BOOL{
                return MDMA_read(sz, (int)aOff, dPtr) == 0;
            } error:&retryErr message:[NSString stringWithFormat:@"Read failed at 0x%06X", aOff]];
            if (!ok) { err = retryErr; break; }
            done += sz;
            if (progress) {
                double f = (double)done / len;
                NSString *label = [NSString stringWithFormat:@"Reading 0x%06X", addr + done];
                NSString *s = [stats statusWithBytesDone:done label:label];
                dispatch_async(dispatch_get_main_queue(), ^{ progress(f, s); });
            }
        }
        if (self->_cancelled) err = MDMAError(-1, @"Cancelled.");
        NSData *result = err ? nil : [buf copy];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result, err); });
    });
}

// ── Flash write ───────────────────────────────────────────────────────────────

- (void)writeFlashData:(NSData *)data atAddress:(uint32_t)addr
             autoErase:(BOOL)autoErase verify:(BOOL)verify
              progress:(nullable MDMAProgressBlock)progress
            completion:(MDMACompletionBlock)completion {
    _cancelled = NO;
    dispatch_async(_usbQueue, ^{
        NSError *err = nil;
        uint32_t len = (uint32_t)data.length;
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        double totalSteps = (autoErase ? 1.0 : 0.0) + 1.0 + (verify ? 1.0 : 0.0);
        double stepsDone  = 0;

        // --- Erase ---
        if (autoErase && !self->_cancelled) {
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(0.0, @"Erasing…"); });
            NSError *re = nil;
            BOOL ok = [self _retryBlock:^BOOL{
                return MDMA_range_erase(addr, len) == 0;
            } error:&re message:@"Erase failed."];
            if (!ok) { err = re; goto finish; }
            stepsDone++;
        }

        // --- Write in chunks ---
        if (!self->_cancelled) {
            uint32_t done = 0;
            const uint32_t chunk = 65536;
            MDMATransferStats *wStats = [[MDMATransferStats alloc] initWithTotalBytes:len];
            while (done < len && !self->_cancelled) {
                uint32_t sz   = (uint32_t)MIN(chunk, len - done);
                uint32_t aOff = addr + done;
                const uint8_t *dPtr = bytes + done;
                NSError *re = nil;
                BOOL ok = [self _retryBlock:^BOOL{
                    return MDMA_write(sz, (int)aOff, dPtr) == 0;
                } error:&re message:[NSString stringWithFormat:@"Write failed at 0x%06X", aOff]];
                if (!ok) { err = re; goto finish; }
                done += sz;
                if (progress) {
                    double f = (stepsDone + (double)done/len) / totalSteps;
                    NSString *label = [NSString stringWithFormat:@"Writing 0x%06X", addr+done];
                    NSString *s = [wStats statusWithBytesDone:done label:label];
                    dispatch_async(dispatch_get_main_queue(), ^{ progress(f, s); });
                }
            }
            stepsDone++;
        }

        // --- Verify ---
        if (verify && !self->_cancelled) {
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{
                progress(stepsDone/totalSteps, @"Verifying…"); });
            NSMutableData *vbuf = [NSMutableData dataWithLength:len];
            uint32_t done = 0;
            const uint32_t chunk = 65536;
            while (done < len && !self->_cancelled) {
                uint32_t sz   = (uint32_t)MIN(chunk, len - done);
                uint32_t aOff = addr + done;
                uint8_t *vPtr = (uint8_t*)vbuf.mutableBytes + done;
                NSError *re = nil;
                BOOL ok = [self _retryBlock:^BOOL{
                    return MDMA_read(sz, (int)aOff, vPtr) == 0;
                } error:&re message:@"Verify read failed."];
                if (!ok) { err = re; goto finish; }
                done += sz;
                if (progress) {
                    double f = (stepsDone + (double)done/len) / totalSteps;
                    dispatch_async(dispatch_get_main_queue(), ^{ progress(f, @"Verifying…"); });
                }
            }
            if (!err && memcmp(vbuf.bytes, bytes, len) != 0)
                err = MDMAError(20, @"Verify failed: data mismatch.");
        }

    finish:
        if (self->_cancelled) err = MDMAError(-1, @"Cancelled.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}

// ── Erase ─────────────────────────────────────────────────────────────────────

- (void)eraseFullChipWithProgress:(nullable MDMAProgressBlock)progress
                       completion:(MDMACompletionBlock)completion {
    _cancelled = NO;
    if (progress) progress(0.0, @"Erasing full chip — may take up to 2 minutes…");
    dispatch_async(_usbQueue, ^{
        NSError *err = nil;
        if (MDMA_cart_erase() != 0) err = MDMAError(30, @"Full chip erase failed.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}

- (void)eraseRangeAtAddress:(uint32_t)addr length:(uint32_t)len
                   progress:(nullable MDMAProgressBlock)progress
                 completion:(MDMACompletionBlock)completion {
    _cancelled = NO;
    dispatch_async(_usbQueue, ^{
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{
            progress(0.0, [NSString stringWithFormat:@"Erasing 0x%06X – 0x%06X…", addr, addr+len]); });
        NSError *err = nil;
        NSError *re  = nil;
        BOOL ok = [self _retryBlock:^BOOL{
            return MDMA_range_erase(addr, len) == 0;
        } error:&re message:@"Range erase failed."];
        if (!ok) err = re;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}


// ── Bootloader ────────────────────────────────────────────────────────────────

- (void)enterBootloaderWithCompletion:(nullable MDMACompletionBlock)completion {
    if (!self.connected) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(MDMAError(1, @"No device connected."));
        });
        return;
    }
    dispatch_async(_usbQueue, ^{
        MDMA_bootloader();  // device disconnects — no reply expected
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connected = NO;
            if (completion) completion(nil);
        });
    });
}

// ── WiFi ROM transfer (TCP, wflash protocol) ───────────────────────────────────
//
// Genesis wflash ROM acts as a TCP server on port 1985.
// Wire format: [cmd:u16 LE][len:u16 LE][data...]
// Genesis does ByteSwapWord on cmd/len/addr/memlen — i.e. values go on wire as LE.
// WF_CMD_OK = 0 (success reply cmd)

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

#define WF_CMD_VERSION_GET_  0
#define WF_CMD_ERASE_        3
#define WF_CMD_PROGRAM_      4
#define WF_CMD_AUTORUN_      7
#define WF_CMD_BLOADER_START_ 8
#define WF_CMD_OK_           0
#define WF_HEADLEN_          4
#define WF_MAX_CHUNK_        (45 * 1440)  // 64800 bytes per program cmd

#pragma pack(push, 1)
typedef struct { uint16_t cmd; uint16_t len;               } WfHdr_;
typedef struct { uint16_t cmd; uint16_t len; uint32_t addr; uint32_t size; } WfMemCmd_;
#pragma pack(pop)

static BOOL wfSendFull(int sock, const void *buf, size_t len) {
    const uint8_t *p = (const uint8_t *)buf;
    while (len > 0) {
        ssize_t n = write(sock, p, len);
        if (n <= 0) return NO;
        p += n; len -= (size_t)n;
    }
    return YES;
}
static BOOL wfRecvFull(int sock, void *buf, size_t len) {
    uint8_t *p = (uint8_t *)buf;
    while (len > 0) {
        ssize_t n = read(sock, p, len);
        if (n <= 0) return NO;
        p += n; len -= (size_t)n;
    }
    return YES;
}

// Establishes a TCP connection to the Genesis wflash ROM and verifies with VERSION_GET.
// Returns the open socket fd (>= 0) on success — CALLER must close() it when done.
- (void)connectToWflashHost:(NSString *)host
                       port:(uint16_t)port
                 completion:(void(^)(int sock, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct addrinfo hints, *res = NULL;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family   = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        char portStr[8];
        snprintf(portStr, sizeof(portStr), "%u", port);
        if (getaddrinfo(host.UTF8String, portStr, &hints, &res) != 0 || !res) {
            NSError *e = MDMAError(60, [NSString stringWithFormat:@"Cannot resolve host: %@", host]);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(-1, e); });
            return;
        }

        int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock < 0) {
            freeaddrinfo(res);
            NSError *e = MDMAError(61, @"Socket creation failed.");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(-1, e); });
            return;
        }
        struct timeval tv = {10, 0};
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
            freeaddrinfo(res); close(sock);
            NSError *e = MDMAError(62, [NSString stringWithFormat:@"Cannot connect to %@:%u — is the Genesis in download mode?", host, port]);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(-1, e); });
            return;
        }
        freeaddrinfo(res);

        // Give the Genesis ~300ms to finish processing the TCP connection-established
        // event on channel 0 and post mw_recv on channel 1 before we send any command.
        // (The Qt client has an equivalent delay due to the user dismissing dialogs.)
        usleep(300000);

        // Socket is left OPEN — caller must close() it
        NSLog(@"wflash: TCP connected, socket %d open", sock);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(sock, nil); });
    });
}

// Writes ROM data over an already-connected wflash socket.
// Protocol:
//   1. Query BLOADER_START to get the wflash bootloader address
//   2. Patch the ROM header: save original entry point to notes[0x1C8],
//      replace it with the bootloader address so wflash still runs after reboot
//   3. ERASE → PROGRAM chunks → AUTORUN, then close the socket.
//
// The ROM header patch mirrors what the Qt wf-cli client does in RomHeadPatch().
// Without it, flashing a game ROM at 0x000000 overwrites the reset vector so
// the cartridge boots the game directly on power-cycle, destroying the wflash menu.
- (void)writeFlashOnSocket:(int)sock
                      data:(NSData *)data
                 atAddress:(uint32_t)addr
                  progress:(nullable MDMAProgressBlock)progress
                completion:(MDMACompletionBlock)completion {
    _cancelled = NO;
    dispatch_async(_usbQueue, ^{
        NSError *err = nil;
        NSData  *writeData = data;   // may be replaced with patched copy below

        // ── 1. Query bootloader start address ──────────────────────────────
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{
            progress(0.01, @"Querying bootloader address…");
        });
        WfHdr_ blCmd = {WF_CMD_BLOADER_START_, 0};
        uint8_t blReply[8];  // WF_HEADLEN(4) + 4 bytes addr
        if (!wfSendFull(sock, &blCmd, WF_HEADLEN_) ||
            !wfRecvFull(sock, blReply, sizeof(blReply))) {
            err = MDMAError(64, @"Failed to get bootloader address from Genesis.");
            goto wf_write_done;
        }
        WfHdr_ *blHdr = (WfHdr_ *)blReply;
        if (blHdr->cmd != WF_CMD_OK_) {
            err = MDMAError(64, @"Genesis returned error for BLOADER_START.");
            goto wf_write_done;
        }
        // The Genesis sends ByteSwapDWord(bootloaderAddr); we read it as LE on macOS
        // which gives back the correct value due to symmetric byte-swapping.
        uint32_t bootloaderAddr;
        memcpy(&bootloaderAddr, blReply + WF_HEADLEN_, 4);
        NSLog(@"wflash: bootloader address = 0x%06X", bootloaderAddr);

        // ── 2. ROM size check ───────────────────────────────────────────────
        if (addr == 0 && (uint32_t)data.length > bootloaderAddr) {
            err = MDMAError(68, [NSString stringWithFormat:
                @"ROM is too large (%.1f MB) — would overwrite the wflash bootloader "
                @"at 0x%06X. ROM must be under %.1f MB.",
                (double)data.length / (1024*1024), bootloaderAddr,
                (double)bootloaderAddr / (1024*1024)]);
            goto wf_write_done;
        }

        // ── 3. Patch ROM header (addr==0 only, needs at least 0x1CC bytes) ─
        // Save original entry point (ROM bytes 4-7, big-endian) to the NOTES
        // field at offset 0x1C8. Then replace bytes 4-7 with the bootloader
        // address so the cartridge still boots wflash on power-cycle.
        // wflash AUTORUN reads back the original entry from 0x1C8 to run the game.
        if (addr == 0 && data.length >= 0x1CC) {
            NSMutableData *patched = [data mutableCopy];
            uint8_t *rom = (uint8_t *)patched.mutableBytes;

            // Copy original entry point bytes (big-endian, 4 bytes) to notes
            rom[0x1C8] = rom[4];
            rom[0x1C9] = rom[5];
            rom[0x1CA] = rom[6];
            rom[0x1CB] = rom[7];

            // Overwrite entry point with bootloader address (big-endian)
            rom[4] = (bootloaderAddr >> 24) & 0xFF;
            rom[5] = (bootloaderAddr >> 16) & 0xFF;
            rom[6] = (bootloaderAddr >>  8) & 0xFF;
            rom[7] = (bootloaderAddr      ) & 0xFF;

            NSLog(@"wflash: patched entry point 0x%02X%02X%02X%02X → 0x%06X",
                  rom[0x1C8], rom[0x1C9], rom[0x1CA], rom[0x1CB], bootloaderAddr);
            writeData = [patched copy];
        }

        // ── 4. ERASE ────────────────────────────────────────────────────────
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{
            progress(0.02, @"Erasing…");
        });
        WfMemCmd_ eraseCmd = {WF_CMD_ERASE_, 8, addr, (uint32_t)writeData.length};
        WfHdr_ eraseReply;
        if (!wfSendFull(sock, &eraseCmd, sizeof(eraseCmd)) ||
            !wfRecvFull(sock, &eraseReply, WF_HEADLEN_) ||
            eraseReply.cmd != WF_CMD_OK_) {
            err = MDMAError(65, @"WiFi erase failed.");
            goto wf_write_done;
        }
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{
            progress(0.05, @"Erase done — programming…");
        });

        // ── 5. PROGRAM in chunks ─────────────────────────────────────────────
        {
            uint32_t total = (uint32_t)writeData.length;
            uint32_t done  = 0;
            const uint8_t *bytes = (const uint8_t *)writeData.bytes;
            MDMATransferStats *stats = [[MDMATransferStats alloc] initWithTotalBytes:total];

            while (done < total && !self->_cancelled) {
                uint32_t chunkSize = (uint32_t)MIN((uint32_t)WF_MAX_CHUNK_, total - done);
                uint32_t chunkAddr = addr + done;

                WfMemCmd_ progCmd = {WF_CMD_PROGRAM_, 8, chunkAddr, chunkSize};
                WfHdr_    progReply;
                if (!wfSendFull(sock, &progCmd, sizeof(progCmd)) ||
                    !wfRecvFull(sock, &progReply, WF_HEADLEN_) ||
                    progReply.cmd != WF_CMD_OK_) {
                    err = MDMAError(66, [NSString stringWithFormat:
                                        @"Program failed at 0x%06X", chunkAddr]);
                    goto wf_write_done;
                }
                if (!wfSendFull(sock, bytes + done, chunkSize)) {
                    err = MDMAError(67, @"Data send failed.");
                    goto wf_write_done;
                }
                done += chunkSize;
                if (progress) {
                    double f = 0.05 + 0.90 * ((double)done / total);
                    NSString *lbl = [NSString stringWithFormat:@"WiFi writing 0x%06X", chunkAddr];
                    NSString *s   = [stats statusWithBytesDone:done label:lbl];
                    dispatch_async(dispatch_get_main_queue(), ^{ progress(f, s); });
                }
            }
            if (self->_cancelled) err = MDMAError(-1, @"Cancelled.");
        }

        // ── 6. AUTORUN — Genesis boots and closes connection ─────────────────
        if (!err) {
            WfHdr_ autorun = {WF_CMD_AUTORUN_, 0};
            WfHdr_ arReply;
            wfSendFull(sock, &autorun, WF_HEADLEN_);
            wfRecvFull(sock, &arReply, WF_HEADLEN_);
        }

    wf_write_done:
        close(sock);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}

// ── Cancel ────────────────────────────────────────────────────────────────────

- (void)cancelCurrentOperation {
    _cancelled = YES;
}

@end
