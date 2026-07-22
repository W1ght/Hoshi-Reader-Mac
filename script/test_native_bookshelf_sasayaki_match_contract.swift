import Foundation

let nativeBookshelf = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)
let bookshelf = try String(contentsOfFile: "Features/Bookshelf/BookshelfView.swift", encoding: .utf8)
let shelf = try String(contentsOfFile: "Features/Bookshelf/ShelfView.swift", encoding: .utf8)
let bookCell = try String(contentsOfFile: "Features/Bookshelf/BookCell.swift", encoding: .utf8)
let matchSection = try String(contentsOfFile: "Features/Sasayaki/SasayakiMatchView.swift", encoding: .utf8)
let sheet = try String(contentsOfFile: "Features/Sasayaki/SasayakiSheet.swift", encoding: .utf8)
let player = try String(contentsOfFile: "Features/Sasayaki/SasayakiPlayer.swift", encoding: .utf8)
let reader = try String(contentsOfFile: "NativeMac/NativeReaderView.swift", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

for source in [nativeBookshelf, bookshelf, shelf, bookCell] {
    require(!source.contains("sasayakiBook"), "Bookshelf should not retain Sasayaki match sheet state")
    require(!source.contains("waveform.badge.magnifyingglass"), "Bookshelf context menu should not show Match")
    require(!source.contains("SasayakiMatchView("), "Bookshelf should not present a standalone match sheet")
}
require(
    matchSection.contains("struct SasayakiSubtitleMatchSection: View"),
    "Subtitle matching should be a reusable Resources section"
)
require(
    sheet.contains("SasayakiSubtitleMatchSection(rootURL: player.rootURL)"),
    "Reader Resources should host subtitle matching"
)
require(
    player.contains("func updateMatchData(_ matchData: SasayakiMatchData)"),
    "Player should accept a newly saved subtitle match"
)
require(
    player.contains(".applySasayakiCues(cues(for: getCurrentIndex())"),
    "A new match should immediately install cues in the current Reader chapter"
)
require(
    reader.contains("userConfig.enableSasayaki && model.sasayakiPlayer != nil"),
    "Reader should expose Sasayaki before a subtitle match exists"
)
require(
    matchSection.contains("FileNames.sasayakiMatch"),
    "Resources matching should preserve the existing sidecar filename"
)

print("Reader Sasayaki subtitle match contract passed")
