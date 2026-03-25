import SwiftUI

@main
struct UglySliceWatchApp: App {
  @StateObject private var connectivity = WatchConnectivityManager()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(connectivity)
    }
  }
}
