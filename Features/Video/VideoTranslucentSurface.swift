#if HOSHI_VIDEO
import AppKit
import SwiftUI

struct VideoTranslucentSurface<Content: View>: NSViewRepresentable {
    let liquidGlassCornerRadius: CGFloat
    let visualEffectCornerRadius: CGFloat
    private let content: Content

    init(
        liquidGlassCornerRadius: CGFloat,
        visualEffectCornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.liquidGlassCornerRadius = liquidGlassCornerRadius
        self.visualEffectCornerRadius = visualEffectCornerRadius
        self.content = content()
    }

    func makeNSView(context: Context) -> VideoTranslucentHostingView {
        VideoTranslucentHostingView(
            rootView: AnyView(content),
            liquidGlassCornerRadius: liquidGlassCornerRadius,
            visualEffectCornerRadius: visualEffectCornerRadius
        )
    }

    func updateNSView(_ nsView: VideoTranslucentHostingView, context: Context) {
        nsView.rootView = AnyView(content)
    }
}

final class VideoTranslucentHostingView: NSView {
    private let hostingView: NSHostingView<AnyView>
    private let surfaceView: NSView

    var rootView: AnyView {
        get { hostingView.rootView }
        set {
            hostingView.rootView = newValue
            invalidateIntrinsicContentSize()
        }
    }

    init(
        rootView: AnyView,
        liquidGlassCornerRadius: CGFloat,
        visualEffectCornerRadius: CGFloat
    ) {
        hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = liquidGlassCornerRadius
            glassView.contentView = hostingView
            surfaceView = glassView
        } else {
            let visualEffectView = NSVisualEffectView()
            visualEffectView.blendingMode = .withinWindow
            visualEffectView.material = .popover
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = visualEffectCornerRadius
            visualEffectView.layer?.masksToBounds = true
            visualEffectView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            ])
            surfaceView = visualEffectView
        }

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        hostingView.fittingSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
