import SwiftUI
import AppKit

// Window delegate to handle window close events
class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // When user clicks the red X button or presses Cmd+W, quit the app
        NSApplication.shared.terminate(nil)
        return false // We handle the quit ourselves
    }
}

struct ContentView: View {
    @StateObject var appService = AppService()

    // Derived from settings - simplified for List/Grid sharing if needed
    var baseIconSize: CGFloat {
        CGFloat(Double(appService.dockTileSize) * appService.iconScale)
    }
    
    // searchText moved to appService
    // selection moved to appService
    @State private var showSettings = false
    @State private var editingTagId: UUID?

    @FocusState private var focusedField: UUID?
    @State private var hoveredAppName: String?
    // removed local isShortcutTriggered
    
    @State private var searchFocusedState: Bool = false
    @FocusState private var isSidebarFocused: Bool
    @State private var headerVerticalOffset: CGFloat = -12
    @State private var showListViewSwitcherAlert: Bool = false
    

    
    // gridItems logic moved to AppService.currentGridApps
    

    
    
    @State private var window: NSWindow?
    @State private var windowDelegate = WindowDelegate()

    private func applyDebugConfiguration() {
        guard let window = window, appService.isDebugMode else { return }
        // Enforce 1280x800 at 80,80
        let debugFrame = NSRect(x: 80, y: 80, width: 1280, height: 800)
        window.setFrame(debugFrame, display: true, animate: true)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                    selection: $appService.sidebarSelection,
                    editingTagId: $editingTagId,
                    focusedField: $focusedField,
                    isSidebarFocused: $isSidebarFocused
                )
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
                        NonTabTextField(placeholder: "Search All Applications...", text: $appService.searchText, isFocused: $searchFocusedState)
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
                                    
                                    // If NOT a fresh shortcut (Mouse/Dock activation)
                                    if !isFreshShortcut {
                                        print("Manual Activation - Focusing Sidebar")
                                        searchFocusedState = false
                                        isSidebarFocused = true
                                        appService.activeFocusZone = .sidebar
                                        appService.focusedAppID = nil // Explicitly clear grid focus
                                        
                                        // Use Default Tag if set, otherwise default to All Apps if nil
                                        if let defaultTag = appService.defaultTagId {
                                             // If current selection is NOT the default tag, switch to it?
                                             // Or only if selection is nil? 
                                             // User request: "Same as shortcut to that tag" => Switch to it.
                                             appService.sidebarSelection = .tag(defaultTag)
                                        } else if appService.sidebarSelection == nil {
                                            appService.sidebarSelection = .allApps
                                        }
                                    }
                                }
                            }
                        

                        Picker("", selection: $appService.viewMode) {
                            Image(systemName: "square.grid.2x2").tag(AppViewMode.grid)
                            Image(systemName: "list.bullet").tag(AppViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        
                        

                        
                        
                        Button(action: { appService.isPinned.toggle() }) {
                            Image(systemName: appService.isPinned ? "pin.fill" : "pin")
                                .foregroundColor(appService.isPinned ? appService.accentColor : .secondary)
                                .font(.title2)
                                .frame(height: 28)
                        }
                        .buttonStyle(.plain)
                        .help(appService.isPinned ? "Unpin window (allow auto-close)" : "Pin window (prevent auto-close)")
                        
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
                          VStack(spacing: 0) {
                            if appService.sidebarSelection == nil || appService.sidebarSelection == .allApps {
                                // Header if needed?
                            } else if appService.sidebarSelection == .openApps {
                            } else if appService.sidebarSelection == .utilities {
                        } else if appService.sidebarSelection == .untagged {
                           HStack {
                                Text("Untagged Applications")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Spacer()
                           }
                           .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 20) {
                            // Step 2 of the Headless feature: when the user
                            // selects "Headless" in the sidebar, swap in the new
                            // viewer. The existing if/else-if chain below has no
                            // branch for .headless, so nothing else renders here.
                            if appService.sidebarSelection == .headless {
                                HeadlessView()
                            }
                            if appService.sidebarSelection == .openApps {
                                // 1. Visible Apps
                                Group {
                                    if appService.viewMode == .grid {
                                        SmartGridView(
                                            items: appService.currentGridApps,
                                            onLaunch: { app in appService.launch(app: app) },
                                            onUpdateSize: { app, size in appService.setSize(size, for: app.id) },
                                            onToggleTag: { app, tag in appService.toggleTag(tag, for: app.id) },
                                            onAddTag: { app in
                                                guard let newTag = appService.addTag(name: "New Tag") else { return }
                                                appService.sidebarSelection = .tag(newTag.id)
                                                editingTagId = newTag.id
                                                focusedField = newTag.id
                                                if let app = app {
                                                    appService.toggleTag(newTag, for: app.id)
                                                }
                                            },
                                            onQuit: { app in appService.quitApp(app: app) },
                                            onHide: { app in appService.hiddenAppBundleIDs.insert(app.id) },
                                            onRestore: nil,
                                            onHoverApp: { app in 
                                                hoveredAppName = app?.name 
                                                if let app = app, appService.triggeredByShortcut {
                                                    appService.switcherTargetID = app.id
                                                }
                                            },
                                            availableTags: appService.tags,
                                            availableWidth: geometry.size.width,
                                            focusedAppID: $appService.focusedAppID
                                        )
                                        .environmentObject(appService)
                                    } else {
                                        AppListView(
                                            items: appService.currentGridApps,
                                            onLaunch: { app in appService.launch(app: app) },
                                            onQuit: { app in appService.quitApp(app: app) },
                                            onHide: { app in appService.hiddenAppBundleIDs.insert(app.id) },
                                            onRestore: nil,
                                            availableTags: appService.tags,
                                            iconSize: baseIconSize,
                                            onToggleTag: { app, tag in appService.toggleTag(tag, for: app.id) },
                                            onAddTag: { app in
                                                guard let newTag = appService.addTag(name: "New Tag") else { return }
                                                appService.sidebarSelection = .tag(newTag.id)
                                                editingTagId = newTag.id
                                                focusedField = newTag.id
                                                if let app = app {
                                                    appService.toggleTag(newTag, for: app.id)
                                                }
                                            },
                                            onHoverApp: { app in 
                                                hoveredAppName = app?.name 
                                                if let app = app, appService.triggeredByShortcut {
                                                    appService.switcherTargetID = app.id
                                                }
                                            },
                                            focusedAppID: $appService.focusedAppID
                                        )
                                    }
                                }
                                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                    for provider in providers {
                                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                            guard let url = url else { return }
                                            Task { @MainActor in
                                                if let app = appService.hiddenRunningApps.first(where: { $0.url.path == url.path }) {
                                                    appService.unhideApp(app)
                                                }
                                            }
                                        }
                                    }
                                    return true
                                }
                                
                                // 2. Hidden Apps (drop zone always visible)
                                HiddenAppsDropZone(
                                    appService: appService,
                                    viewMode: appService.viewMode,
                                    baseIconSize: baseIconSize,
                                    availableWidth: geometry.size.width,
                                    hoveredAppName: $hoveredAppName
                                )
                                
                            } else {
                                // Default View for other selections
                                Group {
                                    if appService.viewMode == .grid {
                                        SmartGridView(
                                            items: appService.currentGridApps,
                                            onLaunch: { app in
                                                if case .tag(let id) = appService.sidebarSelection {
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
                                            onAddTag: { app in
                                                guard let newTag = appService.addTag(name: "New Tag") else { return }
                                                appService.sidebarSelection = .tag(newTag.id)
                                                editingTagId = newTag.id
                                                focusedField = newTag.id
                                                if let app = app {
                                                    appService.toggleTag(newTag, for: app.id)
                                                }
                                            },
                                            onQuit: nil,
                                            onHide: nil,
                                            onRestore: nil,
                                            onHoverApp: { app in hoveredAppName = app?.name },
                                            availableTags: appService.tags,
                                            availableWidth: geometry.size.width,
                                            focusedAppID: $appService.focusedAppID
                                        )
                                        .environmentObject(appService)
                                    } else {
                                        AppListView(
                                            items: appService.currentGridApps,
                                            onLaunch: { app in
                                                if case .tag(let id) = appService.sidebarSelection {
                                                    appService.recordTagUsage(id: id)
                                                }
                                                appService.launch(app: app)
                                            },
                                            onQuit: nil,
                                            onHide: nil,
                                            onRestore: nil,
                                            availableTags: appService.tags,
                                            iconSize: baseIconSize,
                                            onToggleTag: { app, tag in appService.toggleTag(tag, for: app.id) },
                                            onAddTag: { app in
                                                guard let newTag = appService.addTag(name: "New Tag") else { return }
                                                appService.sidebarSelection = .tag(newTag.id)
                                                editingTagId = newTag.id
                                                focusedField = newTag.id
                                                if let app = app {
                                                    appService.toggleTag(newTag, for: app.id)
                                                }
                                            },
                                            onHoverApp: { app in hoveredAppName = app?.name },
                                            focusedAppID: $appService.focusedAppID
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.trailing)
                        .padding(.top, 3)
                        .padding(.bottom)
                        .frame(minHeight: geometry.size.height, alignment: .topLeading)
                        .frame(width: geometry.size.width, alignment: .topLeading)
                          } // end VStack(spacing: 0)
                        }
                        .onChange(of: geometry.size.width) { _, newValue in
                            if newValue > 100 {
                                appService.contentWidth = newValue
                            }
                        }
                        .onAppear {
                            appService.contentWidth = geometry.size.width
                        }
                    }
                    
                    // Status Bar
                    HStack {
                        Text("\(appService.currentGridApps.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 50)
                        
                        Spacer()
                        
                        if let name = hoveredAppName {
                            Text(name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                appService.iconScale = max(1.0, appService.iconScale - 0.5)
                            }) {
                                Image(systemName: "square")
                                    .font(.caption2) // Small square
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Slider(value: $appService.iconScale, in: 1.0...3.0, step: 0.5)
                                .frame(width: 120)
                                .controlSize(.small)
                            
                            Button(action: {
                                appService.iconScale = min(3.0, appService.iconScale + 0.5)
                            }) {
                                Image(systemName: "square")
                                    .font(.title3) // Larger square
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 40) // Move slider left by 20px (from 20 to 40)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10) // Symmetric padding for vertical centering, increased height
                    .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
                }
            }
        }
        // Global Keyboard Event Handling
        .onAppear {
            // Force Sidebar Focus on Launch
            if appService.sidebarSelection == nil {
                appService.sidebarSelection = .allApps
            }
            // Ensure focus state matches
            isSidebarFocused = true
            appService.activeFocusZone = .sidebar
            
        }
        .onChange(of: appService.activeFocusZone) { _, newZone in
            if newZone == .search {
                searchFocusedState = true
                isSidebarFocused = false
            } else if newZone == .sidebar {
                searchFocusedState = false
                isSidebarFocused = true
            } else {
                // grid
                searchFocusedState = false
                isSidebarFocused = false
            }
        }
        .onChange(of: searchFocusedState) { _, isFocused in
            if !isFocused && appService.activeFocusZone == .search {
                appService.activeFocusZone = .sidebar
            }
        }
        .environmentObject(appService) // Only one instance at end
    .background(
        WindowAccessor { window in
             self.window = window
             // Ensure buttons hidden here too in case AppDelegate missed it?
             window.standardWindowButton(.closeButton)?.isHidden = false
             window.standardWindowButton(.miniaturizeButton)?.isHidden = false
             window.standardWindowButton(.zoomButton)?.isHidden = false
             window.titlebarAppearsTransparent = true
             window.titleVisibility = .hidden
             
             window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
             window.isReleasedWhenClosed = false
             window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
             // window.isMovableByWindowBackground = true // REMOVED to fix drag conflict
             
             // Set delegate to handle window close events (quit app on close)
             window.delegate = windowDelegate
             
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
            guard appService.sidebarSelection == .openApps,
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
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
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
                    if appService.viewMode == .list {
                        print("Switcher hotkey pressed but in list mode - playing error beep")
                        NSSound.beep()
                        return // Do not trigger switcher
                    }
                    
                    // Force distractions off
                    isSidebarFocused = false
                    searchFocusedState = false
                    
                    if appService.sidebarSelection == .openApps {
                        // Already on Open Apps view: CYCLE FOCUS
                        let openApps = appService.runningApps
                        
                        // Use persistent target if UI focus is lost
                        let currentID = appService.focusedAppID ?? appService.switcherTargetID
                        
                        if let currentID = currentID, let idx = openApps.firstIndex(where: { $0.id == currentID }) {
                            // Move to next
                            let nextIdx = (idx + 1) % openApps.count
                            let nextID = openApps[nextIdx].id
                            
                            appService.focusedAppID = nextID
                            appService.switcherTargetID = nextID
                        } else {
                            // No focus found? Start at first
                            if let firstID = openApps.first?.id {
                                appService.focusedAppID = firstID
                                appService.switcherTargetID = firstID
                            }
                        }
                    } else {
                        // Not on Open Apps view: SWITCH & INITIAL FOCUS
                        appService.sidebarSelection = .openApps
                        
                        // Delay to allow view transition to complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            if let firstID = appService.runningApps.first?.id {
                                appService.focusedAppID = firstID
                                appService.switcherTargetID = firstID
                            }
                        }
                    }
                case .navigate(let targetSelection):
                    // ... existing ...
                    // Standard Behavior for other views (Sidebar Highlight)
                    searchFocusedState = false
                    isSidebarFocused = true
                    appService.sidebarSelection = targetSelection
                }
            }
        }
    }

    .onChange(of: appService.activeFocusZone) { _, newZone in
        if newZone == .sidebar {
            isSidebarFocused = true
            appService.focusedAppID = nil // Clear grid focus
        } else {
            isSidebarFocused = false
        }
    }
    .onChange(of: appService.sidebarSelection) { oldValue, newValue in
        if newValue != .openApps {
            appService.focusedAppID = nil
            appService.switcherTargetID = nil
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
        // If pinned (or Settings is open), we're staying visible — don't
        // touch the user's context. They want their sidebar selection,
        // search text, and Settings sheet preserved when they bounce to
        // another app and back.
        if appService.isPinned || appService.isSettingsOpen { return }

        showSettings = false
        appService.searchText = "" // Clear search when hidden

        // Reset to All Apps on hide to avoid visual jump on next appear
        appService.sidebarSelection = .allApps

        // Reset focus states
        isSidebarFocused = false
        searchFocusedState = false
        
        // Explicitly clear grid focus
        appService.activeFocusZone = .sidebar
        appService.focusedAppID = nil 
        appService.triggeredByShortcut = false 
    }
    .preferredColorScheme(appService.appTheme == "dark" ? .dark : (appService.appTheme == "light" ? .light : nil))
    .tint(appService.accentColor)
}

struct HiddenAppsDropZone: View {
    @ObservedObject var appService: AppService
    let viewMode: AppViewMode
    let baseIconSize: CGFloat
    let availableWidth: CGFloat
    @Binding var hoveredAppName: String?
    
    var body: some View {
        VStack(spacing: 0) {
            if !appService.hiddenRunningApps.isEmpty {
                Divider()
                    .padding(.vertical, 10)
                
                Text("Skipped Applications (when in Switcher mode)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 35)
                    .padding(.bottom, 15)
                
                if viewMode == .grid {
                    SmartGridView(
                        items: appService.hiddenRunningApps,
                        onLaunch: { app in appService.launch(app: app) },
                        onUpdateSize: { app, size in appService.setSize(size, for: app.id) },
                        onToggleTag: { _, _ in },
                        onAddTag: { _ in },
                        onQuit: nil,
                        onHide: nil,
                        onRestore: { app in appService.unhideApp(app) },
                        onHoverApp: { app in hoveredAppName = app?.name },
                        availableTags: [],
                        availableWidth: availableWidth,
                        focusedAppID: .constant(nil)
                    )
                    .environmentObject(appService)
                } else {
                    AppListView(
                        items: appService.hiddenRunningApps,
                        onLaunch: { app in appService.launch(app: app) },
                        onQuit: nil,
                        onHide: nil,
                        onRestore: { app in appService.unhideApp(app) },
                        availableTags: [],
                        iconSize: baseIconSize,
                        onToggleTag: { _, _ in },
                        onAddTag: { _ in },
                        onHoverApp: { app in hoveredAppName = app?.name },
                        focusedAppID: .constant(nil)
                    )
                }
            }
            
            // Invisible spacer to ensure there's always a drop target area
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in
                        if appService.canHideApp,
                           let app = appService.runningApps.first(where: { $0.url.path == url.path }) {
                            appService.hiddenAppBundleIDs.insert(app.id)
                        }
                    }
                }
            }
            return true
        }
    }
}

struct AppListView: View {
    let items: [AppItem]
    let onLaunch: (AppItem) -> Void
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let onRestore: ((AppItem) -> Void)?
    let availableTags: [AppTag]
    let iconSize: CGFloat
    let onToggleTag: (AppItem, AppTag) -> Void

    let onAddTag: (AppItem?) -> Void
    let onHoverApp: (AppItem?) -> Void

    @Binding var focusedAppID: String?
    
    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 0) {
                ForEach(items) { app in
                    AppRowView(
                        app: app,
                        onLaunch: onLaunch,
                        onQuit: onQuit,
                        onHide: onHide,
                        onRestore: onRestore,
                        availableTags: availableTags,
                        iconSize: iconSize,
                        onToggleTag: onToggleTag,
                        onAddTag: onAddTag,
                        onHoverApp: onHoverApp,
                        isFocused: focusedAppID == app.id
                    )
                    .id(app.id)
                    
                    Divider()
                        .padding(.leading, 56)
                        .opacity(0.5)
                }
            }
            .onChange(of: focusedAppID) { _, newValue in
                 if let id = newValue {
                     withAnimation {
                         proxy.scrollTo(id, anchor: .center)
                     }
                 }
            }
            .onKeyPress(.return) {
                 if let id = focusedAppID, let app = items.first(where: { $0.id == id }) {
                     onLaunch(app)
                     return .handled
                 }
                 return .ignored
            }
        }
    }
}

struct AppRowView: View {
    let app: AppItem
    let onLaunch: (AppItem) -> Void
    let onQuit: ((AppItem) -> Void)?
    let onHide: ((AppItem) -> Void)?
    let onRestore: ((AppItem) -> Void)?
    let availableTags: [AppTag]
    let iconSize: CGFloat
    let onToggleTag: (AppItem, AppTag) -> Void
    let onAddTag: (AppItem?) -> Void
    let onHoverApp: (AppItem?) -> Void
    let isFocused: Bool


    @EnvironmentObject var appService: AppService
    @State private var hoveredAppId: String? = nil
    
    private var isRunning: Bool {
        appService.runningApps.contains(where: { $0.id == app.id })
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.shared.icon(for: app, size: iconSize))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            
            Text(app.name)
                .font(.body)
                .foregroundColor(isFocused ? .white : .primary)
            
            Spacer()
            
            // Running indicator
            if isRunning {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.gray)
                    .help("Running")
            }
            
            // Show tags in list?
            if !app.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(availableTags.filter { app.tags.contains($0.id) }) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.fromHex(tag.colorHex ?? "#888888"))
                            )
                            .help(tag.name)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isFocused ? appService.accentColor : (hoveredAppId == app.id ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredAppId = isHovering ? app.id : nil
            onHoverApp(isHovering ? app : nil)
        }
        .onTapGesture {
            onLaunch(app)
        }
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
                         Button("Add New Tag...") { onAddTag(app) }
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


// Disables the default system selection highlight on the backing NSTableView/NSOutlineView
struct ListSelectionClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.disableSelectionHighlight(from: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.disableSelectionHighlight(from: nsView)
        }
    }
    
    private func disableSelectionHighlight(from view: NSView) {
        guard let window = view.window else { return }
        disableHighlightRecursive(in: window.contentView)
    }
    
    private func disableHighlightRecursive(in view: NSView?) {
        guard let view = view else { return }
        if let outlineView = view as? NSOutlineView {
            outlineView.selectionHighlightStyle = .none
            return
        }
        if let tableView = view as? NSTableView {
            tableView.selectionHighlightStyle = .none
            return
        }
        for subview in view.subviews {
            disableHighlightRecursive(in: subview)
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
                Label("All Applications", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.allApps)
                    .listRowBackground(selection == .allApps ?
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                            .padding(.horizontal, 6)
                        : nil)
                
                if appService.showOpenApps {
                    Label("Open Applications", systemImage: "macwindow")
                        .tag(SidebarSelection.openApps)
                        .listRowBackground(selection == .openApps ?
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                                .padding(.horizontal, 6)
                            : nil)
                }
                
                if appService.showUtilities {
                    Label("Utilities", systemImage: "wrench.and.screwdriver")
                        .tag(SidebarSelection.utilities)
                        .listRowBackground(selection == .utilities ?
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                                .padding(.horizontal, 6)
                            : nil)
                }

                // Headless apps: CLI tools, package-manager installs, services.
                // Read-only viewer in v1; Pro adds execution in v2 (see headless-plan.md).
                if appService.showHeadless {
                    Label("Headless", systemImage: "terminal")
                        .tag(SidebarSelection.headless)
                        .listRowBackground(selection == .headless ?
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                                .padding(.horizontal, 6)
                            : nil)
                }
            }
            
            Section("TAGS") {
                ForEach(appService.displayTags) { tag in
                    TagRow(tag: tag, editingTagId: $editingTagId, focusedField: $focusedField)
                        .tag(SidebarSelection.tag(tag.id))
                        .listRowBackground(selection == .tag(tag.id) ?
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                                .padding(.horizontal, 6)
                            : nil)
                }
                .onMove(perform: appService.moveTag)
                
                Label("Untagged", systemImage: "tag.slash")
                    .tag(SidebarSelection.untagged)
                    .listRowBackground(selection == .untagged ?
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(isSidebarFocused ? 0.4 : 0.2))
                            .padding(.horizontal, 6)
                        : nil)
                
                Button(action: {
                    guard let newTag = appService.addTag(name: "New Tag") else { return }
                    selection = .tag(newTag.id)
                    editingTagId = newTag.id
                    focusedField = newTag.id
                }) {
                    HStack {
                        Label("Add New Tag...", systemImage: "plus.circle")
                        if !appService.canAddTag {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!appService.canAddTag)
            }
        }
        .tint(.gray)
        .focused($isSidebarFocused)
        .background(ListSelectionClearer())
        .onChange(of: selection) { _, _ in
            appService.activeFocusZone = .sidebar
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                Text(AppService.isPro ? "ZoneKey Pro" : "ZoneKey")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                Divider()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let shortcut = appService.appSwitcherShortcutFormatted {
                VStack(spacing: 0) {
                    Divider()
                    Text("Switcher Mode: \(shortcut)")
                        .font(.system(size: 12))
                        .foregroundColor(appService.accentColor)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .background(.regularMaterial)
            }
        }

    }
}

struct TagRow: View {
    let tag: AppTag
    @Binding var editingTagId: UUID?
    @FocusState.Binding var focusedField: UUID?
    
    @EnvironmentObject var appService: AppService
    @State private var isTargeted = false
    @State private var showDeleteConfirmation = false
    
    private func colorSwatch(hex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(Color.fromHex(hex)).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.fromHex(tag.colorHex ?? "#888888"))
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                }
                Spacer()
                
                if appService.showTagCount {
                    Text("\(appService.apps.filter { $0.tags.contains(tag.id) }.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                
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
                .fill(isTargeted ? appService.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
             RoundedRectangle(cornerRadius: 6)
                 .stroke(isTargeted ? appService.accentColor : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button("Rename") {
                editingTagId = tag.id
                focusedField = tag.id
            }
            
            Menu("Color") {
                let tagColors: [(String, String)] = [
                    ("Red", "#FF3B30"),
                    ("Orange", "#FF9500"),
                    ("Yellow", "#FFCC00"),
                    ("Green", "#34C759"),
                    ("Teal", "#5AC8FA"),
                    ("Blue", "#007AFF"),
                    ("Indigo", "#5856D6"),
                    ("Purple", "#AF52DE"),
                    ("Pink", "#FF2D55"),
                    ("Gray", "#8E8E93")
                ]
                
                ForEach(tagColors, id: \.1) { name, hex in
                    Button(action: { appService.setTagColor(id: tag.id, colorHex: hex) }) {
                        Label {
                            Text(name)
                        } icon: {
                            Image(nsImage: colorSwatch(hex: hex))
                        }
                    }
                    .disabled(tag.colorHex == hex)
                }
                
                Divider()
                
                Button(action: { appService.setTagColor(id: tag.id, colorHex: nil) }) {
                    Label("No Color", systemImage: "circle.dashed")
                }
                .disabled(tag.colorHex == nil)
            }
            
            if appService.tagSortMode == .manual {
                Divider()
                
                Button("Move Up") {
                    if let idx = appService.tags.firstIndex(where: { $0.id == tag.id }), idx > 0 {
                        appService.tags.move(fromOffsets: IndexSet(integer: idx), toOffset: idx - 1)
                        appService.savePreferencesNow()
                    }
                }
                .disabled(appService.tags.first?.id == tag.id)
                
                Button("Move Down") {
                    if let idx = appService.tags.firstIndex(where: { $0.id == tag.id }), idx < appService.tags.count - 1 {
                        appService.tags.move(fromOffsets: IndexSet(integer: idx), toOffset: idx + 2)
                        appService.savePreferencesNow()
                    }
                }
                .disabled(appService.tags.last?.id == tag.id)
                
                Divider()
            }
            
            Button("Remove Tag", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .alert("Remove \"\(tag.name)\" from sidebar?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                appService.deleteTag(id: tag.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will only remove the tag filter. No apps will be deleted.")
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
    @Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 22)
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        if isFocused {
            DispatchQueue.main.async {
                if let window = nsView.window, window.firstResponder != nsView.currentEditor() && window.firstResponder != nsView {
                     window.makeFirstResponder(nsView)
                }
            }
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
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }
    }
}
}
