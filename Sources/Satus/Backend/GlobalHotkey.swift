import SwiftUI
import Carbon

struct HotKeyDefinition: Codable, Identifiable, Hashable {
    var id: Int // Unique ID
    var keyCode: Int
    var modifiers: Int // NSEvent.ModifierFlags.rawValue
    var isEnabled: Bool
}

class GlobalHotkey: ObservableObject {
    static let shared = GlobalHotkey()
    
    @Published var isAcessibilityTrusted: Bool = AXIsProcessTrusted()
    @Published var failedRegistrationIDs: Set<Int> = []
    
    // Callback: (ShortcutID) -> Void
    var onTrigger: ((Int) -> Void)?
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [Int: EventHotKeyRef] = [:]
    
    private let defaultsKey = "UserGlobalHotkeys"
    
    init() {
        // Install Event Handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                // Recover 'self'
                let mySelf = Unmanaged<GlobalHotkey>.fromOpaque(userData!).takeUnretainedValue()
                return mySelf.handleCarbonEvent(event)
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        
        loadHotkeys()
    }
    
    deinit {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
    
    func startMonitoring(trigger: @escaping (Int) -> Void) {
        self.onTrigger = trigger
        
        // Poll for permissions
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.isAcessibilityTrusted = AXIsProcessTrusted()
        }
    }
    
    func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - API
    
    func setShortcut(id: Int, keyCode: Int, modifiers: Int) {
        let def = HotKeyDefinition(id: id, keyCode: keyCode, modifiers: modifiers, isEnabled: true)
        saveShortcut(def)
        register(def)
    }
    
    func getShortcut(id: Int) -> HotKeyDefinition? {
        // Read from UserDefaults
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([HotKeyDefinition].self, from: data) {
            return list.first { $0.id == id }
        }
        return nil
    }
    
    func removeShortcut(id: Int) {
        // Remove from list
        if var list = loadAllShortcuts() {
            list.removeAll { $0.id == id }
            saveAll(list)
        }
        unregister(id: id)
    }
    
    // MARK: - Snapshot / Restore
    func getAllShortcuts() -> [HotKeyDefinition] {
        return loadAllShortcuts() ?? []
    }
    
    func restoreShortcuts(_ shortcuts: [HotKeyDefinition]) {
        // 1. Unregister all currently active
        for (id, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        
        // 2. Save the restored list
        saveAll(shortcuts)
        
        // 3. Re-register everything from the restored list
        for def in shortcuts {
            register(def)
        }
        
        // Clear failed IDs as we are resetting
        failedRegistrationIDs.removeAll()
    }
    
    // MARK: - Internal
    
    private func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        if status == noErr {
            // Check signature
            if hotKeyID.signature == 0x53484B59 { // 'SHKY'
                let id = Int(hotKeyID.id)
                DispatchQueue.main.async {
                    self.onTrigger?(id)
                }
                return noErr
            }
        }
        
        return OSStatus(eventNotHandledErr)
    }
    
    private func register(_ def: HotKeyDefinition) {
        // Unregister old if exists
        unregister(id: def.id)
        
        guard def.isEnabled else { return }
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x53484B59 // 'SHKY'
        hotKeyID.id = UInt32(def.id)
        
        var ref: EventHotKeyRef?
        
        // Convert AppKit modifiers to Carbon modifiers
        let carbonMods = convertModifiers(def.modifiers)
        
        let status = RegisterEventHotKey(
            UInt32(def.keyCode),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        
        DispatchQueue.main.async {
            if status == noErr, let ref = ref {
                self.hotKeyRefs[def.id] = ref
                self.failedRegistrationIDs.remove(def.id)
                print("Registered Global Hotkey ID: \(def.id)")
            } else {
                self.failedRegistrationIDs.insert(def.id)
                print("Failed to register hotkey ID: \(def.id), status: \(status)")
            }
        }
    }
    
    private func unregister(id: Int) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
        // Also remove from failed set if we explicitly unregister?
        DispatchQueue.main.async {
            self.failedRegistrationIDs.remove(id)
        }
    }
    
    private func loadHotkeys() {
        guard let list = loadAllShortcuts() else { return }
        for def in list {
            register(def)
        }
    }
    
    private func loadAllShortcuts() -> [HotKeyDefinition]? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode([HotKeyDefinition].self, from: data)
    }
    
    private func saveShortcut(_ def: HotKeyDefinition) {
        var list = loadAllShortcuts() ?? []
        list.removeAll { $0.id == def.id }
        list.append(def)
        saveAll(list)
    }
    
    private func saveAll(_ list: [HotKeyDefinition]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    private func convertModifiers(_ raw: Int) -> UInt32 {
        var carbon: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: UInt(raw))
        
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        
        return carbon
    }
    
    static func isRiskyShortcut(keyCode: Int, modifiers: Int) -> String? {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        guard flags.contains(.command) else { return nil }
        
        // Check for exact matches (ignoring other modifiers? No, Cmd+Shift+C is fine usually. Cmd+C is bad.)
        // Actually Cmd+Shift+C is "Copy Style" or "Inspector". Still standard-ish.
        // But strict "Risky" usually implies the exact common one.
        // Let's check for EXACT Cmd (plus maybe Shift for some?)
        // Let's stick to strict Cmd+Key for now.
        
        let exactCmd = flags.intersection([.command, .option, .control, .shift]) == .command
        
        if exactCmd {
            switch keyCode {
            case 0: return "Overrides Select All" // A
            case 6: return "Overrides Undo" // Z
            case 7: return "Overrides Cut" // X
            case 8: return "Overrides Copy" // C
            case 9: return "Overrides Paste" // V
            case 1: return "Overrides Save" // S
            case 12: return "Overrides Quit" // Q
            case 13: return "Overrides Close" // W
            case 53: return "Overrides Escape" // Esc
            default: break
            }
        }
        
        return nil
    }

    
    // MARK: - Formatting Helper
    
    func getShortcutString(id: Int) -> String? {
        guard let def = getShortcut(id: id) else { return nil }
        return formatShortcut(def)
    }
    
    func formatShortcut(_ def: HotKeyDefinition) -> String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(def.modifiers))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        
        if let key = keyCodeToString(def.keyCode) {
            let modsString = parts.joined(separator: "\u{2009}")
            return modsString.isEmpty ? key : modsString + " " + key
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

