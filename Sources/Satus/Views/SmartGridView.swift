import SwiftUI
import UniformTypeIdentifiers

@available(macOS 13.0, *)
struct AppTransferable: Transferable {
    let app: AppItem
    
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { AppInternalDragItem(id: $0.app.id) })
        
        FileRepresentation(exportedContentType: .fileURL) { payload in
            SentTransferredFile(payload.app.url)
        }
    }
}
// Helper Extensions
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

struct SmartGridView: View {
    let items: [AppItem]
    let onLaunch: (AppItem) -> Void
    let onUpdateSize: (AppItem, AppSize) -> Void
    let onToggleTag: (AppItem, AppTag) -> Void
    let onAddTag: (AppItem?) -> Void 
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let onRestore: ((AppItem) -> Void)?
    let onHoverApp: (AppItem?) -> Void
    let availableTags: [AppTag]
    let availableWidth: CGFloat
    
    @EnvironmentObject var appService: AppService
    
    @Binding var focusedAppID: String?
    
    // Computed props for sizes
    var baseSize: CGFloat {
        CGFloat(Double(appService.dockTileSize) * appService.iconScale)
    }
    
    var largeSize: CGFloat {
        (baseSize * 2) + 20
    }
    
    var body: some View {
        let itemWidth = baseSize + 40 // baseSize + padding
        let columns = max(1, Int(availableWidth / itemWidth))
        let chunkedItems = items.chunked(into: columns)
        
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 20) {
                ForEach(0..<chunkedItems.count, id: \.self) { rowIndex in
                    HStack(spacing: 20) {
                        ForEach(chunkedItems[rowIndex]) { app in
                            AppIconView(
                                app: app,
                                size: baseSize,
                                largeSize: largeSize,
                                isFocused: focusedAppID == app.id || appService.switcherTargetID == app.id,
                                onLaunch: onLaunch,
                                onQuit: onQuit,
                                onHide: onHide,
                                onRestore: onRestore,
                                onUpdateSize: onUpdateSize,
                                onToggleTag: onToggleTag,
                                onAddTag: onAddTag,
                                onHoverApp: onHoverApp,
                                availableTags: availableTags,
                                isSandboxed: appService.isSandboxed
                            )
                            .id(app.id)
                            .accessibilityLabel(app.name)
                            .onTapGesture {
                                onLaunch(app)
                            }
                        }
                    }
                }
            }
            .padding()
            .padding()
            .onKeyPress(.return) {
                // Check focused OR switcher target
                let targetID = focusedAppID ?? appService.switcherTargetID
                if let id = targetID, let app = items.first(where: { $0.id == id }) {
                    onLaunch(app)
                    return .handled
                }
                return .ignored
            }
            .onChange(of: focusedAppID) { _, newValue in
                if let id = newValue {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: appService.switcherTargetID) { _, newValue in
                if let id = newValue {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct AppIconView: View {
    let app: AppItem
    let size: CGFloat
    let largeSize: CGFloat
    let isFocused: Bool
    let onLaunch: (AppItem) -> Void
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let onRestore: ((AppItem) -> Void)?
    let onUpdateSize: (AppItem, AppSize) -> Void
    let onToggleTag: (AppItem, AppTag) -> Void

    let onAddTag: (AppItem?) -> Void
    let onHoverApp: (AppItem?) -> Void
    let availableTags: [AppTag]
    let isSandboxed: Bool
    
    @EnvironmentObject var appService: AppService
    @State private var isHovering = false
    
    var body: some View {
        VStack {
            ZStack {
                Image(nsImage: IconCache.shared.icon(for: app, size: app.size == .large ? largeSize : size))
                    .resizable()
                    .frame(width: app.size == .large ? largeSize : size, height: app.size == .large ? largeSize : size)
                    .cornerRadius(app.size == .large ? largeSize * 0.18 : size * 0.22)
                    .shadow(radius: isHovering ? 8 : 2)
                    .scaleEffect(isHovering || isFocused ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3), value: isHovering)
                    .animation(.spring(response: 0.3), value: isFocused)
                
                if isFocused {
                    RoundedRectangle(cornerRadius: app.size == .large ? largeSize * 0.22 : size * 0.26)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: (app.size == .large ? largeSize : size) + 6, height: (app.size == .large ? largeSize : size) + 6)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover in 
                isHovering = hover 
                onHoverApp(hover ? app : nil)
            }

            Text(app.name)
                .font(.caption)
                .fontWeight(isFocused ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isFocused ? .accentColor : .primary)
                .frame(width: size + 20)
        }
        .frame(width: app.size == .large ? largeSize + 20 : size + 20, height: app.size == .large ? largeSize + 20 : size + 30)
        .contentShape(Rectangle())
        .contextMenu {
            if let onRestore = onRestore {
                Button(action: { onRestore(app) }) {
                    Label("Restore to Open Apps", systemImage: "arrow.uturn.backward")
                }
            } else {
                if let onQuit = onQuit {
                    if isSandboxed {
                         Button(role: .destructive, action: {}) {
                             Label("Quit (Sandbox Restricted)", systemImage: "xmark.circle")
                         }
                         .disabled(true)
                    } else {
                        Button(role: .destructive, action: { onQuit(app) }) {
                            Label("Quit", systemImage: "xmark.circle")
                        }
                    }
                } else {
                    Button(action: { onLaunch(app) }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                }
                
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                
                if let onHide = onHide {
                    if AppService.isPro || appService.canHideApp {
                        Button(action: { onHide(app) }) {
                           Label("Skip \(app.name)", systemImage: "eye.slash")
                        }
                    } else {
                        Button(action: {}) {
                            Label("Skip \(app.name)  ⌈PRO⌋", systemImage: "eye.slash")
                        }
                        .disabled(true)
                    }
                }

                Divider()
                
                Menu {
                    // System Categories
                    let isUtility = app.url.path.contains("/Applications/Utilities")
                    Button(action: {}) {
                        HStack {
                            Text("Utilities")
                            if isUtility {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(true) // Read-only
                    
                    Divider()
                    
                    ForEach(availableTags) { tag in
                        Button(action: { onToggleTag(app, tag) }) {
                            HStack {
                                Text(tag.name)
                                if app.tags.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    if appService.canAddTag {
                        Button("Add New Tag...") {
                            onAddTag(app)
                        }
                    } else {
                        Button(action: {}) {
                            HStack {
                                Text("Add New Tag...")
                                Text("⌈PRO⌋")
                            }
                        }
                        .disabled(true)
                    }
                } label: {
                    Label("Tags", systemImage: "tag")
                }
            }
        }
        .draggable(app.url) {
             let size = CGFloat(64)
             let configuredIcon: NSImage = {
                 let img = NSWorkspace.shared.icon(forFile: app.url.path)
                 img.size = NSSize(width: size, height: size)
                 return img
             }()
             
             Image(nsImage: configuredIcon)
                 .resizable()
                 .frame(width: size, height: size)
        }
    }
}

// Helper Extension
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
