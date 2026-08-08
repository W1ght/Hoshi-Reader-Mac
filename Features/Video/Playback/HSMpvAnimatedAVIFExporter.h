#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HSMpvAnimatedAVIFExporter : NSObject

+ (BOOL)exportAnimatedAVIFFromURL:(NSURL *)sourceURL
    headers:(NSDictionary<NSString *, NSString *> *)headers
    startTime:(double)startTime
    endTime:(double)endTime
    fps:(NSInteger)fps
    maximumHeight:(NSInteger)maximumHeight
    rotation:(NSInteger)rotation
    quality:(double)quality
    toURL:(NSURL *)outputURL
    errorMessage:(NSString * _Nullable * _Nullable)errorMessage
    NS_SWIFT_NAME(exportAnimatedAVIF(from:headers:startTime:endTime:fps:maximumHeight:rotation:quality:to:errorMessage:));

@end

NS_ASSUME_NONNULL_END
