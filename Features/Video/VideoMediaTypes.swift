#if HOSHI_VIDEO
import Foundation
import UniformTypeIdentifiers

enum VideoMediaTypes {
    static let supportedExtensions: Set<String> = [
        "mkv", "webm", "avi", "m4v", "mp4", "mov", "qt",
        "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "ogv",
        "wmv", "asf", "flv",
        "m4b", "m4a", "mp3", "flac", "opus", "ogg", "oga",
        "weba", "wav", "aac", "aiff", "aif", "ape", "wv",
    ]

    static let contentTypes: [UTType] = {
        var types: [UTType] = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie]
        for fileExtension in supportedExtensions {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()

    static func isMediaFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
#endif
