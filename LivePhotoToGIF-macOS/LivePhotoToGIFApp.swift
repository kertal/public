import SwiftUI

@main
struct LivePhotoToGIFApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 640)
    }
}
