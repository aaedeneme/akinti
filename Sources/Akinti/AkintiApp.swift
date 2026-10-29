import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: TorrentStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { store?.saveState() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.forEach { store?.handle(url: $0) } }
    }
}

@main
struct AkintiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = TorrentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { delegate.store = store }
                .frame(minWidth: 900, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Torrent Dosyası Ekle…") { store.pickTorrentFiles() }
                    .keyboardShortcut("o")
                Button("Magnet Bağlantısı Ekle…") { store.beginAdd() }
                    .keyboardShortcut("u")
            }
            CommandMenu("Aktarım") {
                Button("Sürdür") { store.resume(store.selection) }
                Button("Zorla Başlat") { store.forceStart(store.selection) }
                Button("Durdur") { store.pause(store.selection) }
                Divider()
                Button("Klasörde Göster") { store.reveal(store.selection) }
                Button("Klasöre Taşı…") { store.moveSelected(store.selection) }
                Divider()
                Button("Hepsini Duraklat") { store.pauseAll() }
                Button("Hepsini Sürdür") { store.resumeAll() }
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
