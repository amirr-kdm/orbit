// Reads macOS "Now Playing" (every app: Telegram, Chrome, YouTube...) and prints one JSON line per change.
// Since macOS 15.4 only Apple-signed programs may ask for it, so this library is loaded into /usr/bin/perl
// (see Notchbit's NowPlayingBridge). Commands come in on stdin: play, pause, toggle, next, prev.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientBundleFn)(id);
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, id);

static GetClientFn getClient; static ClientBundleFn clientBundle;
static GetInfoFn getInfo; static GetPlayingFn getPlaying; static SendCommandFn sendCommand;
static dispatch_queue_t queue;
static NSString *lastLine = @"";

static NSString *str(NSDictionary *d, NSString *key) { id v = d[key]; return [v isKindOfClass:NSString.class] ? v : @""; }

static void report(void) {
    getInfo(queue, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = (__bridge NSDictionary *)cfInfo ?: @{};
        getPlaying(queue, ^(Boolean playing) {
          void (^emit)(NSString *) = ^(NSString *app) {
            NSMutableDictionary *o = [NSMutableDictionary dictionary];
            o[@"app"] = app ?: @"";
            o[@"title"] = str(info, @"kMRMediaRemoteNowPlayingInfoTitle");
            o[@"artist"] = str(info, @"kMRMediaRemoteNowPlayingInfoArtist");
            o[@"album"] = str(info, @"kMRMediaRemoteNowPlayingInfoAlbum");
            o[@"playing"] = @(playing);
            NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if ([art isKindOfClass:NSData.class] && art.length > 0 && art.length < 600000) o[@"artwork"] = [art base64EncodedStringWithOptions:0];
            NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
            NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            if ([line isEqualToString:lastLine]) return;
            lastLine = line;
            fprintf(stdout, "%s\n", line.UTF8String); fflush(stdout);
          };
          if (getClient && clientBundle) {
              getClient(queue, ^(id client) {
                  NSString *bid = client ? (__bridge NSString *)clientBundle(client) : nil;
                  emit(bid);
              });
          } else emit(nil);
        });
    });
}

// the entry point perl calls (it passes two pointers we do not need)
void nowplaying_boot(void *interp, void *cv) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!h) { fprintf(stderr, "no MediaRemote\n"); exit(2); }
        getInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        getPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        sendCommand = dlsym(h, "MRMediaRemoteSendCommand");
        getClient = dlsym(h, "MRMediaRemoteGetNowPlayingClient");
        clientBundle = dlsym(h, "MRNowPlayingClientGetBundleIdentifier");
        RegisterFn reg = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (!getInfo || !getPlaying || !reg) { fprintf(stderr, "missing symbols\n"); exit(3); }
        queue = dispatch_queue_create("orbit.nowplaying", DISPATCH_QUEUE_SERIAL);
        reg(queue);
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
            [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *x) { report(); }];
        }
        report();
        // commands from Orbit
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[64];
            while (fgets(buf, sizeof buf, stdin)) {
                NSString *c = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                int code = -1;
                if ([c isEqualToString:@"play"]) code = 0; else if ([c isEqualToString:@"pause"]) code = 1;
                else if ([c isEqualToString:@"toggle"]) code = 2; else if ([c isEqualToString:@"next"]) code = 4; else if ([c isEqualToString:@"prev"]) code = 5;
                if (code >= 0 && sendCommand) sendCommand(code, nil);
            }
            exit(0); // Orbit closed the pipe: stop
        });
        // keep the run loop alive (it would return at once with nothing scheduled)
        [NSTimer scheduledTimerWithTimeInterval:3600 repeats:YES block:^(NSTimer *t) {}];
        [[NSRunLoop currentRunLoop] run];
    }
}
