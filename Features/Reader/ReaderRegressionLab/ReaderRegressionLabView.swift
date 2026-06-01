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
    private static let defaultsKey = "HoshiReaderDebugShowReaderRegressionLab"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument) ||
            UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var enableInstructions: String {
        "\(launchArgument) or defaults write <bundle-id> \(defaultsKey) -bool YES"
    }
}

struct ReaderRegressionLabView: View {
    var onImportFixture: () -> Void
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

    private let scenarios: [ScenarioPlan] = [
        .init(name: "Horizontal paginated Light", fixture: "plain-horizontal.epub"),
        .init(name: "Horizontal continuous Light", fixture: "plain-horizontal.epub"),
        .init(name: "Vertical paginated Light", fixture: "plain-vertical.epub"),
        .init(name: "Vertical continuous Light", fixture: "plain-vertical.epub"),
        .init(name: "Vertical full screen chrome", fixture: "plain-vertical.epub"),
        .init(name: "Long chapter end", fixture: "long-chapter.epub"),
        .init(name: "Ruby lookup popup", fixture: "ruby-heavy.epub"),
        .init(name: "Multi-image page", fixture: "multi-image.epub"),
        .init(name: "Cover page", fixture: "cover-image.epub"),
        .init(name: "E-ink popup", fixture: "weird-css.epub"),
    ]

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fixture.name)
                                .font(.headline)
                            Text(fixture.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Screenshot Scenarios") {
                    ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                        LabeledContent("\(index + 1). \(scenario.name)") {
                            Text(scenario.fixture)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                ToolbarItem(placement: .topBarTrailing) {
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

private struct ScenarioPlan: Identifiable {
    var id: String { "\(name)-\(fixture)" }
    let name: String
    let fixture: String
}
#endif
