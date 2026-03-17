import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var helpWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 0. IMMEDIATE LOG
        print("!!! APP DELEGATE DID FINISH LAUNCHING (SYNCHRONOUS) !!!")
        
        // 1. Identity: Ensure we are a regular app to show Menu Bar and Dock icon
        NSApplication.shared.setActivationPolicy(.regular)
        
        // 2. Activation Stunt (Delayed for Xcode/Terminal focus stealing)
        // We do this in AppDelegate to GUARANTEE it runs, regardless of Window/View loading state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("---------- DIAGNOSTICS START (AppDelegate) ----------")
            print("Activation Policy: \(NSApplication.shared.activationPolicy().rawValue) (0=regular, 1=accessory, 2=prohibited)")
            print("App isActive: \(NSApplication.shared.isActive)")
            
            // Aggressively force front
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            if let window = NSApplication.shared.windows.first {
                print("Window FOUND. Title: '\(window.title)'")
                print("Window canBecomeKey: \(window.canBecomeKey)")
                // Check if we need to force it
                if !window.isKeyWindow {
                    window.makeKeyAndOrderFront(nil)
                }
                print("Window isKeyWindow (Post-Force): \(window.isKeyWindow)")
            } else {
                print("NO WINDOW FOUND! (This is unexpected in DidFinishLaunching with SwiftUI)")
                // If SwiftUI hasn't created the window yet, we might be too early even with 0.5s?
                // But usually the WindowGroup is initialized by now.
            }
            print("---------- DIAGNOSTICS END ----------")
            
            // Re-apply menu to fight SwiftUI re-inserting default menus
            self.setupMinimalMenu()
        }
        
        // 3. Global Mouse Monitor (Close on click outside)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            // Safety Check: Is the mouse inside our window?
            // Global monitor shouldn't fire for local events, but if it does (or if window is weird), ensure we don't self-close.
            let mouseLocation = NSEvent.mouseLocation
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                if window.frame.contains(mouseLocation) {
                    return // Clicked inside
                }
            }
            
            if NSApplication.shared.isActive {
                if AppService.shared?.isPinned != true {
                    NSApplication.shared.hide(nil)
                }
            }
        }
        
        // 4. Customize Menu Bar - Remove all menus except app menu
        // We do this inside async loops to ensure we override SwiftUI's default menu reconstruction
        DispatchQueue.main.async {
            self.setupMinimalMenu()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure menu is persisted/restored when coming to foreground
        setupMinimalMenu()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        // Close Help Window
        if let hw = helpWindow {
            hw.close()
            // We don't necessarily need to nil it if isReleasedWhenClosed is false,
            // but closing it is enough to hide it.
        }
        
        // Close About Panel (Standard About Panel usually has title "About <AppName>")
        // Iterating windows to find it.
        for window in NSApplication.shared.windows {
            if window.title.starts(with: "About ") {
                window.close()
            }
        }
    }
    
    func setupMinimalMenu() {
        let mainMenu = NSMenu()
        
        // App Menu (ZoneKey)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "ZoneKey") // Title often needed for the system to recognize it as App Menu
        
        // About
        let aboutItem = NSMenuItem(
            title: "About ZoneKey",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit ZoneKey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        
        let openItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(showMainWindow),
            keyEquivalent: "n"
        )
        windowMenu.addItem(openItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Register as system Windows menu (auto-populates open windows)
        NSApplication.shared.windowsMenu = windowMenu
        
        // Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        
        let satusHelpItem = NSMenuItem(
            title: "ZoneKey Help",
            action: #selector(showHelp),
            keyEquivalent: "?"
        )
        helpMenu.addItem(satusHelpItem)
        
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    @objc func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // 1. Try to find existing window
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // 2. If no window, force SwiftUI to recreate it by "launching" ourselves
        // This is the reliable way to make WindowGroup reappear after last window closed
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        
        let displayVersion = "Version \(version)"
        
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
             .applicationVersion: displayVersion,
             .credits: NSAttributedString(string: "Copyright © 2026 Shimon Shmueli", attributes: [
                 .font: NSFont.systemFont(ofSize: 11),
                 .foregroundColor: NSColor.secondaryLabelColor
             ])
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func showHelp() {
        if helpWindow == nil {
            let helpView = HelpView()
            let hostingController = NSHostingController(rootView: helpView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ZoneKey Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            window.setFrameAutosaveName("ZoneKeyHelpWindow")
            window.isReleasedWhenClosed = false
            
            self.helpWindow = window
        }
        
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Dock Menu
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        
        // Add tags from AppService
        if let appService = AppService.shared {
            let tags = appService.displayTags
            if !tags.isEmpty {
                for tag in tags {
                    let item = NSMenuItem(
                        title: tag.name,
                        action: #selector(dockMenuTagClicked(_:)),
                        keyEquivalent: ""
                    )
                    item.representedObject = tag.id
                    item.target = self
                    menu.addItem(item)
                }
            }
        }
        
        return menu
    }
    
    @objc func dockMenuTagClicked(_ sender: NSMenuItem) {
        guard let tagId = sender.representedObject as? UUID else { return }
        
        // Activate and show main window
        NSApplication.shared.activate(ignoringOtherApps: true)
        showMainWindow()
        
        // Navigate to the selected tag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppService.shared?.sidebarSelection = .tag(tagId)
        }
    }
}

@main
struct SatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "mainwindow") {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
                .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
                .onAppear {
                    // Previous logic moved to ContentView to access AppService
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    if AppService.shared?.isPinned != true {
                        NSApplication.shared.hide(nil)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}


