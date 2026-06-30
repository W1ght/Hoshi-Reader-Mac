import Foundation

func source(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func assertContains(_ source: String, _ needle: String, _ message: String) {
    if !source.contains(needle) {
        fputs("Assertion failed: \(message). Missing: \(needle)\n", stderr)
        exit(1)
    }
}

func assertNotContains(_ source: String, _ needle: String, _ message: String) {
    if source.contains(needle) {
        fputs("Assertion failed: \(message). Unexpected: \(needle)\n", stderr)
        exit(1)
    }
}

let reuseSource = try source("NativeMac/NativeReuseViews.swift")
assertContains(reuseSource, "showStatisticsDashboard", "Bookshelf owns dashboard sub-state")
assertContains(reuseSource, "Label(\"Statistics\", systemImage: \"chart.xyaxis.line\")", "Bookshelf toolbar exposes an SF Symbols Statistics button")
assertContains(reuseSource, "Label(\"Bookshelf\", systemImage: \"books.vertical\")", "Dashboard toolbar exposes an SF Symbols Bookshelf return button")
assertContains(reuseSource, "StatisticsDashboardView(", "Bookshelf routes to the dashboard view")

let dashboardSource = try source("Features/Bookshelf/StatisticsDashboardView.swift")
assertContains(dashboardSource, "struct StatisticsDashboardView", "Dashboard view exists")
assertContains(dashboardSource, "dashboardLayout(width:", "Dashboard uses a width-aware responsive layout")
assertContains(dashboardSource, "width >= 1_260", "Dashboard fills wide windows with three columns")
assertContains(dashboardSource, "HStack(alignment: .top", "Dashboard columns stay top-aligned while resizing")
assertContains(dashboardSource, "Reading Calendar", "Dashboard includes calendar section")
assertContains(dashboardSource, "By Book", "Dashboard includes distribution section")
assertNotContains(dashboardSource, "Label(\"Refresh\"", "Dashboard content should not keep the duplicate refresh button")
assertNotContains(dashboardSource, "Button(\"Bookshelf\")", "Dashboard content should not keep the duplicate Bookshelf button")

let settingsSource = try source("Features/Settings/StatisticsSettingsView.swift")
assertContains(settingsSource, "Daily Goal", "Settings expose daily goal controls")
assertContains(settingsSource, "Weekly Goal", "Settings expose weekly goal controls")
assertContains(settingsSource, "dailyStatisticsTargetType", "Settings persist daily target type")

print("statistics dashboard UI contract passed")
