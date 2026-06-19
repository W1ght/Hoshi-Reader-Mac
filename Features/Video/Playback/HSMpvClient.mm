#if HOSHI_VIDEO
#import "HSMpvClient.h"

#define GL_SILENCE_DEPRECATION
#import <OpenGL/gl.h>
#import <mpv/client.h>
#import <mpv/render_gl.h>

static NSString * const HSMpvErrorDomain = @"moe.shishamo.hoshi.video.mpv";

@implementation HSMpvTrackInfo
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
    double _lastSubtitleRefreshTime;
    NSUInteger _subtitleCueSignature;
    NSUInteger _subtitleCueCount;
    NSMutableArray<HSMpvSubtitleCueInfo *> *_fallbackSubtitleCues;
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
    _currentTime = 0;
    _duration = 0;
    _loaded = NO;
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

- (void)seekToChapter:(NSInteger)index {
    if (!_handle || _shuttingDown) {
        return;
    }
    int64_t value = (int64_t)index;
    mpv_set_property(_handle, "chapter", MPV_FORMAT_INT64, &value);
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
    mpv_set_property_string(_handle, "sub-visibility", "yes");
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
        mpv_set_property_string(_handle, "sub-visibility", "yes");
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
                    dispatch_async(dispatch_get_main_queue(), handler);
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
        dispatch_async(dispatch_get_main_queue(), ^{
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
    void (^handler)(NSArray<HSMpvTrackInfo *> *) = self.trackHandler;
    if (handler) {
        NSArray<HSMpvTrackInfo *> *snapshot = tracks.copy;
        dispatch_async(dispatch_get_main_queue(), ^{
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
            cues.count > 0 ? "no" : "yes"
        );
    }
    void (^handler)(NSArray<HSMpvSubtitleCueInfo *> *) = self.subtitleCueHandler;
    if (handler) {
        NSArray<HSMpvSubtitleCueInfo *> *snapshot = cues.copy;
        dispatch_async(dispatch_get_main_queue(), ^{
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
    dispatch_async(dispatch_get_main_queue(), ^{
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
            errorMessage
        );
    });
}

@end
#endif
