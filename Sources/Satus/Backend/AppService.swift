import Foundation
import AppKit
import ServiceManagement
import SwiftUI

@MainActor
class AppService: ObservableObject {
    static weak var shared: AppService?
    
    // MARK: - Pro/Free Version Gating
    static var isPro: Bool {
        #if SATUS_PRO
        return true
        #else
        return false
        #endif
    }
    static let freeTagLimit = 3
    static let freeHiddenAppLimit = 3
    
    var canAddTag: Bool {
        AppService.isPro || tags.count < AppService.freeTagLimit
    }
    
    var canHideApp: Bool {
        AppService.isPro || hiddenAppBundleIDs.count < AppService.freeHiddenAppLimit
    }
    
    // Pin mode: prevents auto-close when active
    @Published var isPinned: Bool = false

    // Settings open: prevents auto-close while Settings (and any sheet
    // nested in it, like Tag Setup or Review) is on screen.
    @Published var isSettingsOpen: Bool = false
    
    @Published var apps: [AppItem] = []
    @Published var tags: [AppTag] = []
    
    // Sizing
    @Published var iconScale: Double = 1.5 {
        didSet { savePreferences() }
    }
    @Published var dockTileSize: Int = 64 // Default fallback
    @Published var appTheme: String = "system" { // system, dark, light
        didSet { savePreferences() }
    }
    @Published var viewMode: AppViewMode = .grid {
        didSet { savePreferences() }
    }
    
    // Sidebar Visibility
    @Published var showOpenApps: Bool = true {
        didSet { savePreferences() }
    }
    @Published var showUtilities: Bool = true {
        didSet { savePreferences() }
    }
    @Published var showTagCount: Bool = true {
        didSet { savePreferences() }
    }
    
    // Hidden Apps (excluded from Open Apps view)
    @Published var hiddenAppBundleIDs: Set<String> = [] {
        didSet { savePreferences() }
    }
    
    @Published var tagSortMode: TagSortMode = .manual {
        didSet { savePreferences() }
    }
    
    @Published var isDebugMode: Bool = false {
        didSet { 
            savePreferences()
            UserDefaults.standard.set(isDebugMode, forKey: "isDebugMode")
        }
    }
    
    @Published var defaultTagId: UUID? = nil
    
    // Keyword Cache
    @Published var appKeywords: [String: [String]] = [:] { // BundleID : Keywords
        didSet { savePreferences() }
    }
    @Published var lastKeywordFetchDate: Date? = nil {
        didSet { savePreferences() }
    }
    
    // Accent Color
    @Published var accentColorHex: String = "#FF9500" {
        didSet { savePreferences() }
    }
    
    var accentColor: Color {
        Color.fromHex(accentColorHex)
    }

    

    

    
    // Transient state for focus management
    @Published var triggeredByShortcut: Bool = false

    @Published var lastShortcutTime: Date = .distantPast
    @Published var switcherTargetID: String? = nil // Robust tracking for Switcher
    
    private var eventMonitor: Any?
    
    // File System Monitoring
    private var folderMonitors: [DispatchSourceFileSystemObject] = []
    private var debounceTimer: Timer?
    
    func startMonitoringApps() {
        // Clear existing
        folderMonitors.forEach { $0.cancel() }
        folderMonitors.removeAll()
        
        let paths = [
            "/Applications",
            "/System/Applications",
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first?.path ?? ("\(NSHomeDirectory())/Applications")
        ]
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            // Ensure directory exists before monitoring
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            
            let descriptor = open(url.path, O_EVTONLY)
            if descriptor == -1 { continue }
            
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
            
            source.setEventHandler { [weak self] in
                self?.handleAppDirectoryChange()
            }
            
            source.setCancelHandler {
                close(descriptor)
            }
            
            source.resume()
            folderMonitors.append(source)
            print("Monitoring for apps in: \(path)")
        }
    }
    
    private func handleAppDirectoryChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            print("App Directory Changed. Reloading apps...")
            Task { @MainActor in
                self?.loadApps()
            }
        }
    }
    
    var displayTags: [AppTag] {
        switch tagSortMode {
        case .manual:
            return tags
        case .alphabetical:
            return tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .frequency:
            return tags.sorted {
                if $0.usageCount == $1.usageCount {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.usageCount > $1.usageCount
            }
        }
    }
    
    // Focus State for Navigation
    enum FocusZone {
        case sidebar
        case grid
        case search
    }
    
    @Published var activeFocusZone: FocusZone = .sidebar
    @Published var sidebarSelection: SidebarSelection? = .allApps
    @Published var focusedAppID: String? = nil // For grid navigation
    @Published var isSidebarFocused: Bool = true // Computed/Synced with activeFocusZone? No, let's replace this.
    
    // Dock Visibility
    @Published var showInDock: Bool = false {
        didSet {
            savePreferences()
            NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
            if showInDock {
                // If switching to regular, we might need to reactivate to show dock icon properly?
                // Usually automatic.
            }
        }
    }
    
    // Launch at Login
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }

    
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.shimonshmueli.ZoneKey.save", qos: .utility)
    private let persistenceURL: URL?
    
    init() {
        self.isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        if self.isSandboxed {
            print("🔒 App is running in Sandbox mode.")
        } else {
            print("🔓 App is NOT sandboxed.")
        }
        
        print("🚀 AppService init start")
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("AppLibrary")
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            
            // Debug / Dev Isolation
            #if DEBUG
            self.persistenceURL = appDir.appendingPathComponent("user_prefs_dev.json")
            print("🔧 Using DEV persistence: user_prefs_dev.json")
            #else
            self.persistenceURL = appDir.appendingPathComponent("user_prefs_v2.json")
            #endif
        } else {
            self.persistenceURL = nil
        }
        
        // Potential crashers?
        // readDockTileSize() // Disabled for performance
        checkDockPersistence()
        loadApps()
        setupObservers()
        startMonitoringApps()
        
    // Enforce clean start state
        self.activeFocusZone = .sidebar
        self.sidebarSelection = .allApps
        self.focusedAppID = nil
        
        AppService.shared = self
    }
    
    // Sandbox State
    let isSandboxed: Bool
    
    
    
    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
             DispatchQueue.main.async {
                 self?.objectWillChange.send()
             }
        }
        
        let defaultCenter = NotificationCenter.default
        // Detect when App Hide (CMD+H or dock click)
        defaultCenter.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Trigger keyword prefetch if needed (older than 1 day or nil)
                guard let self = self else { return }
                if let lastFetch = self.lastKeywordFetchDate {
                    let daysSinceFetch = Calendar.current.dateComponents([.day], from: lastFetch, to: Date()).day ?? 0
                    if daysSinceFetch >= 1 {
                        self.prefetchKeywords()
                    }
                } else {
                    self.prefetchKeywords()
                }
            }
        }
        
        // Detect App Termination
        defaultCenter.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
             // Reset icon on quit
             Task { @MainActor in
                 if self != nil {
                    let dockTile = NSApplication.shared.dockTile
                    dockTile.badgeLabel = nil
                 }
             }
        }
        
        setupEventMonitor()
    }
    
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let key = event.keyCode
            if self.isDebugMode { print("DEBUG: Key Down: \(key), Zone: \(self.activeFocusZone)") }
            
            // Priority Check: Escape (53) should always trigger, regardless of focus
            if key == 53 {
                 if let keyWindow = NSApplication.shared.keyWindow {
                      if keyWindow.title == "ZoneKey Help" || keyWindow.title.starts(with: "About ") {
                          keyWindow.close()
                          return nil
                      }
                 }
                 
                 if !self.isPinned {
                     NSApplication.shared.hide(nil)
                 }
                 return nil
            }
            
            // Avoid hijacking Search Bar (NSTextView is the field editor) for other keys
            if let window = NSApplication.shared.keyWindow,
               let _ = window.firstResponder as? NSTextView {
                return event
            }
            
            switch key {
            case 36: // Return
                let targetID = self.focusedAppID ?? self.switcherTargetID
                if let id = targetID,
                   let app = self.apps.first(where: { $0.id == id }) {
                    self.launch(app: app)
                    return nil
                }
                return event
                
            case 48: // Tab
                if self.activeFocusZone == .sidebar {
                    if self.isDebugMode { print("DEBUG: Tab from Sidebar -> Search") }
                    self.activeFocusZone = .search
                    self.sidebarSelection = .allApps // Ensure we search all apps
                    return nil // Consume event
                }
                return event

            // ARROW KEYS (123-126)
            case 123: // Left
                self.handleArrowKey(.left)
                return nil
            case 124: // Right
                self.handleArrowKey(.right)
                return nil
            case 125: // Down
                self.handleArrowKey(.down)
                return nil
            case 126: // Up
                self.handleArrowKey(.up)
                return nil
            default:
                return event
            }
        }
    }
    
    func readDockTileSize() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "tilesize"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let size = Int(output) {
                // If the user's dock is tiny (e.g. 35), we might want a minimum sanity check?
                // User asked for default to be SAME as dock.
                self.dockTileSize = size
            }
        } catch {
            print("Failed to read dock size: \(error)")
        }
        }

    
    func checkDockPersistence() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "persistent-apps"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("com.shimonshmueli.ZoneKey") {
                    print("Found in Dock! Syncing preference.")
                    DispatchQueue.main.async {
                        self.showInDock = true
                    }
                }
            }
        } catch {
            print("Failed to check dock persistence: \(error)")
        }
    }
    
    // MARK: - Discovery
    func loadApps() {
        print("Scanning for applications...")
        var discoveredApps: [AppItem] = []
        
        let appsPath = "/Applications"
        let sysAppsPath = "/System/Applications"
        
        let rootApps = scanDirectory(at: URL(fileURLWithPath: appsPath))
        let systemApps = scanDirectory(at: URL(fileURLWithPath: sysAppsPath))
        let userApps = scanDirectory(at: fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "~/Applications"))
        
        discoveredApps.append(contentsOf: rootApps)
        discoveredApps.append(contentsOf: systemApps)
        discoveredApps.append(contentsOf: userApps)
        // Log duplicates before set
        let duplicates = Dictionary(grouping: discoveredApps, by: { $0.id }).filter { $1.count > 1 }
        for (id, apps) in duplicates {
            print("Duplicate ID found: \(id) -> \(apps.count) copies")
        }
        
        discoveredApps = Array(Set(discoveredApps))
        
        // Filter out self
        if let myBundleID = Bundle.main.bundleIdentifier {
            discoveredApps.removeAll { $0.id == myBundleID }
        }
        
        applyPersistence(to: &discoveredApps)
        
        // Migration: Rename "Other" -> "Utilities" if it exists (from old persistence)
        if let otherIndex = tags.firstIndex(where: { $0.name == "Other" }) {
            print("Migrating 'Other' tag to 'Utilities'")
            var tag = tags[otherIndex]
            tag.name = "Utilities"
            tags[otherIndex] = tag
            savePreferences()
        }
        
        self.apps = discoveredApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        if self.tags.isEmpty {
            // Seven seed tags applied to both Free and Pro on first launch.
            // Each carries a color so users see a coherent palette out of the box.
            self.tags = DefaultTags.all.map {
                AppTag(name: $0.name, colorHex: $0.colorHex)
            }
        }
        
        let currentSwitcher = GlobalHotkey.shared.getShortcut(id: 6)
        
        if currentSwitcher == nil || currentSwitcher?.keyCode == 0 {
            print("Pre-populating App Switcher shortcut to Option+Tab (Default)")
            GlobalHotkey.shared.setShortcut(id: 6, keyCode: 48, modifiers: Int(NSEvent.ModifierFlags.option.rawValue))
        }
    }
    
    // MARK: - Keyword Prefetching
    func prefetchKeywords() {
        print("Prefetching keywords for apps in background...")
        Task.detached(priority: .background) {
            var fetchedKeywords: [String: [String]] = [:]
            
            // Need a snapshot of apps array to process safely in background
            let currentApps = await self.apps
            
            for app in currentApps {
                var appKeywordsList: [String] = []
                
                // 1. MDItem Spotlight attributes
                if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, app.url as CFURL) {
                    if let mdKeywords = MDItemCopyAttribute(mdItem, kMDItemKeywords) as? [String] {
                        appKeywordsList.append(contentsOf: mdKeywords)
                    }
                    if let description = MDItemCopyAttribute(mdItem, kMDItemDescription) as? String, !description.isEmpty {
                        appKeywordsList.append(description)
                    }
                    if let copyright = MDItemCopyAttribute(mdItem, kMDItemCopyright) as? String, !copyright.isEmpty {
                        // Extract company/dev name from copyright (e.g. "© 2024 Apple Inc." -> "Apple")
                        let words = copyright.components(separatedBy: .whitespacesAndNewlines)
                            .filter { $0.count > 2 && !$0.starts(with: "©") && !$0.starts(with: "(") && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: $0)) }
                        appKeywordsList.append(contentsOf: words)
                    }
                }
                
                // 2. Bundle Info.plist metadata
                if let bundle = Bundle(url: app.url), let info = bundle.infoDictionary {
                    // App category (e.g. "public.app-category.productivity" -> "productivity")
                    if let category = info["LSApplicationCategoryType"] as? String {
                        let categoryName = category.replacingOccurrences(of: "public.app-category.", with: "")
                            .replacingOccurrences(of: "-", with: " ")
                        appKeywordsList.append(categoryName)
                    }
                    
                    // Human-readable copyright from Info.plist
                    if let copyright = info["NSHumanReadableCopyright"] as? String, !copyright.isEmpty {
                        let words = copyright.components(separatedBy: .whitespacesAndNewlines)
                            .filter { $0.count > 2 && !$0.starts(with: "©") && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: $0)) }
                        appKeywordsList.append(contentsOf: words)
                    }
                }
                
                // Deduplicate
                let uniqueKeywords = Array(Set(appKeywordsList.map { $0.lowercased() }))
                    .filter { !$0.isEmpty }
                
                if !uniqueKeywords.isEmpty {
                    fetchedKeywords[app.id] = uniqueKeywords
                }
            }
            
            let finalKeywords = fetchedKeywords
            await MainActor.run {
                self.appKeywords = finalKeywords
                self.lastKeywordFetchDate = Date()
                print("Keyword prefetch complete. Keywords stored for \(finalKeywords.count) apps.")
                // Log a sample for debugging
                for (id, kw) in finalKeywords.prefix(5) {
                    print("  \(id): \(kw)")
                }
            }
        }
    }
    
    private func scanDirectory(at url: URL) -> [AppItem] {
        var items: [AppItem] = []
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isApplicationKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { return [] }
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "app" else { continue }
            if let bundle = Bundle(url: fileURL), let info = bundle.infoDictionary, let rawID = bundle.bundleIdentifier {
                let bundleID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fileURL.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                let category = info["LSApplicationCategoryType"] as? String
                items.append(AppItem(id: bundleID, name: name, icon: icon, url: fileURL, category: category))
            }
        }
        return items
    }
    
    // MARK: - Actions
    var runningApps: [AppItem] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return apps.filter { runningBundleIDs.contains($0.id) && !hiddenAppBundleIDs.contains($0.id) }
    }
    
    var hiddenRunningApps: [AppItem] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return apps.filter { runningBundleIDs.contains($0.id) && hiddenAppBundleIDs.contains($0.id) }
    }
    
    func unhideApp(_ app: AppItem) {
        if hiddenAppBundleIDs.contains(app.id) {
            hiddenAppBundleIDs.remove(app.id)
            savePreferences()
        }
    }
    
    func launch(app: AppItem) {
        triggeredByShortcut = false
        // Prevent ghosting on return
        if switcherTargetID != nil {
            switcherTargetID = nil 
        }
        
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    func quitApp(app: AppItem) {
        if isDebugMode { print("DEBUG: Attempting to quit app: \(app.name) (\(app.id))") }
        let running = NSWorkspace.shared.runningApplications
        if let target = running.first(where: { $0.bundleIdentifier == app.id }) {
            let success = target.terminate()
            if isDebugMode { print("DEBUG: Terminate called on \(app.name). Success: \(success)") }
        } else {
             if isDebugMode { print("DEBUG: Could not find running app for \(app.id)") }
        }
    }
    
    // createGroup removed
    
    func addTag(name: String) -> AppTag? {
        guard canAddTag else { return nil }
        let newTag = AppTag(name: name)
        tags.append(newTag)
        savePreferences()
        return newTag
    }
    
    func recordTagUsage(id: UUID) {
        if let index = tags.firstIndex(where: { $0.id == id }) {
            var tag = tags[index]
            tag.usageCount += 1
            if isDebugMode { print("DEBUG: Tag '\(tag.name)' usage incremented to \(tag.usageCount)") }
            tags[index] = tag
            savePreferences()
        }
    }
    
    func renameTag(id: UUID, newName: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index] = AppTag(id: tags[index].id, name: newName, colorHex: tags[index].colorHex, items: tags[index].items)
        savePreferences()
    }
    
    func setTagColor(id: UUID, colorHex: String?) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        var tag = tags[index]
        tag.colorHex = colorHex
        tags[index] = tag
        savePreferences()
    }
    
    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        // Clean up checking apps?
        for i in 0..<apps.count {
            if apps[i].tags.contains(id) {
                apps[i].tags.remove(id)
            }
        }
        savePreferences()
    }
    
    func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        savePreferences()
    }
    
    func savePreferencesNow() {
        savePreferences()
    }
    
    // setHeroApp removed

    private var saveTask: Task<Void, Error>?
    
    // ...
    
    func assignTag(_ tag: AppTag, to appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        if !apps[index].tags.contains(tag.id) {
            apps[index].tags.insert(tag.id)
            savePreferences()
        }
    }
    
    func assignTag(_ tag: AppTag, toAppWithURL url: URL) {
        guard let app = apps.first(where: { $0.url.path == url.path }) else { return }
        assignTag(tag, to: app.id)
    }
    


    func setSize(_ size: AppSize, for appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].size = size
        savePreferences()
    }
    
    // ... (rest of methods)
    
    func toggleTag(_ tag: AppTag, for appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        if apps[index].tags.contains(tag.id) {
            apps[index].tags.remove(tag.id)
        } else {
            apps[index].tags.insert(tag.id)
        }
        savePreferences()
    }
    
    // ...
    
    func getPreferencesSnapshot() -> UserPreferences {
        let appSettings = apps.filter { !$0.tags.isEmpty }
            .map { AppItemDTO(id: $0.id, tagIDs: $0.tags) }
        
        let tagSettings = tags.map { AppTagDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex, items: $0.items, usageCount: $0.usageCount) }
        
        return UserPreferences(tags: tagSettings, appSettings: appSettings, iconScale: iconScale, appTheme: appTheme, viewMode: viewMode, shortcutMapping: shortcutTagMapping, showOpenApps: showOpenApps, showUtilities: showUtilities, showTagCount: showTagCount, hiddenAppBundleIDs: Array(hiddenAppBundleIDs), sortTagsAlphabetically: nil, tagSortMode: tagSortMode, isDebugMode: isDebugMode, defaultTagId: defaultTagId, appKeywords: appKeywords, lastKeywordFetchDate: lastKeywordFetchDate, accentColorHex: accentColorHex)
    }

    func restorePreferences(_ prefs: UserPreferences) {
        // Apply properties
        if let scale = prefs.iconScale { self.iconScale = scale }
        if let theme = prefs.appTheme { self.appTheme = theme }
        if let mode = prefs.viewMode { self.viewMode = mode }
        if let mapping = prefs.shortcutMapping { self.shortcutTagMapping = mapping }
        if let showOpen = prefs.showOpenApps { self.showOpenApps = showOpen }
        if let showUtils = prefs.showUtilities { self.showUtilities = showUtils }
        if let hiddenIDs = prefs.hiddenAppBundleIDs { self.hiddenAppBundleIDs = Set(hiddenIDs) }
        if let mode = prefs.tagSortMode {
            self.tagSortMode = mode
        } else if let legacySort = prefs.sortTagsAlphabetically {
            self.tagSortMode = legacySort ? .alphabetical : .manual
        }
        if let debug = prefs.isDebugMode { self.isDebugMode = debug }
        if let defaultTag = prefs.defaultTagId { self.defaultTagId = defaultTag }
        if let keywords = prefs.appKeywords { self.appKeywords = keywords }
        if let fetchDate = prefs.lastKeywordFetchDate { self.lastKeywordFetchDate = fetchDate }
        if let hex = prefs.accentColorHex { self.accentColorHex = hex }

        
        // Restore Tags
        self.tags = prefs.tags.map {
            var t = AppTag(id: $0.id, name: $0.name, colorHex: $0.colorHex, items: $0.items)
            t.usageCount = $0.usageCount ?? 0
            return t
        }
        
        // Restore App Tags
        let settingsMap = Dictionary(uniqueKeysWithValues: prefs.appSettings.map { ($0.id, $0) })
        for i in 0..<apps.count {
            if let settings = settingsMap[apps[i].id] {
                apps[i].tags = settings.tagIDs
            } else {
                apps[i].tags = [] // Reset if not in snapshot? Yes, restore means revert.
            }
        }
        
        savePreferences()
    }

    private func savePreferences() {
        saveTask?.cancel()
        saveTask = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1s Debounce
            if Task.isCancelled { return }
            
            if isDebugMode { print("DEBUG: Capturing state for save at \(Date())") }
            guard let url = persistenceURL else { return }
            
            let prefs = getPreferencesSnapshot()
            let debugMode = isDebugMode
            
            saveQueue.async {
                do {
                    let data = try JSONEncoder().encode(prefs)
                    try data.write(to: url)
                    if debugMode { print("DEBUG: Save completed at \(Date())") }
                } catch {
                    print("Failed to save: \(error)")
                }
            }
        }
    }
    
    func getItemsForTag(_ tag: AppTag) -> [AppItem] {
        let tagApps = apps.filter { $0.tags.contains(tag.id) }
        return tagApps.sorted { (a, b) -> Bool in
            let idxA = tag.items.firstIndex(of: a.id) ?? Int.max
            let idxB = tag.items.firstIndex(of: b.id) ?? Int.max
            return idxA < idxB
        }
    }
    
    // MARK: - Shortcuts
    
    // Mapping for Shortcuts 4, 5 -> Tag UUID
    @Published var shortcutTagMapping: [Int: UUID] = [:] {
        didSet { savePreferences() }
    }
    
    enum ShortcutAction {
        case navigate(SidebarSelection)
        case appSwitcher
    }
    
    var appSwitcherShortcutFormatted: String? {
        guard viewMode == .grid else { return nil }
        return GlobalHotkey.shared.getShortcutString(id: 6)
    }

    // MARK: - Navigation & Filtering
    
    var currentGridApps: [AppItem] {
        // 1. Text Search
        // Note: We need searchText to be in AppService to filter here?
        // Let's rely on the caller/view to handle search for now? 
        // OR move searchText to AppService.
        // For Arrow Navigation to work, AppService needs the TRUTH.
        // Ideally, searchText should be in AppService.
        return getGridApps(searchText: searchText)
    }
    
    @Published var searchText: String = ""
    
    func getGridApps(searchText: String) -> [AppItem] {
        if !searchText.isEmpty {
            let matchedApps = apps.filter { app in
                // Check name match
                if app.name.isFuzzyMatch(with: searchText) { return true }
                
                // Check pre-fetched keywords
                if let keywords = appKeywords[app.id] {
                    for keyword in keywords {
                        if keyword.isFuzzyMatch(with: searchText) { return true }
                    }
                }
                return false
            }
            
            return matchedApps.sorted { appA, appB in
                let scoreA = appA.name.fuzzyMatchScore(with: searchText)
                let scoreB = appB.name.fuzzyMatchScore(with: searchText)
                
                if scoreA != scoreB {
                    return scoreA > scoreB
                }
                return appA.name.localizedStandardCompare(appB.name) == .orderedAscending
            }
        }
        
        guard let sel = sidebarSelection else { return apps }
        
        switch sel {
        case .allApps:
            return apps
        case .openApps:
            return runningApps
        case .utilities:
            return apps.filter {
                if $0.category == "public.app-category.utilities" { return true }
                if let path = $0.url.path.removingPercentEncoding {
                    return path.hasPrefix("/Applications/Utilities") || path.hasPrefix("/System/Applications/Utilities")
                }
                return false
            }
        case .untagged:
            return apps.filter { $0.tags.isEmpty }
        case .tag(let tagId):
            if let tag = tags.first(where: { $0.id == tagId }) {
                return getItemsForTag(tag)
            }
            return []
        }
    }
    
    enum ArrowDirection {
        case up, down, left, right
    }
    
    func handleArrowKey(_ direction: ArrowDirection) {
        if activeFocusZone == .sidebar {
            navigateSidebar(direction)
        } else {
            navigateGrid(direction)
        }
    }
    
    private func navigateSidebar(_ direction: ArrowDirection) {
        // List of sidebar items in order
        var items: [SidebarSelection] = [.allApps]
        if showOpenApps { items.append(.openApps) }
        if showUtilities { items.append(.utilities) }
        
        // Tags
        let sortedTags = displayTags
        items.append(contentsOf: sortedTags.map { .tag($0.id) })
        
        // Untagged
        items.append(.untagged)
        
        guard let current = sidebarSelection,
              let idx = items.firstIndex(of: current) else {
            sidebarSelection = .allApps
            return
        }
        
        switch direction {
        case .up:
            let newIdx = max(0, idx - 1)
            sidebarSelection = items[newIdx]
        case .down:
            let newIdx = min(items.count - 1, idx + 1)
            sidebarSelection = items[newIdx]
        case .right:
            // Switch to Grid
            activeFocusZone = .grid
            // Select first app if nothing selected
            if focusedAppID == nil {
                focusedAppID = getGridApps(searchText: searchText).first?.id
            }
        case .left:
            break // Stay in sidebar
        }
    }
    
    @Published var contentWidth: CGFloat = 800
    
    // Derived icon size for column calc
    var effectiveIconSize: CGFloat {
        CGFloat(Double(dockTileSize) * iconScale)
    }

    private func navigateGrid(_ direction: ArrowDirection) {
        let apps = getGridApps(searchText: searchText)
        guard !apps.isEmpty else { return }
        
        // Ensure focusedAppID is valid or default to first
        let currentIdx = apps.firstIndex(where: { $0.id == focusedAppID }) ?? 0
        if focusedAppID == nil { focusedAppID = apps[currentIdx].id }
        
        let isListMode = (viewMode == .list)
        
        // Calculate Columns
        // Smart Grid: adaptive(min: effectiveIconSize)
        // Item Width = effectiveIconSize + padding (approx 40)
        // This must match SmartGridView calculation
        let itemWidth = effectiveIconSize + 40
        // Use a safe width (prevent 0 or too small)
        let safeWidth = max(contentWidth, 300)
        let columns = isListMode ? 1 : max(1, Int(safeWidth / itemWidth))
        
        switch direction {
        case .left:
            if isListMode {
                // List Mode: Left = Up in List
                if currentIdx == 0 {
                    activeFocusZone = .sidebar
                    focusedAppID = nil
                } else {
                    let newIdx = max(0, currentIdx - 1)
                    focusedAppID = apps[newIdx].id
                }
            } else {
                // Grid Mode: Visual Left
                // If at Left Edge -> Sidebar ? NO, User requested to Disable this.
                if currentIdx % columns == 0 {
                    // Navigate to Sidebar
                    activeFocusZone = .sidebar
                    focusedAppID = nil
                } else {
                    let newIdx = max(0, currentIdx - 1)
                    focusedAppID = apps[newIdx].id
                }
            }
        case .right:
            // "then on without round robin"
            // List: Right = Down (Index + 1)
            // Grid: Right = Index + 1
            let newIdx = min(apps.count - 1, currentIdx + 1)
            focusedAppID = apps[newIdx].id
            
        case .up:
            // Grid: Index - columns
            // List: Index - 1
            let stride = isListMode ? 1 : columns
            let newIdx = max(0, currentIdx - stride)
            focusedAppID = apps[newIdx].id
            
        case .down:
            // Grid: Index + columns
            // List: Index + 1
            let stride = isListMode ? 1 : columns
            let newIdx = min(apps.count - 1, currentIdx + stride)
            focusedAppID = apps[newIdx].id
        }
    }


    func handleShortcut(id: Int) -> ShortcutAction? {
        switch id {
        case 1:
            return .navigate(.allApps)
        case 2:
            return showOpenApps ? .navigate(.openApps) : .navigate(.allApps)
        case 3:
            return showUtilities ? .navigate(.utilities) : .navigate(.allApps)
        case 6:
            // Special App Switcher Mode (Handle rejection in View)
            return .appSwitcher
        default:
            if let tagId = shortcutTagMapping[id] {
                recordTagUsage(id: tagId)
                return .navigate(.tag(tagId))
            }
            return nil
        }
    }
    
    // MARK: - Persistence
    struct UserPreferences: Codable {
        let tags: [AppTagDTO]
        let appSettings: [AppItemDTO]
        let iconScale: Double?

        let appTheme: String?
        let viewMode: AppViewMode?
        
        let shortcutMapping: [Int: UUID]?
        
        let showOpenApps: Bool?
        let showUtilities: Bool?
        let showTagCount: Bool?
        let hiddenAppBundleIDs: [String]?
        let sortTagsAlphabetically: Bool?
        let tagSortMode: TagSortMode?
        let isDebugMode: Bool?
        let defaultTagId: UUID?
        let appKeywords: [String: [String]]?
        let lastKeywordFetchDate: Date?
        let accentColorHex: String?
    }
    
    struct ExportManifest: Codable {
        let tags: [AppTagDTO]
    }
    
    // MARK: - Export / Import
    func exportData() -> String? {
        // Only export tags (and their app associations via 'items')
        // We must ensure 'items' (the list of Bundle IDs) is populated based on the actual 'apps' tags.
        // The AppTag.items property might be stale or empty if not maintained by assignTag.
        
        let tagSettings = tags.map { tag -> AppTagDTO in
             // 1. Find all apps that currently have this tag
             let appsWithTag = apps.filter { $0.tags.contains(tag.id) }
             let appIDsWithTag = Set(appsWithTag.map { $0.id })
             
             // 2. Start with existing items to preserve order, but filter out those no longer tagged
             var finalItems = tag.items.filter { appIDsWithTag.contains($0) }
             
             // 3. Append any apps that are tagged but not in the ordered list
             let existingItemSet = Set(finalItems)
             for app in appsWithTag {
                 if !existingItemSet.contains(app.id) {
                     finalItems.append(app.id)
                 }
             }
             
             return AppTagDTO(id: tag.id, name: tag.name, colorHex: tag.colorHex, items: finalItems, usageCount: tag.usageCount)
        }
        
        let manifest = ExportManifest(tags: tagSettings)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(manifest)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Export failed: \(error)")
            return nil
        }
    }
    
    func importData(from jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        
        // Try decoding as clean Manifest first
        if let manifest = try? JSONDecoder().decode(ExportManifest.self, from: data) {
             print("Importing Clean Manifest...")
             // Create a set of valid app IDs (only installed apps)
             let validAppIDs = Set(self.apps.map { $0.id })
             
             self.tags = manifest.tags.map {
                 // Clean up ghosts
                 let filteredItems = $0.items.filter { validAppIDs.contains($0) }
                 var t = AppTag(id: $0.id, name: $0.name, colorHex: $0.colorHex, items: filteredItems)
                 t.usageCount = $0.usageCount ?? 0
                 return t
             }
             
             // Reconstruct App Associations (App -> Tags)
             // Clear existing tags on apps
             for i in 0..<apps.count {
                 apps[i].tags.removeAll()
             }
             
             // Apply new tags
             for tag in self.tags {
                 for appID in tag.items {
                     if let index = apps.firstIndex(where: { $0.id == appID }) {
                         apps[index].tags.insert(tag.id)
                     }
                 }
             }
             
             objectWillChange.send()
             savePreferences()
             return true
        }
        
        // Fallback: Try decoding as full UserPreferences (Legacy/Internal backup)
        do {
            _ = try JSONDecoder().decode(UserPreferences.self, from: data)
             // ... logic for full restore if needed ...
             // But user asked to split export. Let's support import of legacy just in case?
             // For now, let's focus on the Manifest logic being primary.
             return false // Reject if not manifest? Or support both?
             // Since I changed the export, users might have old exports.
             // But the user request is specific about "When exporting...".
             // Let's keep it simple. If it fails manifest, maybe try prefs?
             // I'll stick to manifest for now as per "Clean Export".
        } catch {
             print("Import failed: \(error)")
             return false
        }
        

    }
    

    
    private func applyPersistence(to apps: inout [AppItem]) {
        guard let url = persistenceURL, let data = try? Data(contentsOf: url), let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else { return }
        
        if let scale = prefs.iconScale {
            self.iconScale = scale
        }
        
        if let theme = prefs.appTheme {
            self.appTheme = theme
        }
        if let mode = prefs.viewMode { self.viewMode = mode }
        
        if let mapping = prefs.shortcutMapping {
             self.shortcutTagMapping = mapping
        }
        
        if let showOpen = prefs.showOpenApps { self.showOpenApps = showOpen }
        if let showUtils = prefs.showUtilities { self.showUtilities = showUtils }
        if let showCount = prefs.showTagCount { self.showTagCount = showCount }
        if let hiddenIDs = prefs.hiddenAppBundleIDs {
            var loadedIDs = Set(hiddenIDs)
            // Enforce free-tier limit: if hidden apps exceed the limit (leftover from PRO),
            // clear them all since they weren't created under the free tier
            if !AppService.isPro && loadedIDs.count > AppService.freeHiddenAppLimit {
                loadedIDs.removeAll()
            }
            self.hiddenAppBundleIDs = loadedIDs
        }
        
        // Migration: sortTagsAlphabetically -> tagSortMode
        if let mode = prefs.tagSortMode {
            self.tagSortMode = mode
        } else if let legacySort = prefs.sortTagsAlphabetically {
            self.tagSortMode = legacySort ? .alphabetical : .manual
        }
        
        if let debug = prefs.isDebugMode { 
            self.isDebugMode = debug
            UserDefaults.standard.set(debug, forKey: "isDebugMode")
        }

                
        if let keywords = prefs.appKeywords {
            self.appKeywords = keywords
        }
        if let fetchDate = prefs.lastKeywordFetchDate {
            self.lastKeywordFetchDate = fetchDate
        }
        
        self.tags = prefs.tags.map {
            var t = AppTag(id: $0.id, name: $0.name, colorHex: $0.colorHex, items: $0.items)
            t.usageCount = $0.usageCount ?? 0
            return t
        }
        
        let settingsMap = Dictionary(uniqueKeysWithValues: prefs.appSettings.map { ($0.id, $0) })
        
        for i in 0..<apps.count {
            if let settings = settingsMap[apps[i].id] {
                apps[i].tags = settings.tagIDs
            }
        }
    }
}
