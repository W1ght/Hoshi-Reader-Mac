#if HOSHI_VIDEO
#import "HSMpvClient.h"

#include <atomic>
#include <cstdint>
#include <dlfcn.h>
#include <math.h>
#define GL_SILENCE_DEPRECATION
#import <OpenGL/gl.h>
#import <mpv/client.h>
#import <mpv/render_gl.h>

static NSString * const HSMpvErrorDomain = @"moe.shishamo.hoshi.video.mpv";
static NSImage *HSMpvAmbientImageFromNode(mpv_node *node, NSInteger maximumDimension);

typedef struct { int num; int den; } HSAVRational;
typedef struct HSAVClass HSAVClass;
typedef struct HSAVInputFormat HSAVInputFormat;
typedef struct HSAVOutputFormat HSAVOutputFormat;
typedef struct HSAVIOContext HSAVIOContext;
typedef struct HSAVBufferRef HSAVBufferRef;
typedef struct HSAVPacketSideData HSAVPacketSideData;
typedef struct HSAVCodecParameters HSAVCodecParameters;
typedef struct HSAVStream {
    const HSAVClass *avClass;
    int index;
    int streamID;
    HSAVCodecParameters *codecParameters;
    void *privateData;
    HSAVRational timeBase;
} HSAVStream;
typedef struct HSAVFormatContext {
    const HSAVClass *avClass;
    const HSAVInputFormat *inputFormat;
    const HSAVOutputFormat *outputFormat;
    void *privateData;
    HSAVIOContext *ioContext;
    int contextFlags;
    unsigned int streamCount;
    HSAVStream **streams;
} HSAVFormatContext;
typedef struct HSAVPacket {
    HSAVBufferRef *buffer;
    int64_t presentationTimestamp;
    int64_t decodingTimestamp;
    uint8_t *data;
    int size;
    int streamIndex;
    int flags;
    HSAVPacketSideData *sideData;
    int sideDataCount;
    int64_t duration;
    int64_t position;
    void *opaque;
    HSAVBufferRef *opaqueReference;
    HSAVRational timeBase;
} HSAVPacket;

@implementation HSMpvTrackInfo
@end

@implementation HSExtractedSubtitleCue
@end

@implementation HSMpvAudioClipExporter

+ (BOOL)exportAudioFromURL:(NSURL *)sourceURL
    toURL:(NSURL *)outputURL
    startTime:(double)startTime
    endTime:(double)endTime
    audioTrackID:(nullable NSNumber *)audioTrackID
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (endTime <= startTime) {
        if (errorMessage) *errorMessage = @"Unable to determine the video audio range.";
        return NO;
    }

    mpv_handle *encoder = mpv_create();
    if (!encoder) {
        if (errorMessage) *errorMessage = @"The bundled audio encoder is unavailable.";
        return NO;
    }

    NSString *start = [NSString stringWithFormat:@"%.6f", MAX(0, startTime)];
    NSString *end = [NSString stringWithFormat:@"%.6f", endTime];
    NSString *track = audioTrackID ? audioTrackID.stringValue : @"auto";
    NSArray<NSArray<NSString *> *> *options = @[
        @[@"config", @"no"], @[@"vid", @"no"], @[@"sid", @"no"],
        @[@"aid", track], @[@"audio-channels", @"mono"],
        @[@"start", start], @[@"end", end], @[@"o", outputURL.path],
        @[@"oac", @"aac"], @[@"of", @"mp4"], @[@"oacopts", @"b=64k"]
    ];
    for (NSArray<NSString *> *option in options) {
        int optionStatus = mpv_set_option_string(
            encoder, option[0].UTF8String, option[1].UTF8String
        );
        if (optionStatus < 0) {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"The bundled audio encoder rejected %@: %s",
                    option[0], mpv_error_string(optionStatus)];
            }
            mpv_terminate_destroy(encoder);
            return NO;
        }
    }

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    int status = mpv_initialize(encoder);
    if (status < 0) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"The bundled audio encoder could not start: %s",
                mpv_error_string(status)];
        }
        mpv_terminate_destroy(encoder);
        return NO;
    }

    const char *command[] = {"loadfile", sourceURL.fileSystemRepresentation, NULL};
    status = mpv_command(encoder, command);
    if (status < 0) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"The video audio could not be opened: %s",
                mpv_error_string(status)];
        }
        mpv_terminate_destroy(encoder);
        return NO;
    }

    BOOL completed = NO;
    NSString *failure = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    while (!completed && deadline.timeIntervalSinceNow > 0) {
        mpv_event *event = mpv_wait_event(encoder, 0.25);
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *endFile = (mpv_event_end_file *)event->data;
            if (endFile && endFile->error < 0) {
                failure = [NSString stringWithFormat:@"The video audio export failed: %s",
                    mpv_error_string(endFile->error)];
            }
            completed = YES;
        } else if (event->event_id == MPV_EVENT_SHUTDOWN) {
            failure = @"The bundled audio encoder stopped unexpectedly.";
            completed = YES;
        }
    }
    if (!completed) failure = @"The video audio export timed out.";
    mpv_terminate_destroy(encoder);

    NSNumber *fileSize = nil;
    [outputURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    if (failure || fileSize.longLongValue <= 0) {
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        if (errorMessage) *errorMessage = failure ?: @"The exported video audio clip is empty.";
        return NO;
    }
    return YES;
}

@end

static BOOL HSMpvSetThumbnailOption(
    mpv_handle *handle,
    NSString *name,
    NSString *value,
    NSString **errorMessage
) {
    int status = mpv_set_option_string(handle, name.UTF8String, value.UTF8String);
    if (status < 0) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"The bundled video thumbnailer rejected %@: %s",
                name, mpv_error_string(status)];
        }
        return NO;
    }
    return YES;
}

static BOOL HSMpvThumbnailIsCancelled(HSMpvCancellationHandler isCancelled) {
    return isCancelled ? isCancelled() : NO;
}

static NSData *HSMpvPNGDataFromImage(NSImage *image) {
    NSData *tiffData = image.TIFFRepresentation;
    if (!tiffData) {
        return nil;
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static NSData *HSMpvPNGDataByLimitingMaximumDimension(
    NSData *pngData,
    NSInteger maximumDimension
) {
    if (maximumDimension <= 0) {
        return pngData;
    }
    NSImageRep *imageRep = [NSBitmapImageRep imageRepWithData:pngData];
    if (![imageRep isKindOfClass:NSBitmapImageRep.class]) {
        return pngData;
    }
    NSBitmapImageRep *bitmap = (NSBitmapImageRep *)imageRep;
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    NSInteger longestSide = MAX(width, height);
    if (width <= 0 || height <= 0 || longestSide <= maximumDimension) {
        return pngData;
    }

    CGFloat scale = (CGFloat)maximumDimension / (CGFloat)longestSide;
    NSInteger outputWidth = MAX(1, (NSInteger)floor((CGFloat)width * scale));
    NSInteger outputHeight = MAX(1, (NSInteger)floor((CGFloat)height * scale));
    NSImage *source = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [source addRepresentation:bitmap];
    NSImage *scaled = [[NSImage alloc] initWithSize:NSMakeSize(outputWidth, outputHeight)];
    [scaled lockFocus];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    [source drawInRect:NSMakeRect(0, 0, outputWidth, outputHeight)
        fromRect:NSZeroRect
        operation:NSCompositingOperationCopy
        fraction:1.0];
    [scaled unlockFocus];
    return HSMpvPNGDataFromImage(scaled) ?: pngData;
}

static NSURL *HSMpvCreateThumbnailOutputDirectory(NSString **errorMessage) {
    NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory()]
        .URLByStandardizingPath;
    directory = [directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"hoshi-video-thumbnail-%@", NSUUID.UUID.UUIDString]
        isDirectory:YES];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
        withIntermediateDirectories:YES
        attributes:nil
        error:&error]) {
        if (errorMessage) {
            *errorMessage = error.localizedDescription;
        }
        return nil;
    }
    return directory;
}

static NSData *HSMpvFirstPNGDataInDirectory(NSURL *directory) {
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:nil];
    NSArray<NSURL *> *pngFiles = [contents filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
            (void)bindings;
            return [url.pathExtension caseInsensitiveCompare:@"png"] == NSOrderedSame;
        }]
    ];
    NSURL *first = [pngFiles sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
    }].firstObject;
    return first ? [NSData dataWithContentsOfURL:first] : nil;
}

static NSData *HSMpvRenderThumbnailPNGData(
    NSURL *url,
    NSInteger maximumDimension,
    double time,
    HSMpvCancellationHandler isCancelled,
    NSString **errorMessage
) {
    NSString *failure = nil;
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    NSURL *outputDirectory = HSMpvCreateThumbnailOutputDirectory(&failure);
    if (!outputDirectory) {
        if (errorMessage) {
            *errorMessage = failure ?: @"The video thumbnail output directory could not be created.";
        }
        return nil;
    }
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    mpv_handle *thumbnailer = mpv_create();
    if (!thumbnailer) {
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The bundled video thumbnailer is unavailable.";
        }
        return nil;
    }
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    NSString *startTime = [NSString stringWithFormat:@"%.6f", MAX(0, time)];
    NSArray<NSArray<NSString *> *> *options = @[
        @[@"config", @"no"],
        @[@"osc", @"no"],
        @[@"input-default-bindings", @"no"],
        @[@"input-cursor", @"no"],
        @[@"sid", @"no"],
        @[@"audio", @"no"],
        @[@"vo", @"image"],
        @[@"vo-image-format", @"png"],
        @[@"vo-image-outdir", outputDirectory.path],
        @[@"frames", @"1"],
        @[@"start", startTime]
    ];
    for (NSArray<NSString *> *option in options) {
        if (HSMpvThumbnailIsCancelled(isCancelled)) {
            mpv_terminate_destroy(thumbnailer);
            [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
            if (errorMessage) {
                *errorMessage = @"The video thumbnail was cancelled.";
            }
            return nil;
        }
        if (!HSMpvSetThumbnailOption(thumbnailer, option[0], option[1], &failure)) {
            mpv_terminate_destroy(thumbnailer);
            [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
            if (errorMessage) {
                *errorMessage = failure;
            }
            return nil;
        }
    }
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    int status = mpv_initialize(thumbnailer);
    if (status < 0) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"The bundled video thumbnailer could not start: %s",
                mpv_error_string(status)];
        }
        return nil;
    }
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    const char *loadCommand[] = {"loadfile", url.fileSystemRepresentation, "replace", NULL};
    status = mpv_command(thumbnailer, loadCommand);
    if (status < 0) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"The video thumbnail could not be opened: %s",
                mpv_error_string(status)];
        }
        return nil;
    }
    if (HSMpvThumbnailIsCancelled(isCancelled)) {
        mpv_terminate_destroy(thumbnailer);
        [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
        if (errorMessage) {
            *errorMessage = @"The video thumbnail was cancelled.";
        }
        return nil;
    }

    BOOL completed = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!completed && deadline.timeIntervalSinceNow > 0) {
        if (HSMpvThumbnailIsCancelled(isCancelled)) {
            failure = @"The video thumbnail was cancelled.";
            completed = YES;
            break;
        }
        mpv_event *event = mpv_wait_event(thumbnailer, 0.1);
        if (!event || event->event_id == MPV_EVENT_NONE) {
            continue;
        }
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *endFile = (mpv_event_end_file *)event->data;
            if (endFile && endFile->error < 0) {
                failure = [NSString stringWithFormat:@"The video thumbnail could not be rendered: %s",
                    mpv_error_string(endFile->error)];
            }
            completed = YES;
        } else if (event->event_id == MPV_EVENT_SHUTDOWN) {
            failure = @"The bundled video thumbnailer stopped unexpectedly.";
            completed = YES;
        }
    }
    if (!completed) {
        failure = @"The video thumbnail timed out while rendering.";
    }

    mpv_terminate_destroy(thumbnailer);
    BOOL cancelled = HSMpvThumbnailIsCancelled(isCancelled)
        || [failure isEqualToString:@"The video thumbnail was cancelled."];
    NSData *pngData = (failure || cancelled) ? nil : HSMpvFirstPNGDataInDirectory(outputDirectory);
    [[NSFileManager defaultManager] removeItemAtURL:outputDirectory error:nil];
    if (pngData) {
        return HSMpvPNGDataByLimitingMaximumDimension(pngData, maximumDimension);
    }
    if (errorMessage) {
        *errorMessage = failure ?: @"The video thumbnail frame could not be encoded.";
    }
    return nil;
}

@implementation HSMpvThumbnailGenerator

+ (nullable NSData *)thumbnailPNGDataForURL:(NSURL *)url
    maximumDimension:(NSInteger)maximumDimension
    time:(double)time
    isCancelled:(HSMpvCancellationHandler)isCancelled
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    double requestedTime = MAX(0, time);
    NSString *lastError = nil;
    NSData *data = HSMpvRenderThumbnailPNGData(
        url,
        maximumDimension,
        requestedTime,
        isCancelled,
        &lastError
    );
    if (!data && requestedTime > 0 && !HSMpvThumbnailIsCancelled(isCancelled)) {
        data = HSMpvRenderThumbnailPNGData(
            url,
            maximumDimension,
            0,
            isCancelled,
            &lastError
        );
    }
    if (!data && errorMessage) {
        *errorMessage = lastError;
    }
    return data;
}

@end

@implementation HSSubtitleTrackExtractor

+ (nullable NSArray<HSExtractedSubtitleCue *> *)extractTextSubtitleFromURL:(NSURL *)url
    streamIndex:(NSInteger)streamIndex
    error:(NSError * _Nullable * _Nullable)error {
    typedef int (*OpenInputFunction)(HSAVFormatContext **, const char *, const void *, void *);
    typedef int (*FindStreamInfoFunction)(HSAVFormatContext *, void *);
    typedef HSAVPacket *(*PacketAllocFunction)(void);
    typedef void (*PacketFreeFunction)(HSAVPacket **);
    typedef void (*PacketUnrefFunction)(HSAVPacket *);
    typedef int (*ReadFrameFunction)(HSAVFormatContext *, HSAVPacket *);
    typedef void (*CloseInputFunction)(HSAVFormatContext **);

    OpenInputFunction openInput = (OpenInputFunction)dlsym(RTLD_DEFAULT, "avformat_open_input");
    FindStreamInfoFunction findStreamInfo = (FindStreamInfoFunction)dlsym(RTLD_DEFAULT, "avformat_find_stream_info");
    PacketAllocFunction packetAlloc = (PacketAllocFunction)dlsym(RTLD_DEFAULT, "av_packet_alloc");
    PacketFreeFunction packetFree = (PacketFreeFunction)dlsym(RTLD_DEFAULT, "av_packet_free");
    PacketUnrefFunction packetUnref = (PacketUnrefFunction)dlsym(RTLD_DEFAULT, "av_packet_unref");
    ReadFrameFunction readFrame = (ReadFrameFunction)dlsym(RTLD_DEFAULT, "av_read_frame");
    CloseInputFunction closeInput = (CloseInputFunction)dlsym(RTLD_DEFAULT, "avformat_close_input");
    if (!openInput || !findStreamInfo || !packetAlloc || !packetFree
        || !packetUnref || !readFrame || !closeInput) {
        if (error) {
            *error = [NSError errorWithDomain:@"HoshiVideoSubtitleExtraction" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"The bundled subtitle extractor is unavailable."
            }];
        }
        return nil;
    }

    HSAVFormatContext *context = NULL;
    if (openInput(&context, url.fileSystemRepresentation, NULL, NULL) < 0
        || !context
        || findStreamInfo(context, NULL) < 0) {
        if (context) closeInput(&context);
        if (error) {
            *error = [NSError errorWithDomain:@"HoshiVideoSubtitleExtraction" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"The selected subtitle track could not be opened."
            }];
        }
        return nil;
    }

    HSAVStream *targetStream = NULL;
    for (unsigned int index = 0; index < context->streamCount; index++) {
        if (context->streams[index] && context->streams[index]->index == streamIndex) {
            targetStream = context->streams[index];
            break;
        }
    }
    if (!targetStream || targetStream->timeBase.den == 0) {
        closeInput(&context);
        if (error) {
            *error = [NSError errorWithDomain:@"HoshiVideoSubtitleExtraction" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"The selected subtitle track is no longer available."
            }];
        }
        return nil;
    }

    NSMutableArray<HSExtractedSubtitleCue *> *result = [NSMutableArray array];
    HSAVPacket *packet = packetAlloc();
    if (!packet) {
        closeInput(&context);
        return nil;
    }
    while (readFrame(context, packet) >= 0) {
        if (packet->streamIndex == streamIndex
            && packet->presentationTimestamp != INT64_MIN
            && packet->data
            && packet->size > 0) {
            NSString *text = [[NSString alloc] initWithBytes:packet->data
                length:(NSUInteger)packet->size
                encoding:NSUTF8StringEncoding];
            if (text.length > 0) {
                double scale = (double)targetStream->timeBase.num
                    / (double)targetStream->timeBase.den;
                HSExtractedSubtitleCue *cue = [[HSExtractedSubtitleCue alloc] init];
                cue.startTime = MAX(0, packet->presentationTimestamp * scale);
                cue.endTime = cue.startTime + (packet->duration > 0
                    ? packet->duration * scale
                    : 10);
                cue.text = text;
                [result addObject:cue];
            }
        }
        packetUnref(packet);
    }
    packetFree(&packet);
    closeInput(&context);
    return result;
}

@end

@implementation HSMpvChapterInfo
@end

@implementation HSMpvSubtitleCueInfo
@end

static void *HSMpvGetOpenGLProcAddress(void *context, const char *name) {
    CFStringRef symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    void *address = bundle ? CFBundleGetFunctionPointerForName(bundle, symbol) : NULL;
    CFRelease(symbol);
    return address;
}

@interface HSMpvOpenGLView ()
@property (nonatomic, assign) mpv_render_context *renderContext;
@end

@implementation HSMpvOpenGLView

- (void)notifyReadyIfPossible {
    if (self.window && self.openGLContext && !NSIsEmptyRect(self.bounds) && self.onReady) {
        [self.openGLContext makeCurrentContext];
        self.onReady(self);
    }
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSOpenGLPixelFormatAttribute attributes[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    self = [super initWithFrame:frameRect pixelFormat:format];
    if (self) {
        self.wantsBestResolutionOpenGLSurface = YES;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        GLint swapInterval = 1;
        [self.openGLContext setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
    }
    return self;
}

- (void)prepareOpenGL {
    [super prepareOpenGL];
    self.openGLContext.view = self;
    [self notifyReadyIfPossible];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self notifyReadyIfPossible];
}

- (void)layout {
    [super layout];
    [self notifyReadyIfPossible];
}

- (void)drawRect:(NSRect)dirtyRect {
    [self.openGLContext makeCurrentContext];
    if (self.renderContext) {
        NSRect backingBounds = [self convertRectToBacking:self.bounds];
        mpv_opengl_fbo framebuffer = {
            .fbo = 0,
            .w = (int)backingBounds.size.width,
            .h = (int)backingBounds.size.height,
            .internal_format = 0
        };
        int flip = 1;
        mpv_render_param parameters[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &framebuffer },
            { MPV_RENDER_PARAM_FLIP_Y, &flip },
            { MPV_RENDER_PARAM_INVALID, NULL }
        };
        mpv_render_context_render(self.renderContext, parameters);
    } else {
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    [self.openGLContext flushBuffer];
}

@end

@interface HSMpvClient () {
    mpv_handle *_handle;
    mpv_render_context *_renderContext;
    dispatch_queue_t _eventQueue;
    dispatch_queue_t _ambientPreviewQueue;
    __weak HSMpvOpenGLView *_view;
    double _currentTime;
    double _duration;
    BOOL _paused;
    BOOL _loaded;
    BOOL _shuttingDown;
    double _speed;
    double _volume;
    BOOL _muted;
    double _subtitleDelay;
    double _audioDelay;
    NSString *_loopMode;
    double _abLoopStart;
    double _abLoopEnd;
    NSString *_aspectRatio;
    NSInteger _rotation;
    NSInteger _videoWidth;
    NSInteger _videoHeight;
    double _lastSubtitleRefreshTime;
    NSUInteger _subtitleCueSignature;
    NSUInteger _subtitleCueCount;
    NSMutableArray<HSMpvSubtitleCueInfo *> *_fallbackSubtitleCues;
    std::atomic<uint64_t> _loadGeneration;
}
- (void)startEventLoop;
- (void)runEventLoop;
- (void)handleEvent:(mpv_event *)event;
- (void)handlePropertyChange:(mpv_event_property *)property;
- (void)emitStateWithError:(nullable NSString *)errorMessage;
- (void)emitTracksFromNode:(mpv_node *)node;
- (void)emitChaptersFromNode:(mpv_node *)node;
- (void)emitSubtitleCuesFromNode:(nullable mpv_node *)node;
- (void)emitSubtitleCueSnapshot:(NSArray<HSMpvSubtitleCueInfo *> *)cues;
- (void)refreshSubtitleCues;
- (void)refreshCurrentSubtitleCue;
- (BOOL)isCurrentLoadGeneration:(uint64_t)guardedLoadGeneration;
@end

static void HSMpvRenderUpdate(void *context) {
    HSMpvOpenGLView *view = (__bridge HSMpvOpenGLView *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [view setNeedsDisplay:YES];
    });
}

@implementation HSMpvClient

+ (nullable instancetype)makeClientWithErrorMessage:(NSString **)errorMessage {
    NSError *error = nil;
    HSMpvClient *client = [[self alloc] initWithError:&error];
    if (!client && errorMessage) {
        *errorMessage = error.localizedDescription;
    }
    return client;
}

- (nullable instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    _eventQueue = dispatch_queue_create("moe.shishamo.hoshi.video.mpv-events", DISPATCH_QUEUE_SERIAL);
    _ambientPreviewQueue = dispatch_queue_create(
        "moe.shishamo.hoshi.video.ambient-preview",
        DISPATCH_QUEUE_SERIAL
    );
    _loadGeneration.store(0, std::memory_order_release);
    _handle = mpv_create();
    if (!_handle) {
        if (error) {
            *error = [NSError errorWithDomain:HSMpvErrorDomain code:-1 userInfo:@{
                NSLocalizedDescriptionKey: @"Unable to create the video playback engine."
            }];
        }
        return nil;
    }

    mpv_set_option_string(_handle, "config", "no");
    mpv_set_option_string(_handle, "osc", "no");
    mpv_set_option_string(_handle, "input-default-bindings", "no");
    mpv_set_option_string(_handle, "input-cursor", "no");
    mpv_set_option_string(_handle, "sid", "no");
    mpv_set_option_string(_handle, "vo", "libmpv");
    mpv_set_option_string(_handle, "keep-open", "yes");

    int status = mpv_initialize(_handle);
    if (status < 0) {
        if (error) {
            NSString *message = [NSString stringWithUTF8String:mpv_error_string(status)];
            *error = [NSError errorWithDomain:HSMpvErrorDomain code:status userInfo:@{
                NSLocalizedDescriptionKey: message
            }];
        }
        mpv_destroy(_handle);
        _handle = NULL;
        return nil;
    }

    mpv_observe_property(_handle, 1, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 2, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 3, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(_handle, 4, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 5, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 6, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(_handle, 7, "sub-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 8, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(_handle, 9, "audio-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(_handle, 10, "chapter-list", MPV_FORMAT_NODE);
    mpv_observe_property(_handle, 11, "video-rotate", MPV_FORMAT_INT64);
    mpv_observe_property(_handle, 12, "video-params", MPV_FORMAT_NODE);
    _speed = 1.0;
    _volume = 100.0;
    _loopMode = @"none";
    _abLoopStart = NAN;
    _abLoopEnd = NAN;
    _aspectRatio = @"-1";
    _fallbackSubtitleCues = [NSMutableArray array];
    [self startEventLoop];
    return self;
}

- (void)dealloc {
    [self shutdown];
}

- (BOOL)attachToView:(HSMpvOpenGLView *)view {
    if (!_handle || _renderContext || _shuttingDown) {
        return _renderContext != NULL;
    }
    [view.openGLContext makeCurrentContext];
    mpv_opengl_init_params openGL = {
        .get_proc_address = HSMpvGetOpenGLProcAddress,
        .get_proc_address_ctx = NULL
    };
    const char *apiType = MPV_RENDER_API_TYPE_OPENGL;
    mpv_render_param parameters[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)apiType },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &openGL },
        { MPV_RENDER_PARAM_INVALID, NULL }
    };
    if (mpv_render_context_create(&_renderContext, _handle, parameters) < 0) {
        [self emitStateWithError:@"Unable to create the video rendering surface."];
        return NO;
    }
    _view = view;
    view.renderContext = _renderContext;
    mpv_render_context_set_update_callback(_renderContext, HSMpvRenderUpdate, (__bridge void *)view);
    [view setNeedsDisplay:YES];
    return YES;
}

- (void)detachFromView {
    if (_renderContext) {
        mpv_render_context_set_update_callback(_renderContext, NULL, NULL);
        _view.renderContext = NULL;
        mpv_render_context_free(_renderContext);
        _renderContext = NULL;
    }
    _view = nil;
}

- (void)loadFile:(NSURL *)url {
    if (!_handle || _shuttingDown) {
        return;
    }
    _loadGeneration.fetch_add(1, std::memory_order_acq_rel);
    _currentTime = 0;
    _duration = 0;
    _loaded = NO;
    _videoWidth = 0;
    _videoHeight = 0;
    _lastSubtitleRefreshTime = -1;
    _subtitleCueSignature = 0;
    _subtitleCueCount = 0;
    [_fallbackSubtitleCues removeAllObjects];
    [self emitSubtitleCuesFromNode:NULL];
    const char *command[] = { "loadfile", url.fileSystemRepresentation, "replace", NULL };
    int status = mpv_command(_handle, command);
    if (status < 0) {
        [self emitStateWithError:[NSString stringWithUTF8String:mpv_error_string(status)]];
    }
}

- (BOOL)isCurrentLoadGeneration:(uint64_t)guardedLoadGeneration {
    return guardedLoadGeneration == _loadGeneration.load(std::memory_order_acquire);
}

- (void)setPaused:(BOOL)paused {
    if (!_handle || _shuttingDown) {
        return;
    }
    int value = paused ? 1 : 0;
    mpv_set_property(_handle, "pause", MPV_FORMAT_FLAG, &value);
}

- (void)seekTo:(double)seconds {
    if (!_handle || _shuttingDown) {
        return;
    }
    NSString *value = [NSString stringWithFormat:@"%.6f", seconds];
    const char *command[] = { "seek", value.UTF8String, "absolute+exact", NULL };
    mpv_command_async(_handle, 0, command);
}

- (void)setSpeed:(double)speed {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_set_property(_handle, "speed", MPV_FORMAT_DOUBLE, &speed);
}

- (void)setVolume:(double)volume {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_set_property(_handle, "volume", MPV_FORMAT_DOUBLE, &volume);
}

- (void)setMuted:(BOOL)muted {
    if (!_handle || _shuttingDown) {
        return;
    }
    int value = muted ? 1 : 0;
    mpv_set_property(_handle, "mute", MPV_FORMAT_FLAG, &value);
}

- (void)setSubtitleDelay:(double)delay {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_set_property(_handle, "sub-delay", MPV_FORMAT_DOUBLE, &delay);
}

- (void)setAudioDelay:(double)delay {
    if (!_handle || _shuttingDown) {
        return;
    }
    _audioDelay = delay;
    mpv_set_property(_handle, "audio-delay", MPV_FORMAT_DOUBLE, &delay);
    [self emitStateWithError:nil];
}

- (void)setLoopMode:(NSString *)mode {
    if (!_handle || _shuttingDown) {
        return;
    }
    _loopMode = [mode isEqualToString:@"file"] ? @"file" : @"none";
    mpv_set_property_string(
        _handle,
        "loop-file",
        [_loopMode isEqualToString:@"file"] ? "inf" : "no"
    );
    [self emitStateWithError:nil];
}

- (void)setABLoopStart:(nullable NSNumber *)start end:(nullable NSNumber *)end {
    if (!_handle || _shuttingDown) {
        return;
    }
    _abLoopStart = start ? start.doubleValue : NAN;
    _abLoopEnd = end ? end.doubleValue : NAN;
    mpv_set_property_string(
        _handle,
        "ab-loop-a",
        start ? start.stringValue.UTF8String : "no"
    );
    mpv_set_property_string(
        _handle,
        "ab-loop-b",
        end ? end.stringValue.UTF8String : "no"
    );
    [self emitStateWithError:nil];
}

- (void)setAspectRatio:(NSString *)aspectRatio {
    if (!_handle || _shuttingDown) {
        return;
    }
    _aspectRatio = aspectRatio.length > 0 ? aspectRatio.copy : @"-1";
    mpv_set_property_string(
        _handle,
        "video-aspect-override",
        _aspectRatio.UTF8String
    );
    [self emitStateWithError:nil];
}

- (void)setRotation:(NSInteger)degrees {
    if (!_handle || _shuttingDown) {
        return;
    }
    int64_t value = (int64_t)(((degrees % 360) + 360) % 360);
    _rotation = (NSInteger)value;
    mpv_set_property(_handle, "video-rotate", MPV_FORMAT_INT64, &value);
    [self emitStateWithError:nil];
}

- (void)setHardwareDecodingEnabled:(BOOL)enabled {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_set_property_string(_handle, "hwdec", enabled ? "auto-safe" : "no");
}

- (void)setDeinterlacingEnabled:(BOOL)enabled {
    if (!_handle || _shuttingDown) {
        return;
    }
    int value = enabled ? 1 : 0;
    mpv_set_property(_handle, "deinterlace", MPV_FORMAT_FLAG, &value);
}

- (void)setHDREnhancementEnabled:(BOOL)enabled {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_set_property_string(_handle, "hdr-compute-peak", enabled ? "yes" : "no");
    mpv_set_property_string(_handle, "tone-mapping", "auto");
}

- (void)setVideoEqualizer:(NSString *)adjustment value:(double)value {
    if (!_handle || _shuttingDown) {
        return;
    }
    NSSet<NSString *> *supportedAdjustments = [NSSet setWithObjects:
        @"brightness",
        @"contrast",
        @"saturation",
        @"gamma",
        @"hue",
        nil
    ];
    if (![supportedAdjustments containsObject:adjustment]) {
        return;
    }
    double normalized = isfinite(value) ? MIN(MAX(value, -100.0), 100.0) : 0.0;
    NSString *valueString = [NSString stringWithFormat:@"%.0f", normalized];
    mpv_set_property_string(_handle, adjustment.UTF8String, valueString.UTF8String);
}

- (void)seekToChapter:(NSInteger)index {
    if (!_handle || _shuttingDown) {
        return;
    }
    int64_t value = (int64_t)index;
    mpv_set_property(_handle, "chapter", MPV_FORMAT_INT64, &value);
}

static mpv_node *HSMpvMapValue(mpv_node *node, const char *key) {
    if (!node || node->format != MPV_FORMAT_NODE_MAP || !node->u.list) {
        return NULL;
    }
    for (int index = 0; index < node->u.list->num; index++) {
        if (node->u.list->keys[index] && strcmp(node->u.list->keys[index], key) == 0) {
            return &node->u.list->values[index];
        }
    }
    return NULL;
}

static BOOL HSMpvNodeDoubleValue(mpv_node *node, double *value) {
    if (!node || !value) {
        return NO;
    }
    if (node->format == MPV_FORMAT_DOUBLE) {
        *value = node->u.double_;
        return isfinite(*value);
    }
    if (node->format == MPV_FORMAT_INT64) {
        *value = (double)node->u.int64;
        return isfinite(*value);
    }
    return NO;
}

static NSSize HSMpvVideoDisplaySizeFromNode(mpv_node *node) {
    double width = 0;
    double height = 0;
    BOOL hasDisplayWidth = HSMpvNodeDoubleValue(HSMpvMapValue(node, "dw"), &width);
    BOOL hasDisplayHeight = HSMpvNodeDoubleValue(HSMpvMapValue(node, "dh"), &height);
    if (!hasDisplayWidth || !hasDisplayHeight || width <= 0 || height <= 0) {
        hasDisplayWidth = HSMpvNodeDoubleValue(HSMpvMapValue(node, "w"), &width);
        hasDisplayHeight = HSMpvNodeDoubleValue(HSMpvMapValue(node, "h"), &height);
    }
    if (!hasDisplayWidth || !hasDisplayHeight || width <= 0 || height <= 0) {
        return NSZeroSize;
    }
    return NSMakeSize(width, height);
}

static NSImage *HSMpvAmbientImageFromNode(mpv_node *node, NSInteger maximumDimension) {
    mpv_node *widthNode = HSMpvMapValue(node, "w");
    mpv_node *heightNode = HSMpvMapValue(node, "h");
    mpv_node *strideNode = HSMpvMapValue(node, "stride");
    mpv_node *formatNode = HSMpvMapValue(node, "format");
    mpv_node *dataNode = HSMpvMapValue(node, "data");
    if (!widthNode || !heightNode || !strideNode || !formatNode || !dataNode
        || widthNode->format != MPV_FORMAT_INT64
        || heightNode->format != MPV_FORMAT_INT64
        || strideNode->format != MPV_FORMAT_INT64
        || formatNode->format != MPV_FORMAT_STRING
        || dataNode->format != MPV_FORMAT_BYTE_ARRAY
        || !dataNode->u.ba || !dataNode->u.ba->data) {
        return nil;
    }

    NSInteger width = (NSInteger)widthNode->u.int64;
    NSInteger height = (NSInteger)heightNode->u.int64;
    NSInteger stride = (NSInteger)strideNode->u.int64;
    NSString *format = [NSString stringWithUTF8String:formatNode->u.string ?: ""];
    if (width <= 0 || height <= 0 || stride == 0 || maximumDimension <= 0) {
        return nil;
    }
    BOOL blueFirst = [format isEqualToString:@"bgr0"] || [format isEqualToString:@"bgra"];
    BOOL redFirst = [format isEqualToString:@"rgb0"] || [format isEqualToString:@"rgba"];
    if (!blueFirst && !redFirst) {
        return nil;
    }

    CGFloat scale = MIN(1.0, (CGFloat)maximumDimension / (CGFloat)MAX(width, height));
    NSInteger outputWidth = MAX(1, (NSInteger)floor((CGFloat)width * scale));
    NSInteger outputHeight = MAX(1, (NSInteger)floor((CGFloat)height * scale));
    NSMutableData *rgbaData = [NSMutableData dataWithLength:(NSUInteger)(outputWidth * outputHeight * 4)];
    const uint8_t *source = (const uint8_t *)dataNode->u.ba->data;
    uint8_t *destination = (uint8_t *)rgbaData.mutableBytes;
    NSInteger absoluteStride = labs(stride);
    if ((NSUInteger)(absoluteStride * height) > dataNode->u.ba->size) {
        return nil;
    }

    for (NSInteger y = 0; y < outputHeight; y++) {
        NSInteger sourceY = MIN(height - 1, (NSInteger)floor((CGFloat)y / scale));
        const uint8_t *sourceRow = stride > 0
            ? source + sourceY * stride
            : source + (height - 1 - sourceY) * absoluteStride;
        for (NSInteger x = 0; x < outputWidth; x++) {
            NSInteger sourceX = MIN(width - 1, (NSInteger)floor((CGFloat)x / scale));
            const uint8_t *pixel = sourceRow + sourceX * 4;
            uint8_t *output = destination + (y * outputWidth + x) * 4;
            output[0] = blueFirst ? pixel[2] : pixel[0];
            output[1] = pixel[1];
            output[2] = blueFirst ? pixel[0] : pixel[2];
            output[3] = 255;
        }
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgbaData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)(
        (uint32_t)kCGImageAlphaPremultipliedLast
        | (uint32_t)kCGBitmapByteOrder32Big
    );
    CGImageRef image = CGImageCreate(
        outputWidth,
        outputHeight,
        8,
        32,
        outputWidth * 4,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        true,
        kCGRenderingIntentDefault
    );
    NSImage *result = image
        ? [[NSImage alloc] initWithCGImage:image size:NSMakeSize(outputWidth, outputHeight)]
        : nil;
    if (image) CGImageRelease(image);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    return result;
}

- (void)captureAmbientPreviewWithMaximumDimension:(NSInteger)maximumDimension
    completion:(void (^)(NSImage * _Nullable image, NSInteger generation))completion {
    if (!completion) {
        return;
    }
    uint64_t guardedGeneration = _loadGeneration.load(std::memory_order_acquire);
    dispatch_async(_ambientPreviewQueue, ^{
        NSImage *image = nil;
        if (self->_handle && !self->_shuttingDown) {
            const char *command[] = { "screenshot-raw", "video", NULL };
            mpv_node result = {0};
            int status = mpv_command_ret(self->_handle, command, &result);
            if (status >= 0) {
                image = HSMpvAmbientImageFromNode(&result, maximumDimension);
                mpv_free_node_contents(&result);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image, (NSInteger)guardedGeneration);
        });
    });
}

- (BOOL)captureScreenshotToURL:(NSURL *)url errorMessage:(NSString **)errorMessage {
    if (!_handle || _shuttingDown) {
        if (errorMessage) {
            *errorMessage = @"Video playback is not available.";
        }
        return NO;
    }
    const char *command[] = {
        "screenshot-to-file",
        url.fileSystemRepresentation,
        "video",
        NULL
    };
    int status = mpv_command(_handle, command);
    if (status < 0) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithUTF8String:mpv_error_string(status)];
        }
        return NO;
    }
    return YES;
}

- (void)loadExternalSubtitle:(NSURL *)url {
    if (!_handle || _shuttingDown) {
        return;
    }
    [_fallbackSubtitleCues removeAllObjects];
    _subtitleCueSignature = 0;
    _subtitleCueCount = 0;
    [self emitSubtitleCuesFromNode:NULL];
    const char *command[] = {
        "sub-add",
        url.fileSystemRepresentation,
        "select",
        NULL
    };
    int status = mpv_command(_handle, command);
    if (status < 0) {
        NSString *absoluteString = url.absoluteString;
        const char *urlCommand[] = {
            "sub-add",
            absoluteString.UTF8String,
            "select",
            NULL
        };
        status = mpv_command(_handle, urlCommand);
    }
    if (status < 0) {
        NSLog(
            @"Failed to load external subtitle into mpv: %@ (%s)",
            url.path,
            mpv_error_string(status)
        );
        return;
    }
    mpv_set_property_string(_handle, "sub-visibility", "no");
    [self refreshSubtitleCues];
}

- (void)selectTrackType:(NSString *)type trackID:(nullable NSNumber *)trackID {
    if (!_handle || _shuttingDown) {
        return;
    }
    NSString *property = nil;
    if ([type isEqualToString:@"audio"]) {
        property = @"aid";
    } else if ([type isEqualToString:@"subtitle"]) {
        property = @"sid";
    } else if ([type isEqualToString:@"video"]) {
        property = @"vid";
    }
    if (!property) {
        return;
    }
    NSString *value = trackID ? trackID.stringValue : @"no";
    if ([type isEqualToString:@"subtitle"]) {
        [_fallbackSubtitleCues removeAllObjects];
        _subtitleCueSignature = 0;
        _subtitleCueCount = 0;
        [self emitSubtitleCuesFromNode:NULL];
        mpv_set_property_string(_handle, "sub-visibility", "no");
    }
    int status = mpv_set_property_string(
        _handle,
        property.UTF8String,
        value.UTF8String
    );
    (void)status;
}

- (void)shutdown {
    if (_shuttingDown) {
        return;
    }
    _shuttingDown = YES;
    if (_handle) {
        mpv_wakeup(_handle);
        dispatch_sync(_eventQueue, ^{});
        // A screenshot-raw command may still be copying pixels on the preview queue.
        // Wait for it before destroying the shared mpv client handle.
        dispatch_sync(_ambientPreviewQueue, ^{});
    }
    [self detachFromView];
    if (_handle) {
        mpv_terminate_destroy(_handle);
        _handle = NULL;
    }
}

- (void)startEventLoop {
    dispatch_async(_eventQueue, ^{
        [self runEventLoop];
    });
}

- (void)runEventLoop {
    while (_handle && !_shuttingDown) {
        mpv_event *event = mpv_wait_event(_handle, -1);
        if (!event) {
            continue;
        }
        if (event->event_id == MPV_EVENT_NONE) {
            if (_shuttingDown) {
                return;
            }
            continue;
        }
        [self handleEvent:event];
    }
}

- (void)handleEvent:(mpv_event *)event {
    switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED:
            _loaded = YES;
            [self refreshSubtitleCues];
            [self emitStateWithError:nil];
            break;
        case MPV_EVENT_END_FILE: {
            mpv_event_end_file *end = (mpv_event_end_file *)event->data;
            if (end && end->error < 0) {
                [self emitStateWithError:[NSString stringWithUTF8String:mpv_error_string(end->error)]];
            } else if (end && end->reason == MPV_END_FILE_REASON_EOF) {
                void (^handler)(void) = self.playbackEndedHandler;
                if (handler) {
                    uint64_t guardedLoadGeneration = _loadGeneration.load(std::memory_order_acquire);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (![self isCurrentLoadGeneration:guardedLoadGeneration]) {
                            return;
                        }
                        handler();
                    });
                }
            }
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE:
            [self handlePropertyChange:(mpv_event_property *)event->data];
            break;
        default:
            break;
    }
}

- (void)handlePropertyChange:(mpv_event_property *)property {
    if (!property || !property->data || !property->name) {
        return;
    }
    if (strcmp(property->name, "time-pos") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _currentTime = *(double *)property->data;
        if (_lastSubtitleRefreshTime < 0
            || fabs(_currentTime - _lastSubtitleRefreshTime) >= 0.25) {
            _lastSubtitleRefreshTime = _currentTime;
            [self refreshSubtitleCues];
        }
    } else if (strcmp(property->name, "duration") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _duration = *(double *)property->data;
    } else if (strcmp(property->name, "pause") == 0 && property->format == MPV_FORMAT_FLAG) {
        _paused = *(int *)property->data != 0;
    } else if (strcmp(property->name, "speed") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _speed = *(double *)property->data;
    } else if (strcmp(property->name, "volume") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _volume = *(double *)property->data;
    } else if (strcmp(property->name, "mute") == 0 && property->format == MPV_FORMAT_FLAG) {
        _muted = *(int *)property->data != 0;
    } else if (strcmp(property->name, "sub-delay") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _subtitleDelay = *(double *)property->data;
    } else if (strcmp(property->name, "audio-delay") == 0 && property->format == MPV_FORMAT_DOUBLE) {
        _audioDelay = *(double *)property->data;
    } else if (strcmp(property->name, "track-list") == 0 && property->format == MPV_FORMAT_NODE) {
        [self emitTracksFromNode:(mpv_node *)property->data];
        [self refreshSubtitleCues];
    } else if (strcmp(property->name, "chapter-list") == 0 && property->format == MPV_FORMAT_NODE) {
        [self emitChaptersFromNode:(mpv_node *)property->data];
    } else if (strcmp(property->name, "video-rotate") == 0 && property->format == MPV_FORMAT_INT64) {
        _rotation = (NSInteger)*(int64_t *)property->data;
    } else if (strcmp(property->name, "video-params") == 0 && property->format == MPV_FORMAT_NODE) {
        NSSize displaySize = HSMpvVideoDisplaySizeFromNode((mpv_node *)property->data);
        _videoWidth = displaySize.width > 0 ? (NSInteger)llround(displaySize.width) : 0;
        _videoHeight = displaySize.height > 0 ? (NSInteger)llround(displaySize.height) : 0;
    }
    [self emitStateWithError:nil];
}

- (void)emitChaptersFromNode:(mpv_node *)node {
    if (!node || node->format != MPV_FORMAT_NODE_ARRAY || !node->u.list) {
        return;
    }
    NSMutableArray<HSMpvChapterInfo *> *chapters = [NSMutableArray array];
    mpv_node_list *list = node->u.list;
    for (int index = 0; index < list->num; index++) {
        mpv_node item = list->values[index];
        if (item.format != MPV_FORMAT_NODE_MAP || !item.u.list) {
            continue;
        }
        HSMpvChapterInfo *chapter = [[HSMpvChapterInfo alloc] init];
        chapter.chapterID = index;
        chapter.title = [NSString stringWithFormat:@"Chapter %d", index + 1];
        mpv_node_list *map = item.u.list;
        for (int field = 0; field < map->num; field++) {
            const char *key = map->keys[field];
            mpv_node value = map->values[field];
            if (!key) {
                continue;
            }
            if (strcmp(key, "title") == 0 && value.format == MPV_FORMAT_STRING) {
                chapter.title = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "time") == 0) {
                if (value.format == MPV_FORMAT_DOUBLE) {
                    chapter.startTime = value.u.double_;
                } else if (value.format == MPV_FORMAT_INT64) {
                    chapter.startTime = (double)value.u.int64;
                }
            }
        }
        [chapters addObject:chapter];
    }
    void (^handler)(NSArray<HSMpvChapterInfo *> *) = self.chapterHandler;
    if (handler) {
        NSArray<HSMpvChapterInfo *> *snapshot = chapters.copy;
        uint64_t guardedLoadGeneration = _loadGeneration.load(std::memory_order_acquire);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isCurrentLoadGeneration:guardedLoadGeneration]) {
                return;
            }
            handler(snapshot);
        });
    }
}

- (void)emitTracksFromNode:(mpv_node *)node {
    if (!node || node->format != MPV_FORMAT_NODE_ARRAY || !node->u.list) {
        return;
    }
    NSMutableArray<HSMpvTrackInfo *> *tracks = [NSMutableArray array];
    mpv_node_list *list = node->u.list;
    for (int index = 0; index < list->num; index++) {
        mpv_node item = list->values[index];
        if (item.format != MPV_FORMAT_NODE_MAP || !item.u.list) {
            continue;
        }
        HSMpvTrackInfo *track = [[HSMpvTrackInfo alloc] init];
        track.ffIndex = -1;
        mpv_node_list *map = item.u.list;
        for (int field = 0; field < map->num; field++) {
            const char *key = map->keys[field];
            mpv_node value = map->values[field];
            if (!key) {
                continue;
            }
            if (strcmp(key, "id") == 0 && value.format == MPV_FORMAT_INT64) {
                track.trackID = (NSInteger)value.u.int64;
            } else if (strcmp(key, "type") == 0 && value.format == MPV_FORMAT_STRING) {
                track.type = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "title") == 0 && value.format == MPV_FORMAT_STRING) {
                track.title = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "lang") == 0 && value.format == MPV_FORMAT_STRING) {
                track.language = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "codec") == 0 && value.format == MPV_FORMAT_STRING) {
                track.codec = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "ff-index") == 0 && value.format == MPV_FORMAT_INT64) {
                track.ffIndex = (NSInteger)value.u.int64;
            } else if (strcmp(key, "external-filename") == 0 && value.format == MPV_FORMAT_STRING) {
                track.externalFilename = [NSString stringWithUTF8String:value.u.string];
            } else if (strcmp(key, "image") == 0 && value.format == MPV_FORMAT_FLAG) {
                track.image = value.u.flag != 0;
            } else if (strcmp(key, "selected") == 0 && value.format == MPV_FORMAT_FLAG) {
                track.selected = value.u.flag != 0;
            }
        }
        if (track.type.length == 0) {
            continue;
        }
        if (track.title.length == 0) {
            track.title = [NSString stringWithFormat:@"%@ %ld",
                track.type.capitalizedString,
                (long)track.trackID];
        }
        [tracks addObject:track];
    }
    BOOL shouldRenderNativeImageSubtitles = NO;
    for (HSMpvTrackInfo *track in tracks) {
        if ([track.type isEqualToString:@"sub"] && track.isSelected && track.isImage) {
            shouldRenderNativeImageSubtitles = YES;
            break;
        }
    }
    if (_handle && !_shuttingDown) {
        mpv_set_property_string(
            _handle,
            "sub-visibility",
            shouldRenderNativeImageSubtitles ? "yes" : "no"
        );
    }
    void (^handler)(NSArray<HSMpvTrackInfo *> *) = self.trackHandler;
    if (handler) {
        NSArray<HSMpvTrackInfo *> *snapshot = tracks.copy;
        uint64_t guardedLoadGeneration = _loadGeneration.load(std::memory_order_acquire);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isCurrentLoadGeneration:guardedLoadGeneration]) {
                return;
            }
            handler(snapshot);
        });
    }
}

- (void)emitSubtitleCuesFromNode:(nullable mpv_node *)node {
    NSMutableArray<HSMpvSubtitleCueInfo *> *cues = [NSMutableArray array];
    if (node && node->format == MPV_FORMAT_NODE_ARRAY && node->u.list) {
        mpv_node_list *list = node->u.list;
        for (int index = 0; index < list->num; index++) {
            mpv_node item = list->values[index];
            if (item.format != MPV_FORMAT_NODE_MAP || !item.u.list) {
                continue;
            }
            HSMpvSubtitleCueInfo *cue = [[HSMpvSubtitleCueInfo alloc] init];
            cue.endTime = NAN;
            mpv_node_list *map = item.u.list;
            for (int field = 0; field < map->num; field++) {
                const char *key = map->keys[field];
                mpv_node value = map->values[field];
                if (!key) {
                    continue;
                }
                if (strcmp(key, "text") == 0 && value.format == MPV_FORMAT_STRING) {
                    cue.text = [NSString stringWithUTF8String:value.u.string];
                } else if (strcmp(key, "start") == 0) {
                    if (value.format == MPV_FORMAT_DOUBLE) {
                        cue.startTime = value.u.double_;
                    } else if (value.format == MPV_FORMAT_INT64) {
                        cue.startTime = (double)value.u.int64;
                    }
                } else if (strcmp(key, "end") == 0) {
                    if (value.format == MPV_FORMAT_DOUBLE) {
                        cue.endTime = value.u.double_;
                    } else if (value.format == MPV_FORMAT_INT64) {
                        cue.endTime = (double)value.u.int64;
                    }
                }
            }
            if (cue.text.length == 0) {
                continue;
            }
            if (isnan(cue.endTime)) {
                cue.endTime = cue.startTime + 10;
            }
            cue.cueID = [NSString stringWithFormat:@"embedded-%d-%.6f", index, cue.startTime];
            [cues addObject:cue];
        }
    }

    [self emitSubtitleCueSnapshot:cues];
}

- (void)emitSubtitleCueSnapshot:(NSArray<HSMpvSubtitleCueInfo *> *)cues {
    NSUInteger signature = 17;
    for (HSMpvSubtitleCueInfo *cue in cues) {
        signature = signature * 31u ^ cue.cueID.hash;
        signature = signature * 31u ^ cue.text.hash;
        signature = signature * 31u ^ @(cue.endTime).hash;
    }
    if (_subtitleCueCount == cues.count && _subtitleCueSignature == signature) {
        return;
    }
    _subtitleCueCount = cues.count;
    _subtitleCueSignature = signature;

    if (_handle && !_shuttingDown) {
        mpv_set_property_string(
            _handle,
            "sub-visibility",
            "no"
        );
    }
    void (^handler)(NSArray<HSMpvSubtitleCueInfo *> *) = self.subtitleCueHandler;
    if (handler) {
        NSArray<HSMpvSubtitleCueInfo *> *snapshot = cues.copy;
        uint64_t guardedLoadGeneration = _loadGeneration.load(std::memory_order_acquire);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isCurrentLoadGeneration:guardedLoadGeneration]) {
                return;
            }
            handler(snapshot);
        });
    }
}

- (void)refreshSubtitleCues {
    if (!_handle || _shuttingDown) {
        return;
    }
    mpv_node node = {0};
    int status = mpv_get_property(_handle, "sub-lines", MPV_FORMAT_NODE, &node);
    if (status >= 0) {
        [self emitSubtitleCuesFromNode:&node];
        mpv_free_node_contents(&node);
    } else if (status == MPV_ERROR_PROPERTY_NOT_FOUND) {
        [self refreshCurrentSubtitleCue];
    } else {
        [self emitSubtitleCuesFromNode:NULL];
    }
}

- (void)refreshCurrentSubtitleCue {
    char *textValue = NULL;
    double startTime = 0;
    double endTime = 0;
    int textStatus = mpv_get_property(
        _handle,
        "sub-text",
        MPV_FORMAT_STRING,
        &textValue
    );
    int startStatus = mpv_get_property(
        _handle,
        "sub-start",
        MPV_FORMAT_DOUBLE,
        &startTime
    );
    int endStatus = mpv_get_property(
        _handle,
        "sub-end",
        MPV_FORMAT_DOUBLE,
        &endTime
    );

    if (textStatus >= 0 && startStatus >= 0 && textValue && textValue[0] != '\0') {
        NSString *text = [NSString stringWithUTF8String:textValue];
        NSString *cueID = [NSString stringWithFormat:
            @"embedded-%.6f-%lu",
            startTime,
            (unsigned long)text.hash
        ];
        NSUInteger existingIndex = [_fallbackSubtitleCues indexOfObjectPassingTest:
            ^BOOL(HSMpvSubtitleCueInfo *cue, NSUInteger index, BOOL *stop) {
                return [cue.cueID isEqualToString:cueID];
            }
        ];
        HSMpvSubtitleCueInfo *cue = existingIndex == NSNotFound
            ? [[HSMpvSubtitleCueInfo alloc] init]
            : _fallbackSubtitleCues[existingIndex];
        cue.cueID = cueID;
        cue.startTime = startTime;
        cue.endTime = endStatus >= 0 && endTime >= startTime
            ? endTime
            : startTime + 10;
        cue.text = text;
        if (existingIndex == NSNotFound) {
            [_fallbackSubtitleCues addObject:cue];
            [_fallbackSubtitleCues sortUsingComparator:
                ^NSComparisonResult(HSMpvSubtitleCueInfo *left, HSMpvSubtitleCueInfo *right) {
                    if (left.startTime < right.startTime) {
                        return NSOrderedAscending;
                    }
                    if (left.startTime > right.startTime) {
                        return NSOrderedDescending;
                    }
                    return NSOrderedSame;
                }
            ];
        }
    }
    if (textValue) {
        mpv_free(textValue);
    }
    [self emitSubtitleCueSnapshot:_fallbackSubtitleCues.copy];
}

- (void)emitStateWithError:(nullable NSString *)errorMessage {
    HSMpvStateHandler handler = self.stateHandler;
    if (!handler) {
        return;
    }
    double currentTime = _currentTime;
    double duration = _duration;
    BOOL playing = !_paused && _loaded;
    BOOL loaded = _loaded;
    double speed = _speed;
    double volume = _volume;
    BOOL muted = _muted;
    double subtitleDelay = _subtitleDelay;
    double audioDelay = _audioDelay;
    NSString *loopMode = _loopMode ?: @"none";
    double abLoopStart = _abLoopStart;
    double abLoopEnd = _abLoopEnd;
    NSString *aspectRatio = _aspectRatio ?: @"-1";
    NSInteger rotation = _rotation;
    NSInteger videoWidth = _videoWidth;
    NSInteger videoHeight = _videoHeight;
    uint64_t guardedLoadGeneration = _loadGeneration.load(std::memory_order_acquire);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isCurrentLoadGeneration:guardedLoadGeneration]) {
            return;
        }
        handler(
            currentTime,
            duration,
            playing,
            loaded,
            speed,
            volume,
            muted,
            subtitleDelay,
            audioDelay,
            loopMode,
            abLoopStart,
            abLoopEnd,
            aspectRatio,
            rotation,
            videoWidth,
            videoHeight,
            errorMessage
        );
    });
}

@end
#endif
