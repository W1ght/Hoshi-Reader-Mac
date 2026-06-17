#import <AppKit/AppKit.h>
#import "HSMpvClient.h"
#include <string.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 4) {
            return 2;
        }
        BOOL expectsAudioOnly = argc == 3 && strcmp(argv[2], "audio-only") == 0;
        BOOL expectsSubtitleCues = argc >= 3 && !expectsAudioOnly;
        BOOL expectsExternalSubtitles = argc == 4
            && strcmp(argv[2], "external-subtitles") == 0;
        NSURL *externalSubtitleURL = expectsExternalSubtitles
            ? [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]]
            : nil;
        if ((argc == 3 && !expectsAudioOnly && strcmp(argv[2], "expect-subtitles") != 0)
            || (argc == 4 && !expectsExternalSubtitles)) {
            return 2;
        }
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 180)
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        HSMpvOpenGLView *view = [[HSMpvOpenGLView alloc] initWithFrame:window.contentView.bounds];
        window.contentView = view;
        [window orderFront:nil];
        [view displayIfNeeded];

        NSError *error = nil;
        HSMpvClient *client = [[HSMpvClient alloc] initWithError:&error];
        if (!client || ![client attachToView:view]) {
            NSLog(@"client setup failed: %@", error);
            return 1;
        }

        __block BOOL loaded = NO;
        __block BOOL receivedTracks = NO;
        __block BOOL selectedSubtitleTrack = NO;
        __block BOOL loadedExternalSubtitles = NO;
        __block BOOL receivedSubtitleCues = NO;
        __weak HSMpvClient *weakClient = client;
        client.stateHandler = ^(
            double currentTime,
            double duration,
            BOOL playing,
            BOOL isLoaded,
            double speed,
            double volume,
            BOOL muted,
            double subtitleDelay,
            double audioDelay,
            NSString *loopMode,
            double abLoopStart,
            double abLoopEnd,
            NSString *aspectRatio,
            NSInteger rotation,
            NSString *message
        ) {
            if (message) {
                NSLog(@"client error: %@", message);
            }
            if (isLoaded && duration > 0) {
                loaded = YES;
                if (externalSubtitleURL && !loadedExternalSubtitles) {
                    loadedExternalSubtitles = YES;
                    [weakClient loadExternalSubtitle:externalSubtitleURL];
                }
            }
        };
        client.trackHandler = ^(NSArray<HSMpvTrackInfo *> *tracks) {
            receivedTracks = tracks.count > 0;
            if (expectsSubtitleCues && !expectsExternalSubtitles && !selectedSubtitleTrack) {
                for (HSMpvTrackInfo *track in tracks) {
                    if ([track.type isEqualToString:@"sub"]) {
                        selectedSubtitleTrack = YES;
                        [weakClient selectTrackType:@"subtitle"
                                           trackID:@(track.trackID)];
                        break;
                    }
                }
            }
        };
        client.subtitleCueHandler = ^(NSArray<HSMpvSubtitleCueInfo *> *cues) {
            if (cues.count > 0 && cues.firstObject.text.length > 0) {
                receivedSubtitleCues = YES;
            }
        };
        [client setPaused:!expectsSubtitleCues];
        [client setSpeed:1.25];
        [client setVolume:75];
        [client setMuted:NO];
        [client setSubtitleDelay:0.5];
        [client setAudioDelay:0.25];
        [client setLoopMode:@"none"];
        [client setABLoopStart:@0.1 end:@0.8];
        [client setABLoopStart:nil end:nil];
        [client setAspectRatio:@"16:9"];
        [client setRotation:90];
        [client setRotation:0];
        [client loadFile:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while ((!loaded || (expectsSubtitleCues && !receivedSubtitleCues))
               && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NSString *screenshotPath = @"/tmp/hoshi-video-client-screenshot.png";
        [[NSFileManager defaultManager] removeItemAtPath:screenshotPath error:nil];
        NSString *screenshotError = nil;
        BOOL captured = expectsAudioOnly
            ? YES
            : [client captureScreenshotToURL:
                [NSURL fileURLWithPath:screenshotPath]
                errorMessage:&screenshotError
            ];
        [client shutdown];
        [window orderOut:nil];
        BOOL screenshotExists = expectsAudioOnly
            || [[NSFileManager defaultManager] fileExistsAtPath:screenshotPath];
        if (!loaded || !receivedTracks || !captured || !screenshotExists
            || (expectsSubtitleCues && !receivedSubtitleCues)) {
            if (screenshotError) {
                NSLog(@"screenshot failed: %@", screenshotError);
            }
            fputs("HSMpvClient media test timed out\n", stderr);
            return 1;
        }
        puts("HSMpvClient media test passed");
    }
    return 0;
}
