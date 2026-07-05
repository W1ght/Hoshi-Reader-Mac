#if HOSHI_VIDEO
import SwiftUI

struct VideoOnScreenDisplayItem: Equatable, Identifiable {
    let id = UUID()
    var title: LocalizedStringKey
    var value: String
    var detail: String?
    var meterProgress: Double?

    init(
        title: LocalizedStringKey,
        value: String,
        detail: String? = nil,
        meterProgress: Double? = nil
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.meterProgress = meterProgress.map(Self.normalizedMeterProgress)
    }

    private static func normalizedMeterProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}

struct VideoOnScreenDisplayView: View {
    let item: VideoOnScreenDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.title)
                    .lineLimit(1)

                Text(item.value)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 27, weight: .bold, design: .default))

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.82))
            }

            if let meterProgress = item.meterProgress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.24))
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.52, blue: 1.0))
                            .frame(width: proxy.size.width * meterProgress)
                    }
                }
                .frame(width: 210, height: 5)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.92), radius: 7, y: 2)
        .shadow(color: .black.opacity(0.72), radius: 1)
        .accessibilityElement(children: .combine)
    }
}
#endif
