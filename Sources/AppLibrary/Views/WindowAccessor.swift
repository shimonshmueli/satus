import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.callback = callback
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private class AccessorView: NSView {
        var callback: ((NSWindow) -> Void)?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = self.window {
                callback?(window)
            }
        }
    }
}
