//
//  ReaderRegressionLabView.swift
//  Hoshi Reader
//
//  Debug-only Reader regression infrastructure.
//

#if DEBUG
import SwiftUI

enum ReaderRegressionLabAvailability {
    private static let launchArgument = "--reader-regression-lab"
    fileprivate static let fixtureDirectoryArgument = "--reader-regression-fixtures"
    fileprivate static let scenarioArgument = "--reader-regression-scenario"
    private static let defaultsKey = "HoshiReaderDebugShowReaderRegressionLab"

    static var isEnabled: Bool {
        shouldAutoOpen ||
            UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var shouldAutoOpen: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var shouldShowLaunchOverlay: Bool {
        shouldAutoOpen && requestedScenario == nil
    }

    static var requestedScenario: ReaderRegressionScenarioPlan? {
        guard let value = launchArgumentValue(scenarioArgument), !value.isEmpty else {
            return nil
        }
        return ReaderRegressionScenarios.plan(matching: value)
    }

    static var enableInstructions: String {
        "\(launchArgument) or defaults write <bundle-id> \(defaultsKey) -bool YES"
    }

    fileprivate static func launchArgumentValue(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }
}

struct ReaderRegressionLabView: View {
    var onImportFixture: () -> Void
    var onOpenScenario: (ReaderRegressionScenarioPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    private let fixtures: [FixturePlan] = [
        .init(name: "plain-horizontal.epub", purpose: "Horizontal paginated and continuous baseline"),
        .init(name: "plain-vertical.epub", purpose: "Vertical Japanese pagination baseline"),
        .init(name: "long-chapter.epub", purpose: "Long chapter middle and end restore"),
        .init(name: "chapter-boundary.epub", purpose: "Previous/next chapter boundary"),
        .init(name: "ruby-heavy.epub", purpose: "Ruby, selection, and popup coordinates"),
        .init(name: "multi-image.epub", purpose: "Large image containment"),
        .init(name: "cover-image.epub", purpose: "Cover image sizing"),
        .init(name: "weird-css.epub", purpose: "Hostile EPUB CSS constraints"),
        .init(name: "internal-links.epub", purpose: "Fragment and file link jumps"),
        .init(name: "mixed-content.epub", purpose: "Combined text, ruby, images, and links"),
    ]

    private let scenarios = ReaderRegressionScenarios.plans

    private var fixtureDirectory: URL {
        ReaderRegressionFixtureLocator.fixtureDirectory
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Entry") {
                        Text("Debug-only")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Enable with") {
                        Text(ReaderRegressionLabAvailability.enableInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Fixture generator") {
                        Text("python3 script/generate_reader_fixtures.py")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Fixture directory") {
                        Text(fixtureDirectory.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Capture skeleton") {
                        Text("script/capture_reader_regression.sh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Fixture EPUBs") {
                    Button {
                        dismiss()
                        onImportFixture()
                    } label: {
                        Label("Import Fixture EPUB...", systemImage: "square.and.arrow.down")
                    }

                    ForEach(fixtures) { fixture in
                        let url = fixtureDirectory.appendingPathComponent(fixture.name)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fixture.name)
                                    .font(.headline)
                                Text(fixture.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? "checkmark.circle.fill" : "exclamationmark.triangle")
                                .foregroundStyle(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? .green : .orange)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Screenshot Scenarios") {
                    ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                        Button {
                            dismiss()
                            onOpenScenario(scenario)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(index + 1). \(scenario.name)")
                                        .foregroundStyle(.primary)
                                    Text(scenario.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(scenario.fixtureName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Geometry To Capture") {
                    GeometryReader { geometry in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("Lab viewport") {
                                Text("\(Int(geometry.size.width)) x \(Int(geometry.size.height))")
                                    .monospacedDigit()
                            }
                            Text("Reader viewport, safe area, page width, page height, writing mode, layout mode, and scroll/page offset should be captured by the next lab iteration inside Reader.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 70)
                }
            }
            .navigationTitle("Reader Regression Lab")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("reader-regression-lab")
    }
}

private struct FixturePlan: Identifiable {
    var id: String { name }
    let name: String
    let purpose: String
}

struct ReaderRegressionScenarioPlan: Identifiable, Hashable {
    var id: String { "\(name)-\(fixtureName)" }
    let name: String
    let fixtureName: String
    let verticalWriting: Bool
    let continuousMode: Bool
    let theme: Themes
    let progressTop: Bool
    let chapterIndex: Int
    let chapterProgress: Double

    var fixtureURL: URL {
        ReaderRegressionFixtureLocator.fixtureDirectory.appendingPathComponent(fixtureName)
    }

    var summary: String {
        [
            verticalWriting ? "Vertical" : "Horizontal",
            continuousMode ? "Continuous" : "Paginated",
            theme.rawValue,
            progressTop ? "Top progress" : "Bottom progress",
            "Chapter \(chapterIndex + 1) @ \(Int((chapterProgress * 100).rounded()))%"
        ].joined(separator: " / ")
    }
}

enum ReaderRegressionFixtureLocator {
    static var fixtureDirectory: URL {
        if let override = ReaderRegressionLabAvailability.launchArgumentValue(ReaderRegressionLabAvailability.fixtureDirectoryArgument), !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return sourceRoot.appendingPathComponent("testdata/reader-fixtures")
    }

    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

enum ReaderRegressionScenarios {
    static let plans: [ReaderRegressionScenarioPlan] = [
        .init(name: "Horizontal paginated Light", fixtureName: "plain-horizontal.epub", verticalWriting: false, continuousMode: false, theme: .light, progressTop: true, chapterIndex: 0, chapterProgress: 0.0),
        .init(name: "Horizontal continuous Light", fixtureName: "plain-horizontal.epub", verticalWriting: false, continuousMode: true, theme: .light, progressTop: false, chapterIndex: 0, chapterProgress: 0.48),
        .init(name: "Vertical paginated Light", fixtureName: "plain-vertical.epub", verticalWriting: true, continuousMode: false, theme: .light, progressTop: true, chapterIndex: 0, chapterProgress: 0.0),
        .init(name: "Vertical continuous Light", fixtureName: "plain-vertical.epub", verticalWriting: true, continuousMode: true, theme: .light, progressTop: false, chapterIndex: 0, chapterProgress: 0.46),
        .init(name: "Vertical full screen chrome", fixtureName: "plain-vertical.epub", verticalWriting: true, continuousMode: false, theme: .dark, progressTop: true, chapterIndex: 0, chapterProgress: 0.33),
        .init(name: "Long chapter end", fixtureName: "long-chapter.epub", verticalWriting: false, continuousMode: false, theme: .light, progressTop: false, chapterIndex: 0, chapterProgress: 0.92),
        .init(name: "Ruby lookup popup", fixtureName: "ruby-heavy.epub", verticalWriting: true, continuousMode: false, theme: .light, progressTop: true, chapterIndex: 0, chapterProgress: 0.2),
        .init(name: "Multi-image page", fixtureName: "multi-image.epub", verticalWriting: false, continuousMode: true, theme: .light, progressTop: false, chapterIndex: 0, chapterProgress: 0.25),
        .init(name: "Cover page", fixtureName: "cover-image.epub", verticalWriting: false, continuousMode: false, theme: .light, progressTop: true, chapterIndex: 0, chapterProgress: 0.0),
        .init(name: "Sepia popup", fixtureName: "weird-css.epub", verticalWriting: false, continuousMode: false, theme: .sepia, progressTop: true, chapterIndex: 0, chapterProgress: 0.18),
    ]

    static func plan(matching value: String) -> ReaderRegressionScenarioPlan? {
        if let number = Int(value),
           plans.indices.contains(number - 1) {
            return plans[number - 1]
        }
        return plans.first { scenario in
            scenario.id == value || scenario.name == value
        }
    }
}
#endif
