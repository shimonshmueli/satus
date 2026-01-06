import SwiftUI
import AppKit

struct WindowDragger: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggerView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private class DraggerView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
