import Foundation
import AppKit
import ServiceManagement

enum DockItem: Codable, Identifiable, Hashable {
    case app(id: String)
    case group(id: UUID, items: [String])
    
    var id: String {
        switch self {
        case .app(let id): return id
        case .group(let id, _): return id.uuidString
        }
    }
}

@MainActor
class AppService: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var tags: [AppTag] = []
    
    // Sizing
    @Published var iconScale: Double = 1.0 {
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
    
    // Hidden Apps (excluded from Open Apps view)
    @Published var hiddenAppBundleIDs: Set<String> = [] {
        didSet { savePreferences() }
    }
    
    @Published var tagSortMode: TagSortMode = .manual {
        didSet { savePreferences() }
    }
    
    @Published var isDebugMode: Bool = false {
        didSet { savePreferences() }
    }
    

    
    // Transient state for focus management
    @Published var triggeredByShortcut: Bool = false

    @Published var lastShortcutTime: Date = .distantPast
    @Published var switcherTargetID: String? = nil // Robust tracking for Switcher
    
    // Dock Configuration
    @Published var dockItems: [DockItem] = [] {
        didSet { savePreferences() }
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
    @Published var isSidebarFocused: Bool = false
    
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
    private let saveQueue = DispatchQueue(label: "com.shimonshmueli.Satus.save", qos: .utility)
    private let persistenceURL: URL?
    
    init() {
        print("🚀 AppService init start")
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("AppLibrary")
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.persistenceURL = appDir.appendingPathComponent("user_prefs_v2.json")
        } else {
            self.persistenceURL = nil
        }
        
        // Potential crashers?
        readDockTileSize()
        checkDockPersistence()
        loadApps()
        // setupObservers()
    }
    
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
                // UPDATED: User asked for default to be 1.5x Dock.
                self.dockTileSize = Int(Double(size) * 1.5)
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
                if output.contains("com.shimonshmueli.Satus") {
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
        print("Scaning for applications...")
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
            self.tags = [
                AppTag(name: "Productivity"),
                AppTag(name: "Media")
            ]
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
    
    func launch(app: AppItem) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    func quitApp(app: AppItem) {
        let running = NSWorkspace.shared.runningApplications
        if let target = running.first(where: { $0.bundleIdentifier == app.id }) {
            target.terminate()
        }
    }
    
    // createGroup removed
    
    func addTag(name: String) -> AppTag {
        let newTag = AppTag(name: name)
        tags.append(newTag)
        savePreferences()
        return newTag
    }
    
    func recordTagUsage(id: UUID) {
        if let index = tags.firstIndex(where: { $0.id == id }) {
            var tag = tags[index]
            tag.usageCount += 1
            print("DEBUG: Tag '\(tag.name)' usage incremented to \(tag.usageCount)")
            tags[index] = tag
            savePreferences()
        }
    }
    
    func renameTag(id: UUID, newName: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index] = AppTag(id: tags[index].id, name: newName, colorHex: tags[index].colorHex, items: tags[index].items)
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
    
    // MARK: - Dock Management
    func moveDockItem(from source: IndexSet, to destination: Int) {
        dockItems.move(fromOffsets: source, toOffset: destination)
        savePreferences()
    }
    
    func createDockGroup(with items: [String]) {
        let group = DockItem.group(id: UUID(), items: items)
        dockItems.append(group)
        savePreferences()
    }
    
    func groupDockItems(targetId: String, sourceId: String) {
        guard let targetIndex = dockItems.firstIndex(where: { $0.id == targetId }),
              let sourceIndex = dockItems.firstIndex(where: { $0.id == sourceId }) else { return }
        
        let targetItem = dockItems[targetIndex]
        let sourceItem = dockItems[sourceIndex]
        
        var newGroupItems: [String] = []
        
        // Extract IDs
        switch targetItem {
        case .app(let id): newGroupItems.append(id)
        case .group(_, let items): newGroupItems.append(contentsOf: items)
        }
        
        switch sourceItem {
        case .app(let id): newGroupItems.append(id)
        case .group(_, let items): newGroupItems.append(contentsOf: items)
        }
        
        let newGroup = DockItem.group(id: UUID(), items: newGroupItems)
        
        // Robust Removal & Insertion
        // 1. Remove source
        dockItems.remove(at: sourceIndex)
        
        // 2. Find new index of target (it might have shifted)
        if let newTargetIndex = dockItems.firstIndex(where: { $0.id == targetId }) {
            // Replace target with group
            dockItems[newTargetIndex] = newGroup
        } else {
            // Fallback (Shouldn't happen)
            dockItems.append(newGroup)
        }
        
        savePreferences()
    }
    
    func addAppToGroup(groupId: UUID, appId: String) {
        guard let index = dockItems.firstIndex(where: {
            if case .group(let id, _) = $0 { return id == groupId }
            return false
        }) else { return }
        
        if case .group(let id, var items) = dockItems[index] {
            if !items.contains(appId) {
                items.append(appId)
                dockItems[index] = .group(id: id, items: items)
                // Remove app from top level if it exists there
                dockItems.removeAll { item in
                    if case .app(let id) = item { return id == appId }
                    return false
                }
                savePreferences()
            }
        }
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
        
        return UserPreferences(tags: tagSettings, appSettings: appSettings, dockItems: dockItems, iconScale: iconScale, appTheme: appTheme, viewMode: viewMode, shortcutMapping: shortcutTagMapping, showOpenApps: showOpenApps, showUtilities: showUtilities, hiddenAppBundleIDs: Array(hiddenAppBundleIDs), sortTagsAlphabetically: nil, tagSortMode: tagSortMode, isDebugMode: isDebugMode)
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
        
        // Restore Dock
        if let dock = prefs.dockItems {
            self.dockItems = dock
        }
        
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
            
            print("DEBUG: Capturing state for save at \(Date())")
            guard let url = persistenceURL else { return }
            
            let prefs = getPreferencesSnapshot()
            
            saveQueue.async {
                do {
                    let data = try JSONEncoder().encode(prefs)
                    try data.write(to: url)
                    print("DEBUG: Save completed at \(Date())")
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

    func handleShortcut(id: Int) -> ShortcutAction? {
        switch id {
        case 1:
            return .navigate(.allApps)
        case 2:
            // Just navigate to Open Apps view
            return showOpenApps ? .navigate(.openApps) : .navigate(.allApps)
        case 3:
            return showUtilities ? .navigate(.utilities) : .navigate(.allApps)
        case 6:
            // Special App Switcher Mode (Grid only)
            return viewMode == .grid ? .appSwitcher : nil
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
        let dockItems: [DockItem]?
        let iconScale: Double?

        let appTheme: String?
        let viewMode: AppViewMode?
        
        let shortcutMapping: [Int: UUID]?
        
        let showOpenApps: Bool?
        let showUtilities: Bool?
        let hiddenAppBundleIDs: [String]?
        let sortTagsAlphabetically: Bool?
        let tagSortMode: TagSortMode?
        let isDebugMode: Bool?
    }
    
    struct ExportManifest: Codable {
        let tags: [AppTagDTO]
        let dockItems: [DockItem]?
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
        
        let manifest = ExportManifest(tags: tagSettings, dockItems: dockItems)
        
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
             
             // Import Dock
             if let dock = manifest.dockItems {
                 self.dockItems = dock
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
        if let hiddenIDs = prefs.hiddenAppBundleIDs { self.hiddenAppBundleIDs = Set(hiddenIDs) }
        
        // Migration: sortTagsAlphabetically -> tagSortMode
        if let mode = prefs.tagSortMode {
            self.tagSortMode = mode
        } else if let legacySort = prefs.sortTagsAlphabetically {
            self.tagSortMode = legacySort ? .alphabetical : .manual
        }
        
        if let debug = prefs.isDebugMode { self.isDebugMode = debug }
        
        if let dock = prefs.dockItems {
            self.dockItems = dock
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
