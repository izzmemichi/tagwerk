import SwiftUI
import SwiftData
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Speicherort (App und Widget teilen sich die Datenbank)

enum SharedStore {
    /// Aus Config.xcconfig (TAGWERK_APP_GROUP), über die Info.plist von App und Widget
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TagwerkAppGroup") as? String ?? ""
    static let widgetChangedKey = "widget.changed"
    static let schema = Schema([ListGroup.self, TaskList.self, TaskItem.self, TaskStep.self, Attachment.self])

    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Öffnet die gemeinsame Datenbank. Beim ersten Start mit App Group werden die
    /// bisherigen Daten aus dem App-Container dorthin kopiert.
    static func makeContainer() throws -> ModelContainer {
        guard let group = groupURL else {
            return try ModelContainer(for: schema)
        }
        let target = group.appendingPathComponent("Tagwerk.store")
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            let old = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            if fm.fileExists(atPath: old.path) {
                for suffix in ["", "-wal", "-shm"] {
                    let src = URL(fileURLWithPath: old.path + suffix)
                    let dst = URL(fileURLWithPath: target.path + suffix)
                    if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
                }
            }
        }
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: target))
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Designs

extension Color {
    /// Kartenfarbe wie bei Microsoft To Do: weiß, im Dunkelmodus dunkelgrau
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : .white
    })
}


enum ListTheme: String, CaseIterable, Identifiable {
    case blue, indigo, purple, rose, red, orange, green, teal, graphite, dawn, lagoon, dusk
    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .blue: return Color(red: 0.25, green: 0.42, blue: 0.85)
        case .indigo: return Color(red: 0.36, green: 0.40, blue: 0.78)
        case .purple: return Color(red: 0.55, green: 0.33, blue: 0.75)
        case .rose: return Color(red: 0.78, green: 0.29, blue: 0.44)
        case .red: return Color(red: 0.80, green: 0.27, blue: 0.24)
        case .orange: return Color(red: 0.85, green: 0.48, blue: 0.16)
        case .green: return Color(red: 0.24, green: 0.55, blue: 0.30)
        case .teal: return Color(red: 0.10, green: 0.53, blue: 0.53)
        case .graphite: return Color(red: 0.37, green: 0.41, blue: 0.46)
        case .dawn: return Color(red: 0.86, green: 0.47, blue: 0.29)
        case .lagoon: return Color(red: 0.08, green: 0.50, blue: 0.62)
        case .dusk: return Color(red: 0.42, green: 0.30, blue: 0.68)
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .dawn: colors = [Color(red: 0.98, green: 0.62, blue: 0.40), Color(red: 0.62, green: 0.36, blue: 0.62)]
        case .lagoon: colors = [Color(red: 0.12, green: 0.62, blue: 0.68), Color(red: 0.10, green: 0.30, blue: 0.55)]
        case .dusk: colors = [Color(red: 0.55, green: 0.38, blue: 0.85), Color(red: 0.16, green: 0.16, blue: 0.40)]
        default: colors = [accent, accent.mix(with: .black, by: 0.18)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var name: String {
        switch self {
        case .blue: return tr("Blau")
        case .indigo: return tr("Indigo")
        case .purple: return tr("Lila")
        case .rose: return tr("Rosé")
        case .red: return tr("Rot")
        case .orange: return tr("Orange")
        case .green: return tr("Grün")
        case .teal: return tr("Petrol")
        case .graphite: return tr("Graphit")
        case .dawn: return tr("Morgenrot")
        case .lagoon: return tr("Lagune")
        case .dusk: return tr("Dämmerung")
        }
    }
}

// MARK: - Datum

enum Day {
    static var locale: Locale { Lang.locale }
    static var cal: Calendar {
        var c = Calendar.current
        c.locale = locale
        c.firstWeekday = 2
        return c
    }

    static var today: Date { cal.startOfDay(for: Date()) }
    static func start(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ n: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    static var tomorrow: Date { add(1, to: today) }

    static var nextMonday: Date {
        let wd = cal.component(.weekday, from: today)
        let delta = (9 - wd) % 7
        return add(delta == 0 ? 7 : delta, to: today)
    }

    static func offset(_ d: Date) -> Int {
        cal.dateComponents([.day], from: today, to: start(d)).day ?? 0
    }

    static func weekdayShort(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).locale(locale)).replacingOccurrences(of: ".", with: "")
    }

    static func label(_ d: Date) -> String {
        switch offset(d) {
        case 0: return tr("Heute")
        case 1: return tr("Morgen")
        case -1: return tr("Gestern")
        default:
            let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
            return sameYear
                ? d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
                : d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
        }
    }

    static func time(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(locale))
    }

    static func longToday() -> String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func at(_ day: Date, hour: Int) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static var laterToday: Date? {
        let h = cal.component(.hour, from: Date()) + 3
        return h <= 22 ? at(today, hour: h) : nil
    }
}

// MARK: - Erinnerungen

enum Reminders {
    static func schedule(_ task: TaskItem) {
        let center = UNUserNotificationCenter.current()
        let id = task.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let date = task.reminder, !task.isCompleted, date > Date() else { return }
        let title = task.title
        let listName = task.list?.name ?? tr("Aufgaben")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = listName
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
        }
    }

    static func cancel(_ task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
}

// MARK: - Badge am App-Symbol (offene Aufgaben in Mein Tag)

enum Badge {
    static let dueTodayKey = "pref.dueTodayInMyDay"
    private static let ids = (1...7).map { "badge.day\($0)" }

    static var dueTodayCounts: Bool { UserDefaults.standard.object(forKey: dueTodayKey) as? Bool ?? true }

    /// Setzt die Zahl für heute und plant für die nächsten 7 Tage je eine stille Mitteilung um Mitternacht,
    /// damit die Zahl auch ohne Öffnen der App stimmt (dann zählen die an dem Tag fälligen Aufgaben).
    static func update(_ ctx: ModelContext) {
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted == false }))) ?? []
        let countsDue = dueTodayCounts
        let today = open.filter { $0.isInMyDay(dueTodayCounts: countsDue) }.count
        var upcoming = Array(repeating: 0, count: ids.count)
        if countsDue {
            for task in open {
                guard let due = task.due else { continue }
                let offset = Day.offset(due)
                if (1...ids.count).contains(offset) { upcoming[offset - 1] += 1 }
            }
        }
        let firstDay = Day.today
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.setBadgeCount(today) { _ in }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for (i, count) in upcoming.enumerated() {
                let content = UNMutableNotificationContent()
                content.badge = NSNumber(value: count)
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Day.add(i + 1, to: firstDay))
                comps.hour = 0
                comps.minute = 0
                comps.second = 5
                center.add(UNNotificationRequest(identifier: ids[i], content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }
}

// MARK: - Abhaken (gemeinsam für App und Widget)

enum TaskOps {
    /// Schaltet erledigt um. Gibt true zurück, wenn die Aufgabe jetzt erledigt ist.
    @discardableResult
    static func toggleComplete(_ task: TaskItem, ctx: ModelContext) -> Bool {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
            Reminders.schedule(task)
            return false
        }
        task.isCompleted = true
        task.completedAt = Date()
        Reminders.cancel(task)

        if let rule = task.repeatRule, !task.spawnedNext, let list = task.list {
            task.spawnedNext = true
            let base = task.due ?? Day.today
            let nextDue = rule.next(after: base)
            let next = TaskItem(title: task.title, order: task.order)
            ctx.insert(next)
            next.list = list
            next.note = task.note
            next.isImportant = task.isImportant
            next.due = nextDue
            next.repeatRule = rule
            if let reminder = task.reminder {
                next.reminder = reminder.addingTimeInterval(nextDue.timeIntervalSince(Day.start(base)))
            }
            for step in task.sortedSteps {
                let s = TaskStep(title: step.title, order: step.order)
                ctx.insert(s)
                s.task = next
            }
            Reminders.schedule(next)
        }
        return true
    }
}
