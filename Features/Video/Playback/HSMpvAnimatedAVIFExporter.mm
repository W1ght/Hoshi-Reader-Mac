#import "HSMpvAnimatedAVIFExporter.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#import <mpv/client.h>
#include <svt-av1/EbSvtAv1Enc.h>

extern "C" {
#include <libavcodec/codec_id.h>
#include <libavcodec/defs.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavutil/mathematics.h>
#include <libavutil/pixfmt.h>
}

namespace {

static NSString *const HSHoshiAnimatedAVIFErrorDomain =
    @"moe.shishamo.hoshi.video.animated-avif";

struct YUVFrame {
    std::vector<uint8_t> y;
    std::vector<uint8_t> u;
    std::vector<uint8_t> v;
};

struct CapturedYUVFrames {
    size_t width = 0;
    size_t height = 0;
    std::vector<std::unique_ptr<YUVFrame>> frames;
};

struct EncodedPacket {
    std::vector<uint8_t> data;
    int64_t pts = 0;
    int64_t dts = 0;
};

static NSString *HSError(NSString *message) {
    return [NSError errorWithDomain:HSHoshiAnimatedAVIFErrorDomain
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey: message}].localizedDescription;
}

static void SetError(NSString **errorMessage, NSString *message) {
    if (errorMessage) {
        *errorMessage = message;
    }
}

static NSString *StringForMPVError(int status, NSString *fallback) {
    const char *message = mpv_error_string(status);
    return message ? [NSString stringWithUTF8String:message] : fallback;
}

static BOOL SetMPVHTTPHeaders(
    mpv_handle *handle,
    NSDictionary<NSString *, NSString *> *headers,
    NSString **errorMessage
) {
    if (!handle || headers.count == 0) {
        return YES;
    }

    mpv_node_list list = {};
    list.num = (int)headers.count;
    list.values = (mpv_node *)calloc(headers.count, sizeof(mpv_node));
    if (!list.values) {
        SetError(errorMessage, HSError(@"Unable to allocate remote video headers."));
        return NO;
    }

    NSUInteger index = 0;
    for (NSString *key in headers) {
        NSString *field = [NSString stringWithFormat:@"%@: %@", key, headers[key]];
        list.values[index].format = MPV_FORMAT_STRING;
        list.values[index].u.string = strdup(field.UTF8String);
        index += 1;
    }

    mpv_node node = {};
    node.format = MPV_FORMAT_NODE_ARRAY;
    node.u.list = &list;
    int status = mpv_set_option(handle, "http-header-fields", MPV_FORMAT_NODE, &node);
    for (int item = 0; item < list.num; item++) {
        free(list.values[item].u.string);
    }
    free(list.values);

    if (status < 0) {
        SetError(
            errorMessage,
            [NSString stringWithFormat:@"The animated AVIF capture rejected HTTP headers: %@",
                StringForMPVError(status, @"unknown error")]
        );
        return NO;
    }
    return YES;
}

static BOOL SetMPVOption(
    mpv_handle *handle,
    NSString *name,
    NSString *value,
    NSString **errorMessage
) {
    int status = mpv_set_option_string(handle, name.UTF8String, value.UTF8String);
    if (status < 0) {
        SetError(
            errorMessage,
            [NSString stringWithFormat:@"The animated AVIF capture rejected %@: %@",
                name,
                StringForMPVError(status, @"unknown error")]
        );
        return NO;
    }
    return YES;
}

static NSURL *CreateTemporaryDirectory(NSString **errorMessage) {
    NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    directory = [directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"hoshi-video-avif-%@", NSUUID.UUID.UUIDString]
        isDirectory:YES];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:&error]) {
        SetError(errorMessage, error.localizedDescription ?: HSError(@"Unable to create the AVIF frame directory."));
        return nil;
    }
    return directory;
}

static std::unique_ptr<CapturedYUVFrames> ParseRawFrames(
    NSData *data,
    size_t width,
    size_t height,
    NSString **errorMessage
) {
    if (!data || width < 64 || height < 64 || width % 2 != 0 || height % 2 != 0) {
        SetError(errorMessage, HSError(@"The animated AVIF YUV frames have unsupported dimensions or color format."));
        return nullptr;
    }
    // mpv writes 10-bit little-endian 4:2:0 planes back to back: luma is 2 bytes
    // per sample, each chroma plane is a quarter of the luma sample count and
    // also 2 bytes per sample.
    const size_t lumaBytes = width * height * 2;
    const size_t chromaBytes = (width / 2) * (height / 2) * 2;
    const size_t frameBytes = lumaBytes + chromaBytes * 2;
    const uint8_t *bytes = static_cast<const uint8_t *>(data.bytes);
    const size_t length = data.length;
    if (length == 0 || length % frameBytes != 0) {
        SetError(errorMessage, HSError(@"The animated AVIF capture produced an incomplete raw YUV frame."));
        return nullptr;
    }

    auto capture = std::make_unique<CapturedYUVFrames>();
    capture->width = width;
    capture->height = height;
    size_t offset = 0;
    while (offset + frameBytes <= length) {
        auto frame = std::make_unique<YUVFrame>();
        frame->y.assign(bytes + offset, bytes + offset + lumaBytes);
        offset += lumaBytes;
        frame->u.assign(bytes + offset, bytes + offset + chromaBytes);
        offset += chromaBytes;
        frame->v.assign(bytes + offset, bytes + offset + chromaBytes);
        offset += chromaBytes;
        capture->frames.push_back(std::move(frame));
    }

    if (capture->frames.empty()) {
        SetError(errorMessage, HSError(@"The animated AVIF capture produced no video frames."));
        return nullptr;
    }
    if (capture->frames.size() == 1) {
        capture->frames.push_back(std::make_unique<YUVFrame>(*capture->frames.front()));
    }
    return capture;
}

static std::unique_ptr<CapturedYUVFrames> CaptureYUVFrames(
    NSURL *sourceURL,
    NSDictionary<NSString *, NSString *> *headers,
    double startTime,
    double endTime,
    NSInteger fps,
    NSInteger maximumHeight,
    NSString **errorMessage
) {
    if (!sourceURL || endTime <= startTime || fps <= 0) {
        SetError(errorMessage, HSError(@"Unable to determine the animated AVIF video range."));
        return nullptr;
    }

    NSURL *directory = CreateTemporaryDirectory(errorMessage);
    if (!directory) {
        return nullptr;
    }

    NSURL *outputURL = [directory URLByAppendingPathComponent:@"frames.raw"];

    mpv_handle *capture = mpv_create();
    if (!capture) {
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        SetError(errorMessage, HSError(@"The bundled animated AVIF frame capturer is unavailable."));
        return nullptr;
    }

    BOOL configured = YES;
    configured = configured && SetMPVOption(capture, @"config", @"no", errorMessage);
    configured = configured && SetMPVOption(capture, @"audio", @"no", errorMessage);
    configured = configured && SetMPVOption(capture, @"sid", @"no", errorMessage);
    configured = configured && SetMPVOption(capture, @"sub-visibility", @"no", errorMessage);
    configured = configured && SetMPVOption(capture, @"o", outputURL.path, errorMessage);
    // Raw 10-bit YUV420 (not yuv4mpegpipe): the y4m muxer only officially
    // accepts 8-bit formats and rejects 10-bit HEVC sources, so stream the
    // scaled frames straight to the encoder as yuv420p10le instead.
    configured = configured && SetMPVOption(capture, @"of", @"rawvideo", errorMessage);
    configured = configured && SetMPVOption(capture, @"ovc", @"rawvideo", errorMessage);
    NSString *scaleFilter = [NSString stringWithFormat:
        @"fps=%ld,lavfi=[scale=w='trunc(min(%ld,ih)*dar/2+0.5)*2'"
         ":h='min(%ld,ih)':flags=lanczos+accurate_rnd,setsar=1,format=yuv420p10le]",
        (long)fps,
        (long)maximumHeight,
        (long)maximumHeight];
    configured = configured && SetMPVOption(
        capture,
        @"vf",
        scaleFilter,
        errorMessage
    );
    NSInteger frameLimit = MAX(2, (NSInteger)ceil((endTime - startTime) * fps) + 1);
    configured = configured && SetMPVOption(capture, @"frames", @(frameLimit).stringValue, errorMessage);
    configured = configured && SetMPVOption(
        capture,
        @"start",
        [NSString stringWithFormat:@"%.6f", MAX(0, startTime)],
        errorMessage
    );
    configured = configured && SetMPVOption(
        capture,
        @"end",
        [NSString stringWithFormat:@"%.6f", MAX(startTime, endTime)],
        errorMessage
    );
    configured = configured && SetMPVOption(capture, @"keep-open", @"no", errorMessage);
    configured = configured && SetMPVOption(capture, @"loop-file", @"no", errorMessage);
    configured = configured && SetMPVHTTPHeaders(capture, headers, errorMessage);

    if (!configured) {
        mpv_terminate_destroy(capture);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        return nullptr;
    }

    int status = mpv_initialize(capture);
    if (status < 0) {
        SetError(
            errorMessage,
            [NSString stringWithFormat:@"The animated AVIF frame capturer could not start: %@",
                StringForMPVError(status, @"unknown error")]
        );
        mpv_terminate_destroy(capture);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        return nullptr;
    }

    const char *source = sourceURL.isFileURL
        ? sourceURL.fileSystemRepresentation
        : sourceURL.absoluteString.UTF8String;
    const char *loadCommand[] = {"loadfile", source, "replace", NULL};
    status = mpv_command(capture, loadCommand);
    if (status < 0) {
        SetError(
            errorMessage,
            [NSString stringWithFormat:@"The video could not be opened for animated AVIF capture: %@",
                StringForMPVError(status, @"unknown error")]
        );
        mpv_terminate_destroy(capture);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        return nullptr;
    }

    // Rawvideo carries no header, so derive the scaled frame size from the
    // source video parameters using the same expression as the vf filter. The
    // first decoded frame populates these before the encode can finish.
    size_t sourceHeight = 0;
    double sourceDAR = 1.0;
    NSDate *paramsDeadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (sourceHeight == 0 && paramsDeadline.timeIntervalSinceNow > 0) {
        mpv_wait_event(capture, 0.05);
        int64_t height = 0;
        if (mpv_get_property(capture, "video-params/h", MPV_FORMAT_INT64, &height) >= 0 && height > 0) {
            sourceHeight = (size_t)height;
            double aspect = 1.0;
            if (mpv_get_property(capture, "video-params/aspect", MPV_FORMAT_DOUBLE, &aspect) >= 0
                && aspect > 0) {
                sourceDAR = aspect;
            } else {
                int64_t width = 0;
                if (mpv_get_property(capture, "video-params/w", MPV_FORMAT_INT64, &width) >= 0 && width > 0) {
                    sourceDAR = (double)width / (double)height;
                }
            }
        }
    }
    if (sourceHeight == 0) {
        SetError(errorMessage, HSError(@"The animated AVIF frame capturer could not determine the video size."));
        mpv_terminate_destroy(capture);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        return nullptr;
    }

    BOOL completed = NO;
    NSString *failure = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    while (!completed && deadline.timeIntervalSinceNow > 0) {
        mpv_event *event = mpv_wait_event(capture, 0.25);
        if (!event || event->event_id == MPV_EVENT_NONE) {
            continue;
        }
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *endFile = (mpv_event_end_file *)event->data;
            if (endFile && endFile->error < 0) {
                failure = [NSString stringWithFormat:
                    @"The animated AVIF video frames could not be rendered: %@",
                    StringForMPVError(endFile->error, @"unknown error")];
            }
            completed = YES;
        } else if (event->event_id == MPV_EVENT_SHUTDOWN) {
            failure = HSError(@"The animated AVIF frame capturer stopped unexpectedly.");
            completed = YES;
        }
    }
    if (!completed) {
        failure = HSError(@"The animated AVIF frame capture timed out.");
    }
    mpv_terminate_destroy(capture);

    if (failure) {
        SetError(errorMessage, failure);
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        return nullptr;
    }

    NSData *data = [NSData dataWithContentsOfURL:outputURL];
    [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
    if (data.length == 0) {
        SetError(errorMessage, HSError(@"The animated AVIF capture produced no YUV video frames."));
        return nullptr;
    }
    const size_t height = MIN((int64_t)maximumHeight, (int64_t)sourceHeight);
    const size_t width = (size_t)((int64_t)trunc((double)height * sourceDAR / 2.0 + 0.5) * 2);
    return ParseRawFrames(data, width, height, errorMessage);
}

template <typename Function>
static Function ResolveFunction(void *handle, const char *name) {
    return reinterpret_cast<Function>(dlsym(handle, name));
}

struct SvtAPI {
    void *handle = nullptr;
    using InitHandle = EbErrorType (*)(EbComponentType **, EbSvtAv1EncConfiguration *);
    using SetParameter = EbErrorType (*)(EbComponentType *, EbSvtAv1EncConfiguration *);
    using Init = EbErrorType (*)(EbComponentType *);
    using StreamHeader = EbErrorType (*)(EbComponentType *, EbBufferHeaderType **);
    using StreamHeaderRelease = EbErrorType (*)(EbBufferHeaderType *);
    using SendPicture = EbErrorType (*)(EbComponentType *, EbBufferHeaderType *);
    using GetPacket = EbErrorType (*)(EbComponentType *, EbBufferHeaderType **, uint8_t);
    using ReleaseOutput = void (*)(EbBufferHeaderType **);
    using Deinit = EbErrorType (*)(EbComponentType *);
    using DeinitHandle = EbErrorType (*)(EbComponentType *);

    InitHandle initHandle = nullptr;
    SetParameter setParameter = nullptr;
    Init init = nullptr;
    StreamHeader streamHeader = nullptr;
    StreamHeaderRelease streamHeaderRelease = nullptr;
    SendPicture sendPicture = nullptr;
    GetPacket getPacket = nullptr;
    ReleaseOutput releaseOutput = nullptr;
    Deinit deinit = nullptr;
    DeinitHandle deinitHandle = nullptr;

    BOOL load(NSString **errorMessage) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath;
        if (frameworks.length > 0) {
            [paths addObject:[frameworks stringByAppendingPathComponent:@"libSvtAv1Enc.4.dylib"]];
        }
        [paths addObject:@"@rpath/libSvtAv1Enc.4.dylib"];
        for (NSString *path in paths) {
            handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
            if (handle) {
                break;
            }
        }
        if (!handle) {
            SetError(errorMessage, HSError(@"The bundled SVT-AV1 encoder is unavailable."));
            return NO;
        }
        initHandle = ResolveFunction<InitHandle>(handle, "svt_av1_enc_init_handle");
        setParameter = ResolveFunction<SetParameter>(handle, "svt_av1_enc_set_parameter");
        init = ResolveFunction<Init>(handle, "svt_av1_enc_init");
        streamHeader = ResolveFunction<StreamHeader>(handle, "svt_av1_enc_stream_header");
        streamHeaderRelease = ResolveFunction<StreamHeaderRelease>(handle, "svt_av1_enc_stream_header_release");
        sendPicture = ResolveFunction<SendPicture>(handle, "svt_av1_enc_send_picture");
        getPacket = ResolveFunction<GetPacket>(handle, "svt_av1_enc_get_packet");
        releaseOutput = ResolveFunction<ReleaseOutput>(handle, "svt_av1_enc_release_out_buffer");
        deinit = ResolveFunction<Deinit>(handle, "svt_av1_enc_deinit");
        deinitHandle = ResolveFunction<DeinitHandle>(handle, "svt_av1_enc_deinit_handle");
        if (!initHandle || !setParameter || !init || !streamHeader || !streamHeaderRelease
            || !sendPicture || !getPacket || !releaseOutput || !deinit || !deinitHandle) {
            SetError(errorMessage, HSError(@"The bundled SVT-AV1 encoder has an incompatible API."));
            dlclose(handle);
            handle = nullptr;
            return NO;
        }
        return YES;
    }

    void shutdown(EbComponentType *encoder) {
        if (!encoder) {
            return;
        }
        deinit(encoder);
        deinitHandle(encoder);
    }

    ~SvtAPI() {
        if (handle) {
            dlclose(handle);
        }
    }
};

struct FFmpegAPI {
    using AllocOutputContext = int (*)(AVFormatContext **, const AVOutputFormat *, const char *, const char *);
    using NewStream = AVStream *(*)(AVFormatContext *, const AVCodec *);
    using WriteHeader = int (*)(AVFormatContext *, AVDictionary **);
    using WriteFrame = int (*)(AVFormatContext *, AVPacket *);
    using WriteTrailer = int (*)(AVFormatContext *);
    using FreeContext = void (*)(AVFormatContext *);
    using IOOpen = int (*)(AVIOContext **, const char *, int);
    using IOClose = int (*)(AVIOContext **);
    using Malloc = void *(*)(size_t);
    using RescaleQ = int64_t (*)(int64_t, AVRational, AVRational);

    AllocOutputContext allocOutputContext = nullptr;
    NewStream newStream = nullptr;
    WriteHeader writeHeader = nullptr;
    WriteFrame writeFrame = nullptr;
    WriteTrailer writeTrailer = nullptr;
    FreeContext freeContext = nullptr;
    IOOpen ioOpen = nullptr;
    IOClose ioClose = nullptr;
    Malloc avMalloc = nullptr;
    RescaleQ rescaleQ = nullptr;

    BOOL load(NSString **errorMessage) {
        allocOutputContext = ResolveFunction<AllocOutputContext>(RTLD_DEFAULT, "avformat_alloc_output_context2");
        newStream = ResolveFunction<NewStream>(RTLD_DEFAULT, "avformat_new_stream");
        writeHeader = ResolveFunction<WriteHeader>(RTLD_DEFAULT, "avformat_write_header");
        writeFrame = ResolveFunction<WriteFrame>(RTLD_DEFAULT, "av_write_frame");
        writeTrailer = ResolveFunction<WriteTrailer>(RTLD_DEFAULT, "av_write_trailer");
        freeContext = ResolveFunction<FreeContext>(RTLD_DEFAULT, "avformat_free_context");
        ioOpen = ResolveFunction<IOOpen>(RTLD_DEFAULT, "avio_open");
        ioClose = ResolveFunction<IOClose>(RTLD_DEFAULT, "avio_closep");
        avMalloc = ResolveFunction<Malloc>(RTLD_DEFAULT, "av_malloc");
        rescaleQ = ResolveFunction<RescaleQ>(RTLD_DEFAULT, "av_rescale_q");
        if (!allocOutputContext || !newStream || !writeHeader || !writeFrame || !writeTrailer
            || !freeContext || !ioOpen || !ioClose || !avMalloc || !rescaleQ) {
            SetError(errorMessage, HSError(@"The bundled FFmpeg AVIF muxer is unavailable."));
            return NO;
        }
        return YES;
    }
};

static BOOL EncodeAVIF(
    std::unique_ptr<CapturedYUVFrames> capture,
    NSInteger fps,
    double quality,
    NSURL *outputURL,
    NSString **errorMessage
) {
    SvtAPI svt;
    if (!svt.load(errorMessage)) {
        return NO;
    }
    FFmpegAPI ffmpeg;
    if (!ffmpeg.load(errorMessage)) {
        return NO;
    }

    if (!capture || capture->frames.size() < 2) {
        SetError(errorMessage, HSError(@"The animated AVIF frames are too small or incomplete."));
        return NO;
    }
    const size_t width = capture->width;
    const size_t height = capture->height;
    std::vector<std::unique_ptr<YUVFrame>> &frames = capture->frames;

    EbComponentType *encoder = nullptr;
    EbSvtAv1EncConfiguration configuration = {};
    EbErrorType status = svt.initHandle(&encoder, &configuration);
    if (status != EB_ErrorNone) {
        SetError(errorMessage, [NSString stringWithFormat:@"SVT-AV1 could not initialize (%d).", status]);
        return NO;
    }
    configuration.source_width = (uint32_t)width;
    configuration.source_height = (uint32_t)height;
    configuration.frame_rate_numerator = (uint32_t)fps;
    configuration.frame_rate_denominator = 1;
    // The raw capture layer normalizes every source to 10-bit little-endian
    // YUV420, so the encoder preserves the 10-bit depth of HEVC/x265 sources
    // instead of banding them down to 8-bit.
    configuration.encoder_bit_depth = 10;
    configuration.encoder_color_format = EB_YUV420;
    // Preset M6 balances encode time with rate-distortion efficiency; at the
    // mining card size it is still fast while producing smaller, sharper files
    // than the default M8 at the same CRF.
    configuration.enc_mode = ENC_M6;
    configuration.pred_structure = 1;
    configuration.intra_period_length = -1;
    configuration.rate_control_mode = SVT_AV1_RC_MODE_CQP_OR_CRF;
    configuration.qp = (uint32_t)MIN(63.0, MAX(0.0, floor((1.0 - quality) * 63.0)));
    configuration.avif = false;

    status = svt.setParameter(encoder, &configuration);
    if (status == EB_ErrorNone) {
        status = svt.init(encoder);
    }
    if (status != EB_ErrorNone) {
        svt.shutdown(encoder);
        SetError(errorMessage, [NSString stringWithFormat:@"SVT-AV1 could not start (%d).", status]);
        return NO;
    }

    EbBufferHeaderType *sequenceHeader = nullptr;
    status = svt.streamHeader(encoder, &sequenceHeader);
    if (status != EB_ErrorNone || !sequenceHeader || sequenceHeader->n_filled_len == 0) {
        svt.shutdown(encoder);
        SetError(errorMessage, HSError(@"SVT-AV1 did not provide an AV1 sequence header."));
        return NO;
    }

    std::vector<EncodedPacket> packets;
    EbErrorType outputStatus = EB_ErrorNone;
    BOOL outputSucceeded = YES;
    std::thread outputThread([&] {
        while (true) {
            EbBufferHeaderType *output = nullptr;
            EbErrorType packetStatus = svt.getPacket(encoder, &output, 0);
            if (packetStatus == EB_NoErrorEmptyQueue) {
                continue;
            }
            if (packetStatus != EB_ErrorNone || !output) {
                outputStatus = packetStatus;
                outputSucceeded = NO;
                break;
            }
            if (output->flags & EB_BUFFERFLAG_EOS) {
                svt.releaseOutput(&output);
                break;
            }
            if (output->n_filled_len > 0 && output->p_buffer) {
                EncodedPacket packet;
                packet.data.assign(output->p_buffer, output->p_buffer + output->n_filled_len);
                packet.pts = output->pts >= 0 ? output->pts : (int64_t)packets.size();
                packet.dts = output->dts >= 0 ? output->dts : packet.pts;
                packets.push_back(std::move(packet));
            }
            svt.releaseOutput(&output);
        }
    });

    BOOL inputSucceeded = YES;
    EbErrorType inputStatus = EB_ErrorNone;
    for (size_t index = 0; index < frames.size(); index++) {
        EbSvtIOFormat *input = (EbSvtIOFormat *)calloc(1, sizeof(EbSvtIOFormat));
        if (!input) {
            inputSucceeded = NO;
            inputStatus = EB_ErrorInsufficientResources;
            break;
        }
        input->luma = frames[index]->y.data();
        input->cb = frames[index]->u.data();
        input->cr = frames[index]->v.data();
        input->y_stride = (uint32_t)width;
        input->cb_stride = (uint32_t)(width / 2);
        input->cr_stride = (uint32_t)(width / 2);

        EbBufferHeaderType picture = {};
        picture.size = sizeof(picture);
        picture.p_buffer = (uint8_t *)input;
        // 10-bit 4:2:0: 2 bytes per luma sample plus 1 byte per pixel of chroma
        // (two quarter-size planes at 2 bytes per sample) = 3 bytes per pixel.
        picture.n_filled_len = (uint32_t)(width * height * 3);
        picture.n_alloc_len = picture.n_filled_len;
        picture.pts = (int64_t)index;
        picture.dts = (int64_t)index;
        picture.pic_type = EB_AV1_INVALID_PICTURE;
        inputStatus = svt.sendPicture(encoder, &picture);
        free(input);
        if (inputStatus != EB_ErrorNone) {
            inputSucceeded = NO;
            break;
        }
    }

    EbBufferHeaderType eos = {};
    eos.size = sizeof(eos);
    eos.flags = EB_BUFFERFLAG_EOS;
    EbErrorType eosStatus = svt.sendPicture(encoder, &eos);
    if (inputSucceeded && eosStatus != EB_ErrorNone) {
        inputSucceeded = NO;
        inputStatus = eosStatus;
    }
    outputThread.join();

    if (!inputSucceeded) {
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, [NSString stringWithFormat:@"SVT-AV1 rejected the input (%d).", inputStatus]);
        return NO;
    }
    if (!outputSucceeded) {
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, [NSString stringWithFormat:@"SVT-AV1 failed to encode (%d).", outputStatus]);
        return NO;
    }

    AVFormatContext *format = nullptr;
    status = (EbErrorType)ffmpeg.allocOutputContext(
        &format,
        nullptr,
        "avif",
        outputURL.fileSystemRepresentation
    );
    if (status < 0 || !format) {
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, @"The bundled FFmpeg AVIF muxer could not be created.");
        return NO;
    }

    AVStream *stream = ffmpeg.newStream(format, nullptr);
    if (!stream) {
        ffmpeg.freeContext(format);
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, @"The bundled FFmpeg AVIF muxer could not create a video stream.");
        return NO;
    }
    stream->time_base = AVRational{1, (int)fps};
    stream->avg_frame_rate = AVRational{(int)fps, 1};
    stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
    stream->codecpar->codec_id = AV_CODEC_ID_AV1;
    stream->codecpar->width = (int)width;
    stream->codecpar->height = (int)height;
    stream->codecpar->format = AV_PIX_FMT_YUV420P10LE;
    stream->codecpar->extradata = (uint8_t *)ffmpeg.avMalloc(
        sequenceHeader->n_filled_len + AV_INPUT_BUFFER_PADDING_SIZE
    );
    stream->codecpar->extradata_size = (int)sequenceHeader->n_filled_len;
    if (!stream->codecpar->extradata) {
        ffmpeg.freeContext(format);
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, @"The bundled FFmpeg AVIF muxer could not allocate codec metadata.");
        return NO;
    }
    memcpy(stream->codecpar->extradata, sequenceHeader->p_buffer, sequenceHeader->n_filled_len);
    memset(
        stream->codecpar->extradata + sequenceHeader->n_filled_len,
        0,
        AV_INPUT_BUFFER_PADDING_SIZE
    );

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    int ioStatus = ffmpeg.ioOpen(&format->pb, outputURL.fileSystemRepresentation, AVIO_FLAG_WRITE);
    if (ioStatus < 0 || ffmpeg.writeHeader(format, nullptr) < 0) {
        if (format->pb) {
            ffmpeg.ioClose(&format->pb);
        }
        ffmpeg.freeContext(format);
        svt.streamHeaderRelease(sequenceHeader);
        svt.shutdown(encoder);
        SetError(errorMessage, @"The bundled FFmpeg AVIF muxer could not open the output file.");
        return NO;
    }

    BOOL writeSucceeded = YES;
    for (const EncodedPacket &encoded : packets) {
        AVPacket packet = {};
        packet.data = const_cast<uint8_t *>(encoded.data.data());
        packet.size = (int)encoded.data.size();
        packet.pts = ffmpeg.rescaleQ(encoded.pts, AVRational{1, (int)fps}, stream->time_base);
        packet.dts = ffmpeg.rescaleQ(encoded.dts, AVRational{1, (int)fps}, stream->time_base);
        packet.duration = ffmpeg.rescaleQ(1, AVRational{1, (int)fps}, stream->time_base);
        packet.stream_index = stream->index;
        packet.time_base = stream->time_base;
        if (ffmpeg.writeFrame(format, &packet) < 0) {
            writeSucceeded = NO;
            break;
        }
    }
    if (writeSucceeded) {
        writeSucceeded = ffmpeg.writeTrailer(format) >= 0;
    }
    if (format->pb) {
        ffmpeg.ioClose(&format->pb);
    }
    ffmpeg.freeContext(format);
    svt.streamHeaderRelease(sequenceHeader);
    svt.shutdown(encoder);

    if (!writeSucceeded) {
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        SetError(errorMessage, @"The bundled FFmpeg AVIF muxer failed while writing the animation.");
        return NO;
    }
    return YES;
}

} // namespace

@implementation HSMpvAnimatedAVIFExporter

+ (BOOL)exportAnimatedAVIFFromURL:(NSURL *)sourceURL
    headers:(NSDictionary<NSString *, NSString *> *)headers
    startTime:(double)startTime
    endTime:(double)endTime
    fps:(NSInteger)fps
    maximumHeight:(NSInteger)maximumHeight
    quality:(double)quality
    toURL:(NSURL *)outputURL
    errorMessage:(NSString **)errorMessage {
    if (!outputURL.isFileURL || endTime <= startTime) {
        SetError(errorMessage, HSError(@"Unable to determine the animated AVIF video range."));
        return NO;
    }
    fps = MAX(1, MIN(30, fps));
    maximumHeight = MAX(64, maximumHeight);
    quality = MIN(1.0, MAX(0.0, quality));

    NSString *captureError = nil;
    std::unique_ptr<CapturedYUVFrames> frames = CaptureYUVFrames(
        sourceURL,
        headers ?: @{},
        startTime,
        endTime,
        fps,
        maximumHeight,
        &captureError
    );
    if (!frames) {
        SetError(errorMessage, captureError ?: HSError(@"The animated AVIF frame capture failed."));
        return NO;
    }
    return EncodeAVIF(
        std::move(frames),
        fps,
        quality,
        outputURL,
        errorMessage
    );
}

@end
