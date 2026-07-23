import Foundation

struct VideoInspectorState: Equatable {
    var speed = 1.0
    var subtitleDelay: TimeInterval = 0
    var audioDelay: TimeInterval = 0
    var loopMode: VideoLoopMode = .none
    var abLoop: VideoABLoop?
    var aspectRatio: VideoAspectRatio = .automatic
    var tracks: [VideoTrack] = []

    init() {}

    init(snapshot: VideoPlaybackSnapshot) {
        speed = snapshot.speed
        subtitleDelay = snapshot.subtitleDelay
        audioDelay = snapshot.audioDelay
        loopMode = snapshot.loopMode
        abLoop = snapshot.abLoop
        aspectRatio = snapshot.aspectRatio
        tracks = snapshot.tracks
    }
}
