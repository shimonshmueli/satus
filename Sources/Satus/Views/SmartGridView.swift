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
        let cardWidth = baseSize + 44 // card internal (28) + frame extra (16)
        let itemWidth = cardWidth + 20 // card + HStack spacing
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
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing)
            .padding(.trailing)
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
        let currentSize = app.size == .large ? largeSize : size
        let cardWidth = currentSize + 28
        
        VStack(spacing: 6) {
            // Icon
            ZStack {
                Image(nsImage: IconCache.shared.icon(for: app, size: currentSize))
                    .resizable()
                    .frame(width: currentSize, height: currentSize)
                    .cornerRadius(currentSize * 0.22)
                    .shadow(radius: isHovering ? 8 : 2)
                    .scaleEffect(isHovering || isFocused ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3), value: isHovering)
                    .animation(.spring(response: 0.3), value: isFocused)
                
                if isFocused {
                    RoundedRectangle(cornerRadius: currentSize * 0.26)
                        .stroke(appService.accentColor, lineWidth: 3)
                        .frame(width: currentSize + 6, height: currentSize + 6)
                }
            }
            
            // Name
            Text(app.name)
                .font(.caption)
                .fontWeight(isFocused ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isFocused ? appService.accentColor : .primary)
                .frame(width: cardWidth - 12)
            
            // Tag dots
            let matchedTags = availableTags.filter { app.tags.contains($0.id) }
            if !matchedTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(matchedTags) { tag in
                        Circle()
                            .fill(Color.fromHex(tag.colorHex ?? "#888888"))
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                // Invisible spacer to keep card heights consistent
                Color.clear.frame(height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? appService.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(width: cardWidth + 16)
        .contentShape(Rectangle())
        .onHover { hover in
            isHovering = hover
            onHoverApp(hover ? app : nil)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let onRestore = onRestore {
                Button(action: { onRestore(app) }) {
                    Label("Restore to Open Applications", systemImage: "arrow.uturn.backward")
                }
            } else {
                if let onQuit = onQuit {
                    // Apple Events entitlement lets terminate() work inside the sandbox.
                    // The system shows its own per-target Automation prompt the first time.
                    Button(role: .destructive, action: { onQuit(app) }) {
                        Label("Quit", systemImage: "xmark.circle")
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
