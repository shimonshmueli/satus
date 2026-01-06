import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appService: AppService
    @Environment(\.dismiss) var dismiss
    
    struct SettingsSnapshot {
        let preferences: AppService.UserPreferences
        let shortcuts: [HotKeyDefinition]
    }
    
    @State private var snapshot: SettingsSnapshot?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    restoreSnapshot()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Discard Changes")
                
                Spacer()
                
                Text("Settings")
                    .font(.headline)
                
                Spacer()
                
                // Invisible spacer to balance the X for centering title
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }
            .padding()
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
            
            Divider()
            
            Form {
                Section("Appearance") {
                    CustomThemePicker(selection: $appService.appTheme) { clickedTheme in
                        handleThemeClick(clickedTheme)
                    }
                }
                

                
                Section("General") {
                    Toggle("Launch at Login", isOn: $appService.launchAtLogin)
                    
                    Divider()
                    Toggle("Show Open Apps", isOn: $appService.showOpenApps)
                    Toggle("Show Utilities", isOn: $appService.showUtilities)
                    Picker("Sort Tags", selection: $appService.tagSortMode) {
                        Text("Manual").tag(TagSortMode.manual)
                        Text("Alphabetical").tag(TagSortMode.alphabetical)
                        Text("Frequency").tag(TagSortMode.frequency)
                    }
                    .pickerStyle(.menu)
                    
                    if !GlobalHotkey.shared.isAcessibilityTrusted {
                         VStack(alignment: .leading, spacing: 6) {
                             HStack {
                                 Image(systemName: "exclamationmark.triangle.fill")
                                     .foregroundColor(.yellow)
                                 Text("Background Access Required")
                                     .font(.caption)
                             }
                             Button("Grant Permissions") {
                                 GlobalHotkey.shared.checkPermissions()
                             }
                             .controlSize(.small)
                         }
                         .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    Button(action: {
                        appService.hiddenAppBundleIDs.removeAll()
                    }) {
                        Label("Unhide All Apps", systemImage: "eye")
                    }
                    .disabled(appService.hiddenAppBundleIDs.isEmpty)
                    
                    if !appService.hiddenAppBundleIDs.isEmpty {
                        Text("\(appService.hiddenAppBundleIDs.count) app(s) currently hidden from Open Apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Apps Switcher") {
                     // Shortcut 6: Apps Switcher
                     ShortcutRow(id: 6, label: "Apps Switcher", appService: appService)
                        .padding(.leading, 15)
                     
                     if appService.viewMode != .grid {
                         HStack {
                             Image(systemName: "info.circle")
                             Text("Switcher is disabled in List View")
                         }
                         .font(.caption)
                         .foregroundColor(.secondary)
                         .padding(.leading, 15)
                     }
                }

                Section("Navigation Shortcuts") {
                    // Shortcut 1: All Apps
                    ShortcutRow(id: 1, label: "All Apps", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 2: Open Apps
                    ShortcutRow(id: 2, label: "Open Apps", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 3: Utilities
                    ShortcutRow(id: 3, label: "Utilities", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 4-5: Custom Tags
                    ForEach(4...5, id: \.self) { id in
                        CustomTagShortcutRow(id: id, appService: appService)
                    }
                }
                
                Section("Data Management") {
                    Button(action: {
                        if let json = appService.exportData() {
                            exportDocument = JSONDocument(jsonString: json)
                            showExporter = true
                        }
                    }) {
                        Label("Export Tag Associations (JSON)", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        showImporter = true
                    }) {
                        Label("Import Tag Associations (JSON)", systemImage: "square.and.arrow.down")
                    }
                    
                    if let status = importStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Success") ? .green : .red)
                    }
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version 1.0")
                        Text("© 2025 Shimon Shmueli")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "Satus_Config") { result in
                switch result {
                case .success(let url):
                    print("Saved to \(url)")
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Security
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        let data = try Data(contentsOf: url)
                        if let json = String(data: data, encoding: .utf8) {
                            if appService.importData(from: json) {
                                importStatus = "Import Successful!"
                            } else {
                                importStatus = "Import Failed: Invalid Data"
                            }
                        }
                    } catch {
                        importStatus = "Import Failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importStatus = "Import Failed: \(error.localizedDescription)"
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            takeSnapshot()
        }
    }
    
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: JSONDocument?
    @State private var importStatus: String?
    
    // Debug Mode Sequence: System, System, Dark, Dark, Light, Light
    @State private var themeUnlockQueue: [String] = []
    
    func handleThemeClick(_ theme: String) {
        themeUnlockQueue.append(theme)
        if themeUnlockQueue.count > 6 {
            themeUnlockQueue.removeFirst(themeUnlockQueue.count - 6)
        }
        
        let targetSequence = ["system", "system", "dark", "dark", "light", "light"]
        if themeUnlockQueue == targetSequence {
            appService.isDebugMode.toggle()
            themeUnlockQueue.removeAll()
            // Optional: Play sound or feedback?
            print("Debug Mode Toggled: \(appService.isDebugMode)")
        }
    }
    
    func takeSnapshot() {
        let prefs = appService.getPreferencesSnapshot()
        let shortcuts = GlobalHotkey.shared.getAllShortcuts()
        snapshot = SettingsSnapshot(preferences: prefs, shortcuts: shortcuts)
    }
    
    func restoreSnapshot() {
        guard let s = snapshot else { return }
        print("Restoring Settings Snapshot...")
        appService.restorePreferences(s.preferences)
        GlobalHotkey.shared.restoreShortcuts(s.shortcuts)
    }
}

struct CustomThemePicker: View {
    @Binding var selection: String
    var onClick: (String) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            themeButton("System", value: "system")
            Divider().frame(height: 16)
            themeButton("Dark", value: "dark")
            Divider().frame(height: 16)
            themeButton("Light", value: "light")
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .frame(height: 24)
    }
    
    func themeButton(_ label: String, value: String) -> some View {
        Button(action: {
            selection = value
            onClick(value)
        }) {
            Text(label)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(selection == value ? .white : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selection == value ? Color.accentColor : Color.clear)
    }
}

import UniformTypeIdentifiers

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var jsonString: String
    
    init(jsonString: String = "") {
        self.jsonString = jsonString
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        jsonString = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = jsonString.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}

struct ShortcutRow: View {
    let id: Int
    let label: String
    var showLabel: Bool = true
    @ObservedObject var appService: AppService
    @ObservedObject var hotkeyManager = GlobalHotkey.shared
    
    @State private var current: HotKeyDefinition?
    @State private var isRecording = false
    @State private var isHovering = false
    
    var warningMessage: String? {
        if hotkeyManager.failedRegistrationIDs.contains(id) {
            return "Warning: Shortcut conflict or invalid (system reserved)"
        }
        if let c = current, let msg = GlobalHotkey.isRiskyShortcut(keyCode: c.keyCode, modifiers: c.modifiers) {
            return "Warning: \(msg)"
        }
        return nil
    }
    
    var body: some View {
        HStack {
            if showLabel {
                Text(label)
            }
            Spacer()
            
            if isRecording {
                Text("Press keys...")
                    .foregroundColor(.accentColor)
                    .background(KeyReader { key, mods in
                         GlobalHotkey.shared.setShortcut(id: id, keyCode: Int(key), modifiers: Int(mods.rawValue))
                         load()
                         isRecording = false
                    })
            } else {
                Button(action: { isRecording = true }) {
                    HStack(spacing: 4) {
                        if hotkeyManager.failedRegistrationIDs.contains(id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                        } else if let c = current, let _ = GlobalHotkey.isRiskyShortcut(keyCode: c.keyCode, modifiers: c.modifiers) {
                             Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.orange)
                        }
                        
                        if let c = current {
                            Text(formatShortcut(c))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(hotkeyManager.failedRegistrationIDs.contains(id) ? .secondary : .primary)
                        } else {
                            Text("Record Shortcut")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .overlay(alignment: .bottom) {
                    if isHovering, let msg = warningMessage {
                        Text(msg)
                            .font(.caption)
                            .padding(6)
                            .background(VisualEffectView(material: .toolTip, blendingMode: .withinWindow))
                            .background(Color.black.opacity(0.8)) // Fallback/Tint
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .shadow(radius: 4)
                            .fixedSize()
                            .offset(y: 35)
                            .zIndex(100)
                    }
                }

            }
            
            if current != nil {
                Button(action: {
                    GlobalHotkey.shared.removeShortcut(id: id)
                    load()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { load() }
        .onChange(of: hotkeyManager.failedRegistrationIDs) { load() }
    }
    
    func load() {
        current = GlobalHotkey.shared.getShortcut(id: id)
    }
    
    func formatShortcut(_ def: HotKeyDefinition) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(def.modifiers))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let mods = parts.joined(separator: "\u{2009}")
        let key = keyString(for: def.keyCode)
        
        return mods.isEmpty ? key : mods + " " + key
    }
    
    func keyString(for code: Int) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if code >= 18 && code <= 29 { return ["1","2","3","4","5","6","7","8","9","0"][code-18] }
            let map: [Int:String] = [
                12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 32:"U", 34:"I", 31:"O", 35:"P",
                0:"A", 1:"S", 2:"D", 3:"F", 5:"G", 4:"H", 38:"J", 40:"K", 37:"L",
                6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 45:"N", 46:"M"
            ]
            return map[code] ?? "Key(\(code))"
        }
    }
}

struct KeyReader: NSViewRepresentable {
    var onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onKey = onKey
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class KeyView: NSView {
        var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            onKey?(event.keyCode, event.modifierFlags)
        }
    }
}

struct CustomTagShortcutRow: View {
    let id: Int
    @ObservedObject var appService: AppService
    @ObservedObject var hotkeyManager = GlobalHotkey.shared
    
    @State private var current: HotKeyDefinition?
    @State private var isRecording = false
    @State private var isHovering = false
    
    var warningMessage: String? {
        if hotkeyManager.failedRegistrationIDs.contains(id) {
            return "Warning: Shortcut conflict or invalid (system reserved)"
        }
        if let c = current, let msg = GlobalHotkey.isRiskyShortcut(keyCode: c.keyCode, modifiers: c.modifiers) {
            return "Warning: \(msg)"
        }
        return nil
    }
    
    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { appService.shortcutTagMapping[id] ?? UUID() },
                set: { appService.shortcutTagMapping[id] = $0 }
            )) {
                Text("None").tag(UUID())
                ForEach(appService.tags) { tag in
                    Text(tag.name).tag(tag.id)
                }
            }
            .labelsHidden()
            
            Spacer()
            
            if isRecording {
                Text("Press keys...")
                    .foregroundColor(.accentColor)
                    .background(KeyReader { key, mods in
                         GlobalHotkey.shared.setShortcut(id: id, keyCode: Int(key), modifiers: Int(mods.rawValue))
                         load()
                         isRecording = false
                    })
            } else {
                Button(action: { isRecording = true }) {
                    HStack(spacing: 4) {
                        if hotkeyManager.failedRegistrationIDs.contains(id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                        } else if let c = current, let _ = GlobalHotkey.isRiskyShortcut(keyCode: c.keyCode, modifiers: c.modifiers) {
                             Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.orange)
                        }
                        
                        if let c = current {
                            Text(formatShortcut(c))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(hotkeyManager.failedRegistrationIDs.contains(id) ? .secondary : .primary)
                        } else {
                            Text("Record Shortcut")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .overlay(alignment: .bottom) {
                    if isHovering, let msg = warningMessage {
                        Text(msg)
                            .font(.caption)
                            .padding(6)
                            .background(VisualEffectView(material: .toolTip, blendingMode: .withinWindow))
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .shadow(radius: 4)
                            .offset(y: 30)
                            .zIndex(100)
                    }
                }
            }

            
            if current != nil {
                Button(action: {
                    GlobalHotkey.shared.removeShortcut(id: id)
                    load()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { load() }
        .onChange(of: hotkeyManager.failedRegistrationIDs) { load() }
    }
    
    private func load() {
        current = GlobalHotkey.shared.getShortcut(id: id)
    }
    
    private func formatShortcut(_ def: HotKeyDefinition) -> String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(def.modifiers))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        
        if let key = keyCodeToString(def.keyCode) {
            let mods = parts.joined(separator: "\u{2009}")
            return mods.isEmpty ? key : mods + " " + key
        }
        return parts.joined(separator: "\u{2009}")
    }
    
    private func keyCodeToString(_ code: Int) -> String? {
        let mapping: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return mapping[code]
    }
}

