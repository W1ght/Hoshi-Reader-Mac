import Foundation

let source = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)
let matchView = try String(contentsOfFile: "Features/Sasayaki/SasayakiMatchView.swift", encoding: .utf8)
let project = try String(contentsOfFile: "Niratan.xcodeproj/project.pbxproj", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

require(
    source.contains("@State private var sasayakiBook: BookMetadata?"),
    "Native bookshelf must own the selected Sasayaki match book"
)
require(
    source.contains(".sheet(item: $sasayakiBook)"),
    "Native bookshelf must present the existing Sasayaki match sheet"
)
require(
    source.contains("SasayakiMatchView(book: book, viewModel: viewModel)"),
    "Native bookshelf must reuse SasayakiMatchView"
)
require(
    source.contains("@Binding var sasayakiBook: BookMetadata?"),
    "Bookshelf sections must receive the match selection binding"
)
require(
    source.contains("onMatch: { sasayakiBook = $0 }"),
    "Shelf match actions must select the requested book"
)
require(
    !source.contains("onMatch: { _ in }"),
    "Native bookshelf must not discard match actions"
)
require(
    project.contains("Sasayaki/SasayakiMatchView.swift"),
    "The native target must compile SasayakiMatchView"
)
require(
    !matchView.contains(".navigationBarTitleDisplayMode(.inline)"),
    "SasayakiMatchView must use the native-compatible navigation title helper"
)
require(
    !matchView.contains("ToolbarItem(placement: .topBarTrailing)"),
    "SasayakiMatchView must use a native macOS toolbar placement"
)
require(
    matchView.contains("NativeSettingsForm("),
    "Match sheet must use the native grouped settings form"
)
require(
    matchView.contains("NativeSettingsSectionCard"),
    "Match sheet must use rounded native section cards"
)
require(
    matchView.contains("private var matchHeader: some View"),
    "Match sheet must own a centered v0.5.0-style header"
)
require(
    matchView.contains("SasayakiMatchLayout.sheetWidth"),
    "Match sheet must have an explicit stable width"
)
require(
    matchView.contains("SasayakiMatchLayout.sheetHeight"),
    "Match sheet must have an explicit stable height"
)
require(
    !matchView.contains("Form {"),
    "Match sheet must not fall back to the compressed macOS Form layout"
)
require(
    !matchView.contains("ToolbarItem(placement: .confirmationAction)"),
    "Done must remain in the top-right custom header"
)

print("Native bookshelf Sasayaki match contract passed")
