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
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Also explicitly open System Settings to the Accessibility pane
        if !isTrusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
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
        for (_, ref) in hotKeyRefs {
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
        // Special Keys
        switch code {
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
            
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
            
        case 36: return "↩" // Return
        case 48: return "⇥" // Tab
        case 49: return "Space"
        case 51: return "⌫" // Delete
        case 53: return "⎋" // Esc
        case 71: return "⌧" // Clear
        case 76: return "⌅" // Enter
            
        // Arrows
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
            
        // Function Keys
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
            
        // Punctuation / Symbol
        case 24: return "="
        case 27: return "-"
        case 30: return "]"
        case 33: return "["
        case 39: return "'"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 47: return "."
        case 50: return "`"
            
        // Keypad (Optional, can add if requested)
        default:
            return "Key(\(code))"
        }
    }
}

