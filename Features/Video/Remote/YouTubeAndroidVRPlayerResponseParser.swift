import Foundation

nonisolated enum YouTubeAndroidVRPlayerResponseParser {
    static func parse(
        data: Data
    ) throws -> YouTubeResolvedPageMetadata {
        try YouTubeInitialPlayerResponseParser.parse(
            playerResponseData: data
        )
    }
}
