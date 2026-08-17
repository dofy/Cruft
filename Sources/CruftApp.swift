import SwiftUI

@main
struct CruftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 660)
                .frame(minHeight: 520, idealHeight: 820, maxHeight: .infinity)
        }
        .windowResizability(.contentSize)
    }
}
