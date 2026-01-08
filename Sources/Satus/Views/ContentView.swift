import SwiftUI
import AppKit


enum SidebarSelection: Hashable {
    case allApps
    case openApps
    case utilities
    case untagged
    case tag(UUID)
}



struct ContentView: View {
    @StateObject var appService = AppService()
    
    // Derived from settings - simplified for List/Grid sharing if needed
    var baseIconSize: CGFloat {
        CGFloat(Double(appService.dockTileSize) * appService.iconScale)
    }
    
    @State private var searchText = ""
    @State private var selection: SidebarSelection? = .allApps
    @State private var showSettings = false
    @State private var editingTagId: UUID?

    @FocusState private var focusedField: UUID?
    @FocusState private var focusedAppID: String?
    @State private var hoveredAppName: String?
    // removed local isShortcutTriggered
    
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isSidebarFocused: Bool
    @State private var headerVerticalOffset: CGFloat = -22
    

    
    var gridItems: [AppItem] {
        if !searchText.isEmpty {
            return appService.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch selection {
        case .allApps, .none:
            return appService.apps
        case .openApps:
            return appService.runningApps
        case .utilities:
            return appService.apps.filter { 
                let path = $0.url.path
                return path.hasPrefix("/Applications/Utilities") || path.hasPrefix("/System/Applications/Utilities")
            }
        case .untagged:
            return appService.apps.filter { $0.tags.isEmpty }
        case .tag(let id):
            return appService.apps.filter { $0.tags.contains(id) }
        }
    }
    

    
    
    @State private var window: NSWindow?

    private func applyDebugConfiguration() {
        guard let window = window, appService.isDebugMode else { return }
        // Enforce 1280x800 at 80,80
        let debugFrame = NSRect(x: 80, y: 80, width: 1280, height: 800)
        window.setFrame(debugFrame, display: true, animate: true)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, editingTagId: $editingTagId, focusedField: $focusedField, isSidebarFocused: $isSidebarFocused)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            .background(WindowDragger()) // Make sidebar background draggable
        } detail: {
            ZStack {
                VisualEffectView(material: .headerView, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                // Allow dragging on header background
                WindowDragger()
                    .frame(height: 60) // Approximate header height
                    .mask(Rectangle().padding(.top, -100)) // Extend up?
                    .ignoresSafeArea()
                    .allowsHitTesting(true) // Ensure it captures clicks, but it's behind content? No, ZStack order matters.
                
                // Wait, if it's behind VStack, VStack might block it if it has background?
                // Let's put WindowDragger as a background of the top HStack 

                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .frame(height: 28)
                        NonTabTextField(placeholder: "Search All Apps...", text: $searchText)
                            .frame(height: 28)
                            // .focused($isSearchFocused) // Not needed as focus is controlled by focusing other elements
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    // Focus search on appear unless triggered by shortcut
                                    // if !appService.triggeredByShortcut {
                                    //    isSearchFocused = true
                                    // }
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    // Check if last shortcut was within 1.0 second (Fresh Shortcut)
                                    let isFreshShortcut = Date().timeIntervalSince(appService.lastShortcutTime) < 1.0
                                    
                                    // If NOT a fresh shortcut (Mouse/Dock activation), enforce Sidebar Focus on All Apps
                                    if !isFreshShortcut {
                                        print("Manual Activation - Focusing Sidebar (All Apps)")
                                        isSearchFocused = false
                                        isSidebarFocused = true
                                    }
                                }
                            }
                        

                        Picker("", selection: $appService.viewMode) {
                            Image(systemName: "square.grid.2x2").tag(AppViewMode.grid)
                            Image(systemName: "list.bullet").tag(AppViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        
                        

                        
                        
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundColor(.secondary)
                                .font(.title2)
                                .frame(height: 28)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showSettings) {
                            SettingsView()
                                .environmentObject(appService)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .offset(y: headerVerticalOffset)
                    .background(WindowDragger()) // Make the empty space in header draggable
                    
                    GeometryReader { geometry in
                        ScrollView {
                            if selection == nil || selection == .allApps {
                                // Header if needed?
                            } else if selection == .openApps {
                            } else if selection == .utilities {
                        } else if selection == .untagged {
                           HStack {
                                Text("Untagged Apps")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Spacer()
                           }
                           .padding(.horizontal)
                        }
                        
                        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                            Group {
                                if appService.viewMode == .grid {
                                    SmartGridView(
                                        items: gridItems,
                                        onLaunch: { app in
                                            if case .tag(let id) = selection {
                                                appService.recordTagUsage(id: id)
                                            }
                                            appService.launch(app: app)
                                        },
                                        onUpdateSize: { app, size in
                                            appService.setSize(size, for: app.id)
                                        },
                                        onToggleTag: { app, tag in
                                            appService.toggleTag(tag, for: app.id)
                                        },
                                        onAddTag: {
                                            let newTag = appService.addTag(name: "New Tag")
                                            selection = .tag(newTag.id)
                                            editingTagId = newTag.id
                                            focusedField = newTag.id
                                        },
                                        onQuit: (selection == .openApps) ? { app in appService.quitApp(app: app) } : nil,
                                        onHide: (selection == .openApps) ? { app in appService.hiddenAppBundleIDs.insert(app.id) } : nil,
                                        onHoverApp: { name in hoveredAppName = name },
                                        availableTags: appService.tags,
                                        availableWidth: geometry.size.width,
                                        focusedAppID: $focusedAppID
                                    )
                                    .environmentObject(appService)
                                } else {
                                    AppListView(
                                        items: gridItems,
                                        onLaunch: { app in
                                            if case .tag(let id) = selection {
                                                appService.recordTagUsage(id: id)
                                            }
                                            appService.launch(app: app)
                                        },
                                        onQuit: (selection == .openApps) ? { app in appService.quitApp(app: app) } : nil,
                                        onHide: (selection == .openApps) ? { app in appService.hiddenAppBundleIDs.insert(app.id) } : nil,
                                        availableTags: appService.tags,
                                        iconSize: baseIconSize,
                                        onToggleTag: { app, tag in appService.toggleTag(tag, for: app.id) },
                                        onAddTag: {
                                            let newTag = appService.addTag(name: "New Tag")
                                            selection = .tag(newTag.id)
                                            editingTagId = newTag.id
                                            focusedField = newTag.id
                                        },
                                        onHoverApp: { name in hoveredAppName = name }
                                    )
                                }
                            }
                        }
                        .padding()
                        .offset(y: -12)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        }
                    }
                    
                    // Status Bar
                    HStack {
                        Text("\(gridItems.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if let name = hoveredAppName {
                            Text(name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Image(systemName: "minus.magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            Slider(value: $appService.iconScale, in: 0.7...3.0, step: 0.1)
                                .frame(width: 100)
                                .controlSize(.mini)
                            
                            Image(systemName: "plus.magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(VisualEffectView(material: .titlebar, blendingMode: .behindWindow))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
                }
            }
        }
    .preferredColorScheme(appService.appTheme == "dark" ? .dark : (appService.appTheme == "light" ? .light : nil))
    .environmentObject(appService)
    .background(
        WindowAccessor { window in
             self.window = window
             // Ensure buttons hidden here too in case AppDelegate missed it?
             window.standardWindowButton(.closeButton)?.isHidden = true
             window.standardWindowButton(.miniaturizeButton)?.isHidden = true
             window.standardWindowButton(.zoomButton)?.isHidden = true
             window.titlebarAppearsTransparent = true
             window.titleVisibility = .hidden
             // window.isMovableByWindowBackground = true // REMOVED to fix drag conflict
             
             // Initial Check
             applyDebugConfiguration()
        }
    )
    .onChange(of: appService.isDebugMode) { _, _ in
        applyDebugConfiguration()
    }
    .onAppear {
        // Monitor for Modifier Release (Release to Activate)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            // Only act if we are in App Switcher mode
            guard selection == .openApps,
                  let targetID = appService.switcherTargetID,
                  let app = appService.runningApps.first(where: { $0.id == targetID }) else {
                return event
            }
            
            // Get the Apps Switcher shortcut definition
            if let shortcut = GlobalHotkey.shared.getShortcut(id: 6) {
                let requiredMods = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifiers))
                let currentMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                
                // If required modifiers are NO LONGER pressed (subset check), activate
                // But we must ensure they WERE pressed. 
                // Simple check: If current modifiers are strictly LESS than required, it means one was released.
                // Or better: If current set does NOT contain the required set.
                
                if !currentMods.isSuperset(of: requiredMods) {
                    // Modifiers released! Launch.
                    // print("DEBUG: Modifiers released. Launching \(app.name)")
                    appService.launch(app: app)
                }
            }
            return event
        }
        
        GlobalHotkey.shared.startMonitoring { id in
            let app = NSApplication.shared
            
            // 1. Activate
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
            app.activate(ignoringOtherApps: true)
            
            if let window = app.windows.first {
                window.makeKeyAndOrderFront(nil)
                // Restore window style just in case
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            
            // 2. Navigate
            if let action = appService.handleShortcut(id: id) {
                print("Shortcut triggered: \(action)")
                appService.triggeredByShortcut = true
                appService.lastShortcutTime = Date()
                
                switch action {
                case .appSwitcher:
                    // Force distractions off
                    isSidebarFocused = false
                    isSearchFocused = false
                    
                    if selection == .openApps {
                        // Already on Open Apps view: CYCLE FOCUS
                        let openApps = appService.runningApps
                        
                        // Use persistent target if UI focus is lost
                        let currentID = focusedAppID ?? appService.switcherTargetID
                        
                        if let currentID = currentID, let idx = openApps.firstIndex(where: { $0.id == currentID }) {
                            // Move to next
                            let nextIdx = (idx + 1) % openApps.count
                            let nextID = openApps[nextIdx].id
                            
                            focusedAppID = nextID
                            appService.switcherTargetID = nextID
                        } else {
                            // No focus found? Start at first
                            if let firstID = openApps.first?.id {
                                focusedAppID = firstID
                                appService.switcherTargetID = firstID
                            }
                        }
                    } else {
                        // Not on Open Apps view: SWITCH & INITIAL FOCUS
                        selection = .openApps
                        
                        // Delay to allow view transition to complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            if let firstID = appService.runningApps.first?.id {
                                focusedAppID = firstID
                                appService.switcherTargetID = firstID
                            }
                        }
                    }
                case .navigate(let targetSelection):
                    // ... existing ...
                    // Standard Behavior for other views (Sidebar Highlight)
                    isSearchFocused = false
                    isSidebarFocused = true
                    selection = targetSelection
                }
            }
        }
    }
    .onKeyPress(.escape) {
        // Lite App Switcher: ESC launches the app if in Open Apps and focused
        let targetID = focusedAppID ?? appService.switcherTargetID
        if selection == .openApps, let id = targetID, let app = appService.runningApps.first(where: { $0.id == id }) {
            appService.launch(app: app)
            return .handled
        }
        
        NSApplication.shared.hide(nil)
        return .handled
    }
    .onChange(of: selection) { oldValue, newValue in
        if newValue != .openApps {
            focusedAppID = nil
            appService.switcherTargetID = nil
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
        // print("DEBUG: Resigning Active") // Monitor if this fires during shortcut
        showSettings = false
        searchText = "" // Clear search when hidden
        
        // Reset to All Apps on hide to avoid visual jump on next appear
        selection = .allApps
        
        // Reset focus states
        isSidebarFocused = false
        isSearchFocused = false
    }
    }
}





struct AppListView: View {
    let items: [AppItem]
    let onLaunch: (AppItem) -> Void
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let availableTags: [AppTag]
    let iconSize: CGFloat
    let onToggleTag: (AppItem, AppTag) -> Void

    let onAddTag: () -> Void
    let onHoverApp: (String?) -> Void
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { app in
                AppRowView(
                    app: app,
                    onLaunch: onLaunch,
                    onQuit: onQuit,
                    onHide: onHide,
                    availableTags: availableTags,
                    iconSize: iconSize,
                    onToggleTag: onToggleTag,
                    onAddTag: onAddTag,
                    onHoverApp: onHoverApp
                )
                
                Divider()
                    .padding(.leading, 56)
                    .opacity(0.5)
            }
        }
    }
}

struct AppRowView: View {
    let app: AppItem
    let onLaunch: (AppItem) -> Void
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let availableTags: [AppTag]
    let iconSize: CGFloat
    let onToggleTag: (AppItem, AppTag) -> Void
    let onAddTag: () -> Void
    let onHoverApp: (String?) -> Void
    
    @State private var hoveredAppId: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.shared.icon(for: app, size: iconSize))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            
            Text(app.name)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Show tags in list?
            if !app.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(availableTags.filter { app.tags.contains($0.id) }) { tag in
                        Circle()
                            .fill(Color.fromHex(tag.colorHex ?? "#888888"))
                            .frame(width: 8, height: 8)
                            .help(tag.name)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(hoveredAppId == app.id ? Color.secondary.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredAppId = isHovering ? app.id : nil
            onHoverApp(isHovering ? app.name : nil)
        }
        .onTapGesture {
            onLaunch(app)
        }
        .contextMenu {
             if let onQuit = onQuit {
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
                  Button(action: { onHide(app) }) {
                      Label("Hide \(app.name)", systemImage: "eye.slash")
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
                 Button("Add New Tag...") { onAddTag() }
             } label: {
                 Label("Tags", systemImage: "tag")
             }
        }
        .draggable(app.url) {
            let size: CGFloat = 64
            let configuredIcon: NSImage = {
                let img = NSWorkspace.shared.icon(forFile: app.url.path)
                img.size = NSSize(width: size, height: size)
                return img
            }()
            
            Image(nsImage: configuredIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}


struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var editingTagId: UUID?
    @FocusState.Binding var focusedField: UUID?
    @FocusState.Binding var isSidebarFocused: Bool
    
    @EnvironmentObject var appService: AppService
    
    var body: some View {
        List(selection: $selection) {
            
            Section {
                Label("All Apps", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.allApps)
                
                if appService.showOpenApps {
                    Label("Open Apps", systemImage: "macwindow")
                        .tag(SidebarSelection.openApps)
                }
                
                if appService.showUtilities {
                    Label("Utilities", systemImage: "wrench.and.screwdriver")
                        .tag(SidebarSelection.utilities)
                }
            }
            
            Section("TAGS") {
                if appService.tagSortMode == .manual {
                    ForEach(appService.displayTags) { tag in
                        TagRow(tag: tag, editingTagId: $editingTagId, focusedField: $focusedField)
                    }
                    .onMove(perform: appService.moveTag)
                } else {
                    ForEach(appService.displayTags) { tag in
                        TagRow(tag: tag, editingTagId: $editingTagId, focusedField: $focusedField)
                    }
                }
                
                Label("Untagged", systemImage: "tag.slash")
                    .tag(SidebarSelection.untagged)
                
                Button(action: {
                    let newTag = appService.addTag(name: "New Tag")
                    selection = .tag(newTag.id)
                    editingTagId = newTag.id
                    focusedField = newTag.id
                }) {
                    Label("Add New Tag...", systemImage: "plus.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .focused($isSidebarFocused)

    }
}

struct TagRow: View {
    let tag: AppTag
    @Binding var editingTagId: UUID?
    @FocusState.Binding var focusedField: UUID?
    
    @EnvironmentObject var appService: AppService
    @State private var isTargeted = false
    
    var body: some View {
        HStack {
            if editingTagId == tag.id {
                TextField("Tag Name", text: Binding(
                    get: { tag.name },
                    set: { appService.renameTag(id: tag.id, newName: $0) }
                ))
                .focused($focusedField, equals: tag.id)
                .onSubmit {
                    editingTagId = nil
                }
            } else {
                Text(tag.name)
                Spacer()
                
                if appService.tagSortMode == .manual {
                    // Drag Handle Hint (2 fine lines)
                    VStack(spacing: 3) {
                        Capsule()
                            .frame(width: 10, height: 1)
                            .foregroundColor(Color.fromHex("#635F5D"))
                        Capsule()
                            .frame(width: 10, height: 1)
                            .foregroundColor(Color.fromHex("#635F5D"))
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
             RoundedRectangle(cornerRadius: 6)
                 .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .tag(SidebarSelection.tag(tag.id))
        .contextMenu {
            Button("Rename") {
                editingTagId = tag.id
                focusedField = tag.id
            }
            Button("Remove Tag", role: .destructive) {
                appService.deleteTag(id: tag.id)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
             Task {
                 for url in items {
                     appService.assignTag(tag, toAppWithURL: url)
                 }
             }
             return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
    }
}


struct NonTabTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    @State private var isInternalUpdate = false
    
    func makeNSView(context: Context) -> NonTabNSTextField {
        let textField = NonTabNSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 22) // Approximation of .title2
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NonTabNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NonTabTextField
        
        init(parent: NonTabTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

class NonTabNSTextField: NSTextField {
    override var canBecomeKeyView: Bool {
        return false // Prevents Tabbing to this field
    }
    
    // Ensure it can still be clicked to focus
    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }
}
