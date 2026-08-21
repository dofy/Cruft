import AppKit
import SwiftUI

final class CruftAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let helpMenu = NSApp.helpMenu,
                  let helpItem = NSApp.mainMenu?.items.first(where: { $0.submenu === helpMenu }) else {
                return
            }
            NSApp.mainMenu?.removeItem(helpItem)
            NSApp.helpMenu = nil
        }
    }
}

@main
struct CruftApp: App {
    @NSApplicationDelegateAdaptor(CruftAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("Cruft", id: "main") {
            ContentView()
                .frame(minWidth: 900, idealWidth: 1020, minHeight: 620, idealHeight: 760)
        }
        .defaultSize(width: 1020, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
        }
    }
}
