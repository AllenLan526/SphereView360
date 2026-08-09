import SwiftUI

@main
struct SphereView360App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ViewerStore()

    var body: some Scene {
        WindowGroup("SphereView360", id: "viewer") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 560)
                .onReceive(NotificationCenter.default.publisher(for: .sphereViewOpenURLs)) { notification in
                    guard let urls = notification.userInfo?[OpenURLNotification.urlsKey] as? [URL] else {
                        return
                    }
                    store.openFirstSupported(urls)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open 360 Media...") {
                    store.presentOpenPanel()
                }
                .keyboardShortcut("o")

                Button("Add to Open With") {
                    store.registerOpenWithOption()
                }

                Divider()

                Button(store.isPlaying ? "Pause" : "Play") {
                    store.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!store.hasVideo)

                Button("Reset View") {
                    store.requestViewReset()
                }
                .keyboardShortcut("0")
                .disabled(!store.hasMedia)
            }
        }
    }
}
