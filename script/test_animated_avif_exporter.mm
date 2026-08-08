#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "HSMpvAnimatedAVIFExporter.h"

namespace {

struct AnimationInfo {
    NSInteger width = 0;
    NSInteger height = 0;
    size_t frameCount = 0;
};

static BOOL InspectAnimation(NSURL *url, AnimationInfo *info) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
    if (!source) {
        return NO;
    }
    size_t frameCount = CGImageSourceGetCount(source);
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil);
    NSDictionary *values = CFBridgingRelease(properties);
    AnimationInfo result;
    result.width = [values[(NSString *)kCGImagePropertyPixelWidth] integerValue];
    result.height = [values[(NSString *)kCGImagePropertyPixelHeight] integerValue];
    result.frameCount = frameCount;
    CFRelease(source);
    if (result.width < 64 || result.height < 64
        || result.width % 2 != 0 || result.height % 2 != 0
        || result.frameCount < 2 || result.frameCount > 151) {
        return NO;
    }
    if (info) {
        *info = result;
    }
    return YES;
}

static BOOL Export(
    NSURL *sourceURL,
    NSURL *outputURL,
    NSInteger rotation,
    double endTime,
    AnimationInfo *info
) {
    NSString *errorMessage = nil;
    BOOL succeeded = [HSMpvAnimatedAVIFExporter
        exportAnimatedAVIFFromURL:sourceURL
        headers:@{}
        startTime:0
        endTime:endTime
        fps:10
        maximumHeight:350
        rotation:rotation
        quality:0.75
        toURL:outputURL
        errorMessage:&errorMessage];
    if (!succeeded) {
        fprintf(stderr, "AVIF export failed: %s\n", errorMessage.UTF8String ?: "unknown error");
        return NO;
    }
    if (!InspectAnimation(outputURL, info)) {
        fputs("AVIF output is not a readable, bounded even-sized animation\n", stderr);
        return NO;
    }
    return YES;
}

static NSURL *CreateY4M(
    NSURL *directory,
    NSString *name,
    NSInteger width,
    NSInteger height,
    NSInteger frameCount
) {
    NSURL *url = [directory URLByAppendingPathComponent:name];
    NSMutableData *data = [NSMutableData data];
    NSString *header = [NSString stringWithFormat:
        @"YUV4MPEG2 W%ld H%ld F10:1 Ip A1:1 C444\n",
        (long)width,
        (long)height];
    [data appendData:[header dataUsingEncoding:NSASCIIStringEncoding]];
    NSMutableData *frame = [NSMutableData dataWithLength:(NSUInteger)(width * height * 3)];
    uint8_t *bytes = static_cast<uint8_t *>(frame.mutableBytes);
    memset(bytes, 96, (size_t)(width * height));
    memset(bytes + width * height, 128, (size_t)(width * height * 2));
    NSData *frameHeader = [@"FRAME\n" dataUsingEncoding:NSASCIIStringEncoding];
    for (NSInteger index = 0; index < frameCount; index++) {
        [data appendData:frameHeader];
        [data appendData:frame];
    }
    NSError *error = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        fprintf(stderr, "fixture write failed: %s\n", error.localizedDescription.UTF8String);
        return nil;
    }
    return url;
}

static int RunSelfTest(void) {
    NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    directory = [directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"niratan-avif-test-%@", NSUUID.UUID.UUIDString]
        isDirectory:YES];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error]) {
        fprintf(stderr, "test directory creation failed: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    @try {
        NSURL *oddSource = CreateY4M(directory, @"odd.y4m", 320, 241, 10);
        AnimationInfo odd;
        if (!oddSource || !Export(
                oddSource,
                [directory URLByAppendingPathComponent:@"odd.avif"],
                0,
                1,
                &odd
            )) {
            return 1;
        }
        AnimationInfo rotated;
        if (!Export(
                oddSource,
                [directory URLByAppendingPathComponent:@"rotated.avif"],
                90,
                1,
                &rotated
            ) || rotated.height <= rotated.width) {
            fputs("AVIF rotation did not produce portrait output\n", stderr);
            return 1;
        }

        NSURL *longSource = CreateY4M(directory, @"long.y4m", 64, 64, 200);
        AnimationInfo bounded;
        if (!longSource || !Export(
                longSource,
                [directory URLByAppendingPathComponent:@"bounded.avif"],
                0,
                20,
                &bounded
            ) || bounded.frameCount != 150) {
            fprintf(stderr, "AVIF duration cap produced %zu frames instead of 150\n", bounded.frameCount);
            return 1;
        }
        printf(
            "Animated AVIF exporter self-test passed: odd=%ldx%ld, rotated=%ldx%ld, bounded=%zu frames\n",
            (long)odd.width,
            (long)odd.height,
            (long)rotated.width,
            (long)rotated.height,
            bounded.frameCount
        );
        return 0;
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
    }
}

} // namespace

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
            return RunSelfTest();
        }
        if (argc != 4 && argc != 5) {
            fputs("usage: test_animated_avif_exporter <source> <output> <rotation> [end-time]\n", stderr);
            return 2;
        }
        NSURL *sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        NSInteger rotation = [[NSString stringWithUTF8String:argv[3]] integerValue];
        double endTime = argc == 5
            ? [[NSString stringWithUTF8String:argv[4]] doubleValue]
            : 0.5;
        AnimationInfo info;
        if (!Export(sourceURL, outputURL, rotation, endTime, &info)) {
            return 1;
        }
        printf(
            "Animated AVIF exporter test passed: %ldx%ld, %zu frames\n",
            (long)info.width,
            (long)info.height,
            info.frameCount
        );
    }
    return 0;
}
