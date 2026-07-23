import Foundation

struct VideoAudioClipRange: Equatable {
    let start: TimeInterval
    let end: TimeInterval

    static func resolve(
        cueStart: TimeInterval,
        cueEnd: TimeInterval,
        subtitleDelay: TimeInterval,
        duration: TimeInterval,
        padding: TimeInterval = 0.12
    ) -> VideoAudioClipRange? {
        let paddedStart = max(0, cueStart + subtitleDelay - padding)
        var paddedEnd = cueEnd + subtitleDelay + padding
        if duration > 0 {
            paddedEnd = min(duration, paddedEnd)
        }
        guard paddedEnd > paddedStart else { return nil }
        return VideoAudioClipRange(start: paddedStart, end: paddedEnd)
    }
}
