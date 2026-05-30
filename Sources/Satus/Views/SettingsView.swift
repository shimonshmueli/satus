import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appService: AppService
    @Environment(\.dismiss) var dismiss
    @ObservedObject var hotkeyManager = GlobalHotkey.shared
    
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
                    
                    Divider()
                    
                    AccentColorPicker(selectedHex: $appService.accentColorHex)
                }
                

                
                Section("General") {
                    Toggle("Launch at Login", isOn: $appService.launchAtLogin)
                    Toggle("Show Open Applications", isOn: $appService.showOpenApps)
                    Toggle("Show Utilities", isOn: $appService.showUtilities)
                    Toggle("Show Tag Application Count", isOn: $appService.showTagCount)
                    Picker("Sort Tags", selection: $appService.tagSortMode) {
                        Text("Manual").tag(TagSortMode.manual)
                        Text("Alphabetical").tag(TagSortMode.alphabetical)
                        Text("Most Used").tag(TagSortMode.frequency)
                    }
                    .pickerStyle(.menu)
                    
                    if !hotkeyManager.isAcessibilityTrusted {
                         VStack(alignment: .leading, spacing: 4) {
                             Text("Background Access")
                             Text("Background access to keyboard shortcuts is required.\nTo grant permission, go to **System Settings > Privacy & Security > Accessibility**")
                                 .font(.caption)
                                 .foregroundColor(.secondary)
                         }
                         .padding(.vertical, 4)
                    }
                    

                    Picker("Default Tag on Launch", selection: Binding(
                        get: { appService.defaultTagId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
                        set: { appService.defaultTagId = ($0 == UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) ? nil : $0 }
                    )) {
                        Text("All Applications").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                        Divider()
                        ForEach(appService.tags) { tag in
                            Text(tag.name).tag(tag.id)
                        }
                    }
                }
                Section("Application Switcher") {
                     // Shortcut 6: Apps Switcher
                     ShortcutRow(id: 6, label: "Application Switcher", appService: appService)
                        .padding(.leading, 15)
                     
                     if appService.viewMode != .grid {
                         HStack {
                             Image(systemName: "info.circle")
                             Text("Switcher Mode is disabled in List View")
                         }
                         .font(.caption)
                         .foregroundColor(.secondary)
                         .padding(.leading, 15)
                     }
                }

                Section("Navigation Shortcuts") {
                    // Shortcut 1: All Apps
                    ShortcutRow(id: 1, label: "All Applications", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 2: Open Apps
                    ShortcutRow(id: 2, label: "Open Applications", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 3: Utilities
                    ShortcutRow(id: 3, label: "Utilities", appService: appService)
                        .padding(.leading, 15)
                    
                    // Shortcut 4-9: Custom Tags (Skipping 6 as it is App Switcher)
                    ForEach([4, 5, 7, 8, 9], id: \.self) { id in
                        CustomTagShortcutRow(id: id, appService: appService)
                            .padding(.leading, 15)
                    }
                }
                
                Section("Data Management") {
                    HStack {
                        Button(action: {
                            if let json = appService.exportData() {
                                exportDocument = JSONDocument(jsonString: json)
                                showExporter = true
                            }
                        }) {
                            Label("Export Tag Associations (JSON)", systemImage: "square.and.arrow.up")
                        }
                        .disabled(!AppService.isPro)
                        
                        if !AppService.isPro {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    
                    HStack {
                        Button(action: {
                            showImporter = true
                        }) {
                            Label("Import Tag Associations (JSON)", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!AppService.isPro)
                        
                        if !AppService.isPro {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button(action: {
                                isPrefetching = true
                                appService.prefetchKeywords()
                                // Simulate a brief loading state for UX since we do detached fire-and-forget
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isPrefetching = false
                                }
                            }) {
                                Text("Prefetch Application Keywords")
                            }
                            .disabled(isPrefetching)
                            
                            if isPrefetching {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.leading, 8)
                            }
                        }
                        
                        if let date = appService.lastKeywordFetchDate {
                            Text("Last fetched: \(date, formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Keywords are automatically refreshed daily when the application is hidden.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let status = importStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Success") ? .green : .red)
                    }
                }
                
                Section {
                    // Provider picker
                    Picker("Provider", selection: $llmProviderRaw) {
                        ForEach(KeychainStore.Provider.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }

                    // API key field + Save / Clear
                    HStack {
                        SecureField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            if KeychainStore.save(apiKeyInput, for: llmProvider) {
                                apiKeyInput = ""
                                refreshKeyStatus()
                                llmStatus = "Key saved."
                            } else {
                                llmStatus = "Failed to save key."
                            }
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Clear") {
                            KeychainStore.delete(for: llmProvider)
                            apiKeyInput = ""
                            refreshKeyStatus()
                            llmStatus = "Key cleared."
                        }
                        .disabled(!hasStoredKey)
                    }

                    // Key presence indicator
                    Text(hasStoredKey
                         ? "A key is stored for \(llmProvider.displayName)."
                         : "No key stored for \(llmProvider.displayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Model override (OpenRouter only — Anthropic uses its default model)
                    if llmProvider == .openrouter {
                        TextField("Model (e.g. anthropic/claude-haiku-4-5)",
                                  text: $openRouterModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Action button. For now this is a smoke test: classify one app
                    // and show the result inline. Full review-sheet flow comes later.
                    HStack {
                        Button("Suggest tags for my apps…") {
                            runClassificationSmokeTest()
                        }
                        .disabled(!hasStoredKey || isClassifying)
                        if isClassifying {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let status = llmStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(status, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy status to clipboard")
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Tag Suggestions")
                        Text("PRO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                    }
                } footer: {
                    Text("Bring your own API key. Keys are stored in the macOS Keychain and only sent to the selected provider when you press the button.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(!AppService.isPro)
                .onAppear { refreshKeyStatus() }
                .onChange(of: llmProviderRaw) {
                    apiKeyInput = ""
                    llmStatus = nil
                    refreshKeyStatus()
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                        Text("© 2025 Shimon Shmueli")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "ZoneKey_Config") { result in
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
        .frame(width: 500, height: 750)
        .tint(appService.accentColor)
        .onAppear {
            takeSnapshot()
        }
    }
    
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: JSONDocument?
    @State private var importStatus: String?
    @State private var isPrefetching = false

    // LLM tag-suggestions (Pro). Provider selection + model override persist
    // across launches; the API key itself lives in the Keychain (KeychainStore).
    @AppStorage("llmProvider")      private var llmProviderRaw: String = KeychainStore.Provider.anthropic.rawValue
    @AppStorage("llmOpenRouterModel") private var openRouterModel: String = "anthropic/claude-haiku-4-5"
    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var llmStatus: String? = nil
    @State private var isClassifying: Bool = false

    private var llmProvider: KeychainStore.Provider {
        KeychainStore.Provider(rawValue: llmProviderRaw) ?? .anthropic
    }

    private func refreshKeyStatus() {
        hasStoredKey = KeychainStore.hasKey(for: llmProvider)
    }

    /// Classify all currently-untagged apps via the chosen provider, validate
    /// the reply, persist to the cache, and surface a summary inline.
    /// State mutation on AppService is deferred to the review-sheet milestone.
    private func runClassificationSmokeTest() {
        #if SATUS_PRO
        let untagged = appService.apps.filter { $0.tags.isEmpty }
        guard !untagged.isEmpty else {
            llmStatus = "All installed apps are already tagged. Nothing to classify."
            return
        }

        isClassifying = true
        llmStatus = "Classifying \(untagged.count) untagged app\(untagged.count == 1 ? "" : "s")…"

        // Snapshot the inputs so the background Task is independent of view state.
        let appsSnapshot = untagged
        let tagsSnapshot = appService.tags
        let provider = llmProvider
        let modelOverride = openRouterModel

        Task { @MainActor in
            defer { isClassifying = false }
            do {
                let client: LLMClient
                switch provider {
                case .anthropic:  client = AnthropicClient()
                case .openrouter: client = OpenRouterClient(model: modelOverride)
                }
                let run = try await Classifier(client: client)
                    .suggest(for: appsSnapshot, existingTags: tagsSnapshot)

                let totalNewTagNames = run.assignments
                    .reduce(0) { $0 + $1.newTagNames.count }
                let totalExistingAssignments = run.assignments
                    .reduce(0) { $0 + $1.existingTagIDs.count }

                var parts: [String] = []
                parts.append("Done. \(run.assignments.count) app assignment\(run.assignments.count == 1 ? "" : "s")")
                parts.append("(\(run.cacheHits) cached, \(run.newRequests) fetched).")
                parts.append("\(totalExistingAssignments) tag link\(totalExistingAssignments == 1 ? "" : "s"), \(totalNewTagNames) new tag name\(totalNewTagNames == 1 ? "" : "s") proposed.")
                if run.unknownTagIDsDropped > 0 {
                    parts.append("Dropped \(run.unknownTagIDsDropped) unknown tag ID\(run.unknownTagIDsDropped == 1 ? "" : "s").")
                }
                if run.newTagNamesDroppedOrNormalized > 0 {
                    parts.append("Cleaned \(run.newTagNamesDroppedOrNormalized) new-tag name\(run.newTagNamesDroppedOrNormalized == 1 ? "" : "s").")
                }
                parts.append("Review sheet coming next.")
                llmStatus = parts.joined(separator: " ")
            } catch {
                llmStatus = "Failed: \(error.localizedDescription)"
            }
        }
        #else
        llmStatus = "Tag suggestions require ZoneKey Pro."
        #endif
    }

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
    @EnvironmentObject var appService: AppService
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
        .background(selection == value ? appService.accentColor : Color.clear)
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
                    .foregroundColor(appService.accentColor)
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
        return GlobalHotkey.shared.formatShortcut(def)
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
    
    var selectedTagName: String {
        if let tagID = appService.shortcutTagMapping[id],
           let tag = appService.tags.first(where: { $0.id == tagID }) {
            return tag.name
        }
        return ""
    }
    
    var body: some View {
        HStack {
            Menu {
                Button("None") {
                    appService.shortcutTagMapping[id] = nil
                }
                Divider()
                ForEach(appService.tags) { tag in
                    Button(tag.name) {
                        appService.shortcutTagMapping[id] = tag.id
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedTagName)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .frame(width: 150)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .tint(.primary)
            .fixedSize()
            
            Spacer()
            
            if isRecording {
                Text("Press keys...")
                    .foregroundColor(appService.accentColor)
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
        return GlobalHotkey.shared.formatShortcut(def)
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()
struct AccentColorPicker: View {
    @Binding var selectedHex: String
    @State private var customColor: Color = .green
    
    private let presets: [(name: String, hex: String)] = [
        ("Green", "#34C759"),
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Orange", "#FF9500"),
        ("Pink", "#FF2D55"),
        ("Teal", "#5AC8FA"),
        ("Red", "#FF3B30"),
        ("Yellow", "#FFCC00"),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accent Color")
                .font(.system(size: 13))
            
            HStack(spacing: 10) {
                ForEach(presets, id: \.hex) { preset in
                    Button(action: {
                        selectedHex = preset.hex
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.fromHex(preset.hex))
                                .frame(width: 24, height: 24)
                                .shadow(color: Color.fromHex(preset.hex).opacity(0.4), radius: 2, y: 1)
                            
                            if selectedHex.uppercased() == preset.hex.uppercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
                
                Divider()
                    .frame(height: 20)
                
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .help("Custom Color")
                    .onChange(of: customColor) { _, newColor in
                        selectedHex = newColor.toHex()
                    }
                    .onAppear {
                        customColor = Color.fromHex(selectedHex)
                    }
            }
        }
    }
}

