import SwiftUI

@main
struct CleanMyMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 660, height: 660)
        }
        .windowResizability(.contentSize)
    }
}
