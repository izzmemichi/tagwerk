import SwiftUI
import SwiftData
import UserNotifications

/// Hält die Datenbank. Hat das Widget etwas abgehakt, wird sie beim Zurückkehren neu geladen.
@Observable
final class StoreHolder {
    var container: ModelContainer
    var version = 0
    init(_ container: ModelContainer) { self.container = container }
}

@main
struct TagwerkApp: App {
    @State private var holder: StoreHolder
    @Environment(\.scenePhase) private var scenePhase
    /// Bei Sprachwechsel wird die Oberfläche neu aufgebaut
    @AppStorage(Lang.key, store: Lang.store) private var language = ""

    init() {
        let container: ModelContainer
        do {
            container = try SharedStore.makeContainer()
        } catch {
            fatalError("Die Datenbank konnte nicht geöffnet werden: \(error)")
        }
        // Automatisches Speichern aus: Alle Speicherungen laufen über Sync.commit und werden so fürs Hochladen vorgemerkt
        container.mainContext.autosaveEnabled = false
        _ = Store.defaultList(container.mainContext)
        Sync.shared.commit(container.mainContext)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        let holder = StoreHolder(container)
        _holder = State(initialValue: holder)
        Sync.shared.context = { holder.container.mainContext }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .id("\(holder.version)-\(language)")
                .environment(\.locale, Lang.locale)
                .modelContainer(holder.container)
                .task {
                    // Jede Sekunde ungespeicherte Änderungen sichern (löst den Upload aus),
                    // alle 30 Sekunden zur Sicherheit abgleichen, falls die Live-Verbindung etwas verpasst
                    var tick = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard UIApplication.shared.applicationState == .active else { continue }
                        Sync.shared.flushLocal()
                        tick += 1
                        // Live-Verbindung überwachen und bei Bedarf neu aufbauen
                        if tick % 5 == 0 && Sync.shared.isSignedIn && !Sync.shared.isLive { await Sync.shared.connectLive() }
                        if tick % 30 == 0 { await Sync.shared.run() }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let defaults = UserDefaults(suiteName: SharedStore.appGroup)
                if defaults?.bool(forKey: SharedStore.widgetChangedKey) == true {
                    defaults?.set(false, forKey: SharedStore.widgetChangedKey)
                    if let fresh = try? SharedStore.makeContainer() {
                        fresh.mainContext.autosaveEnabled = false
                        holder.container = fresh
                        holder.version += 1
                    }
                }
                Badge.update(holder.container.mainContext)
                Task {
                    await Sync.shared.run()
                    await Sync.shared.connectLive()
                }
            } else if phase == .background {
                Sync.shared.commit(holder.container.mainContext)
                Badge.update(holder.container.mainContext)
                SharedStore.reloadWidgets()
                // Letzte Änderungen noch hochladen, bevor iOS die App schlafen legt
                Sync.shared.disconnectLive()
                let bgTask = UIApplication.shared.beginBackgroundTask()
                Task {
                    await Sync.shared.run()
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }
}
