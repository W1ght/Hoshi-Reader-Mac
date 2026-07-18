#if HOSHI_VIDEO
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HSMpvStateHandler)(
    double currentTime,
    double duration,
    BOOL playing,
    BOOL loaded,
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
    NSInteger videoWidth,
    NSInteger videoHeight,
    NSString * _Nullable errorMessage
);
typedef void (^HSMpvVideoGeometryHandler)(
    double osdWidth,
    double osdHeight,
    double topMargin,
    double bottomMargin,
    double leftMargin,
    double rightMargin
);
typedef BOOL (^HSMpvCancellationHandler)(void);

@interface HSMpvTrackInfo : NSObject
@property (nonatomic, assign) NSInteger trackID;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *language;
@property (nonatomic, copy, nullable) NSString *codec;
@property (nonatomic, assign) NSInteger ffIndex;
@property (nonatomic, copy, nullable) NSString *externalFilename;
@property (nonatomic, assign, getter=isImage) BOOL image;
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@end

@interface HSExtractedSubtitleCue : NSObject
@property (nonatomic, assign) double startTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSData *rawPayload;
@property (nonatomic, assign) int64_t presentationTimestamp;
@property (nonatomic, assign) int64_t decodingTimestamp;
@property (nonatomic, assign) int64_t packetDuration;
@property (nonatomic, assign) NSInteger timeBaseNumerator;
@property (nonatomic, assign) NSInteger timeBaseDenominator;
@property (nonatomic, assign) NSInteger packetFlags;
@property (nonatomic, assign) int64_t filePosition;
@end

@interface HSExtractedSubtitleTrack : NSObject
@property (nonatomic, copy, nullable) NSData *codecPrivateData;
@property (nonatomic, copy) NSArray<HSExtractedSubtitleCue *> *packets;
@end

@interface HSSubtitleTrackExtractor : NSObject
+ (nullable HSExtractedSubtitleTrack *)extractTextSubtitleFromURL:(NSURL *)url
    streamIndex:(NSInteger)streamIndex
    isCancelled:(HSMpvCancellationHandler)isCancelled
    error:(NSError * _Nullable * _Nullable)error;
@end

@interface HSMpvAudioClipExporter : NSObject
+ (BOOL)exportAudioFromURL:(NSURL *)sourceURL
    toURL:(NSURL *)outputURL
    startTime:(double)startTime
    endTime:(double)endTime
    httpHeaders:(NSDictionary<NSString *, NSString *> *)httpHeaders
    audioTrackID:(nullable NSNumber *)audioTrackID
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
@end

@interface HSMpvThumbnailGenerator : NSObject
+ (nullable NSData *)thumbnailPNGDataForURL:(NSURL *)url
    maximumDimension:(NSInteger)maximumDimension
    time:(double)time
    isCancelled:(HSMpvCancellationHandler)isCancelled
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
@end

@interface HSMpvChapterInfo : NSObject
@property (nonatomic, assign) NSInteger chapterID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) double startTime;
@end

@interface HSMpvSubtitleCueInfo : NSObject
@property (nonatomic, copy) NSString *cueID;
@property (nonatomic, assign) double startTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, copy) NSString *text;
@end

@interface HSMpvOpenGLView : NSView
@property (nonatomic, copy, nullable) void (^onReady)(HSMpvOpenGLView *view);
@end

@interface HSMpvClient : NSObject

@property (nonatomic, copy, nullable) HSMpvStateHandler stateHandler;
@property (nonatomic, copy, nullable) HSMpvVideoGeometryHandler videoGeometryHandler;
@property (nonatomic, copy, nullable) void (^trackHandler)(NSArray<HSMpvTrackInfo *> *tracks);
@property (nonatomic, copy, nullable) void (^chapterHandler)(
    NSArray<HSMpvChapterInfo *> *chapters
);
@property (nonatomic, copy, nullable) void (^subtitleCueHandler)(
    NSArray<HSMpvSubtitleCueInfo *> *cues
);
@property (nonatomic, copy, nullable) void (^playbackEndedHandler)(void);
@property (nonatomic, copy, nullable) void (^remoteAudioStateHandler)(
    BOOL attached,
    NSString * _Nullable errorMessage
);

- (instancetype)init NS_UNAVAILABLE;
+ (nullable instancetype)makeClientWithErrorMessage:(NSString * _Nullable * _Nullable)errorMessage
    NS_SWIFT_NAME(make(errorMessage:));
- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)attachToView:(HSMpvOpenGLView *)view;
- (void)detachFromView;
- (void)loadFile:(NSURL *)url;
- (void)loadSourceURLString:(NSString *)urlString
    headers:(NSDictionary<NSString *, NSString *> *)headers
    audioURLString:(nullable NSString *)audioURLString
    audioHeaders:(NSDictionary<NSString *, NSString *> *)audioHeaders;
- (void)setPaused:(BOOL)paused;
- (void)seekTo:(double)seconds;
- (void)setSpeed:(double)speed;
- (void)setVolume:(double)volume;
- (void)setMuted:(BOOL)muted;
- (void)setSubtitleDelay:(double)delay;
- (void)setAudioDelay:(double)delay;
- (void)setLoopMode:(NSString *)mode;
- (void)setABLoopStart:(nullable NSNumber *)start end:(nullable NSNumber *)end;
- (void)setAspectRatio:(NSString *)aspectRatio;
- (void)setRotation:(NSInteger)degrees;
- (void)setHardwareDecodingEnabled:(BOOL)enabled;
- (void)setDeinterlacingEnabled:(BOOL)enabled;
- (void)setHDREnhancementEnabled:(BOOL)enabled;
- (BOOL)setVideoShaderURLs:(NSArray<NSURL *> *)shaderURLs
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
- (void)setVideoEqualizer:(NSString *)adjustment value:(double)value;
- (void)seekToChapter:(NSInteger)index;
- (void)captureAmbientPreviewWithMaximumDimension:(NSInteger)maximumDimension
    completion:(void (^)(NSImage * _Nullable image, NSInteger generation))completion;
- (BOOL)captureScreenshotToURL:(NSURL *)url
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
- (void)loadExternalSubtitle:(NSURL *)url;
- (void)selectTrackType:(NSString *)type trackID:(nullable NSNumber *)trackID;
- (void)setNativeSubtitleRenderingEnabled:(BOOL)enabled;
- (BOOL)installASSSubtitleEffectsFromURL:(NSURL *)url
    logicalTrackID:(nullable NSNumber *)logicalTrackID
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage
    NS_SWIFT_NAME(installASSSubtitleEffects(from:logicalTrackID:errorMessage:));
- (void)clearASSSubtitleEffects;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
#endif
