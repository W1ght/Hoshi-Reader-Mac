#if HOSHI_VIDEO
import SwiftUI

struct MpvRenderView: NSViewRepresentable {
    let engine: MpvPlayerEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeNSView(context: Context) -> HSMpvOpenGLView {
        let view = HSMpvOpenGLView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.onReady = { view in
            engine.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: HSMpvOpenGLView, context: Context) {}

    static func dismantleNSView(_ nsView: HSMpvOpenGLView, coordinator: Coordinator) {
        nsView.onReady = nil
        coordinator.engine.detachRenderView()
    }

    final class Coordinator {
        let engine: MpvPlayerEngine

        init(engine: MpvPlayerEngine) {
            self.engine = engine
        }
    }
}
#endif
