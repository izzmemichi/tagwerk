import SwiftUI
import SwiftData
import UserNotifications
import AudioToolbox
import UIKit

// MARK: - Einstellungen

enum Pref {
    static let addToTop = "pref.addToTop"
    static let importantToTop = "pref.importantToTop"
    static let sound = "pref.sound"
    static let confirmDelete = "pref.confirmDelete"
    static let showImportant = "pref.showImportant"
    static let showPlanned = "pref.showPlanned"
    static let showAll = "pref.showAll"
    static let showCompleted = "pref.showCompleted"
    static let autoHideEmpty = "pref.autoHideEmpty"
    static let dueTodayInMyDay = Badge.dueTodayKey
    static let profileName = "pref.profileName"
}

// MARK: - Intelligente Listen

enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case myDay, important, planned, all, completed, tasks
    var id: String { rawValue }

    var title: String {
        switch self {
        case .myDay: return tr("Mein Tag")
        case .important: return tr("Wichtig")
        case .planned: return tr("Geplant")
        case .all: return tr("Alle")
        case .completed: return tr("Abgeschlossen")
        case .tasks: return tr("Aufgaben")
        }
    }

    var icon: String {
        switch self {
        case .myDay: return "sun.max"
        case .important: return "star"
        case .planned: return "calendar"
        case .all: return "infinity"
        case .completed: return "checkmark.circle"
        case .tasks: return "house"
        }
    }

    var defaultTheme: ListTheme {
        switch self {
        case .myDay: return .dawn
        case .important: return .rose
        case .planned: return .teal
        case .all: return .graphite
        case .completed: return .green
        case .tasks: return .indigo
        }
    }

    var iconColor: Color {
        switch self {
        case .myDay: return Color(red: 0.40, green: 0.45, blue: 0.52)
        case .important: return Color(red: 0.78, green: 0.29, blue: 0.44)
        case .planned: return Color(red: 0.40, green: 0.45, blue: 0.52)
        case .all: return Color(red: 0.18, green: 0.50, blue: 0.34)
        case .completed: return Color(red: 0.18, green: 0.50, blue: 0.34)
        case .tasks: return Color(red: 0.25, green: 0.42, blue: 0.85)
        }
    }
}

enum Route: Hashable {
    case smart(SmartList)
    case list(TaskList)
    case search
    case settings
}

enum SortMode: String, CaseIterable, Identifiable {
    case rhythm, list, importance, alphabetical, dueDate, created, myDay
    var id: String { rawValue }
    /// Diese Sortierungen teilen die offenen Aufgaben in Abschnitte auf
    var groups: Bool { self == .rhythm || self == .list }
    var title: String {
        switch self {
        case .rhythm: return tr("Rhythmus")
        case .list: return tr("Liste")
        case .importance: return tr("Wichtigkeit")
        case .alphabetical: return tr("Alphabetisch")
        case .dueDate: return tr("Fälligkeitsdatum")
        case .created: return tr("Erstellungsdatum")
        case .myDay: return tr("Zu „Mein Tag“ hinzugefügt")
        }
    }
    var icon: String {
        switch self {
        case .rhythm: return "repeat"
        case .list: return "list.bullet"
        case .importance: return "star"
        case .alphabetical: return "arrow.up.arrow.down"
        case .dueDate: return "calendar"
        case .created: return "calendar.badge.plus"
        case .myDay: return "sun.max"
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Stille Badge-Mitteilungen nicht anzeigen, solange die App offen ist
        completionHandler(notification.request.identifier.hasPrefix("badge.") ? [] : [.banner, .sound])
    }
}

// MARK: - Aktionen

@MainActor
enum Store {
    static func defaultList(_ ctx: ModelContext) -> TaskList {
        let descriptor = FetchDescriptor<TaskList>(predicate: #Predicate { $0.isDefault == true })
        if let found = try? ctx.fetch(descriptor).first { return found }
        let list = TaskList(name: tr("Aufgaben"), theme: .indigo, order: -1, isDefault: true)
        ctx.insert(list)
        return list
    }

    static func nextListOrder(_ ctx: ModelContext) -> Double {
        let lists = (try? ctx.fetch(FetchDescriptor<TaskList>())) ?? []
        let groups = (try? ctx.fetch(FetchDescriptor<ListGroup>())) ?? []
        return (lists.map(\.order) + groups.map(\.order)).max().map { $0 + 1 } ?? 0
    }

    @discardableResult
    static func addTask(title: String, to list: TaskList, important: Bool = false, myDay: Bool = false,
                        due: Date? = nil, reminder: Date? = nil, rule: RepeatRule? = nil,
                        ctx: ModelContext) -> TaskItem {
        let toTop = UserDefaults.standard.object(forKey: Pref.addToTop) as? Bool ?? true
        let orders = list.tasks.map(\.order)
        let order = toTop ? (orders.min() ?? 0) - 1 : (orders.max() ?? 0) + 1
        let task = TaskItem(title: title, order: order)
        ctx.insert(task)
        task.list = list
        task.isImportant = important
        if myDay { task.myDayDate = Day.today; task.myDayAddedAt = Date() }
        task.due = due ?? (rule != nil ? Day.today : nil)
        task.reminder = reminder
        task.repeatRule = rule
        Reminders.schedule(task)
        return task
    }

    static func setMyDay(_ task: TaskItem, _ on: Bool) {
        task.myDayDate = on ? Day.today : nil
        task.myDayAddedAt = on ? Date() : nil
    }

    static func toggleComplete(_ task: TaskItem, ctx: ModelContext) {
        if TaskOps.toggleComplete(task, ctx: ctx) {
            if UserDefaults.standard.object(forKey: Pref.sound) as? Bool ?? true {
                AudioServicesPlaySystemSound(1057)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    static func delete(_ task: TaskItem, ctx: ModelContext) {
        Reminders.cancel(task)
        for a in task.attachments { try? FileManager.default.removeItem(at: a.url) }
        ctx.delete(task)
    }

    static func move(_ task: TaskItem, to list: TaskList) {
        let orders = list.tasks.map(\.order)
        task.list = list
        task.order = (orders.min() ?? 0) - 1
    }

    static func newList(name: String, theme: ListTheme, group: ListGroup?, ctx: ModelContext) -> TaskList {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let list = TaskList(name: trimmed.isEmpty ? tr("Unbenannte Liste") : trimmed, theme: theme, order: nextListOrder(ctx))
        ctx.insert(list)
        list.group = group
        return list
    }

    static func duplicate(_ list: TaskList, ctx: ModelContext) -> TaskList {
        let copy = TaskList(name: list.name + tr(" (Kopie)"), theme: list.theme, order: list.order + 0.5)
        ctx.insert(copy)
        copy.group = list.group
        for t in list.tasks where !t.isCompleted {
            let n = TaskItem(title: t.title, order: t.order)
            ctx.insert(n)
            n.list = copy
            n.note = t.note
            n.isImportant = t.isImportant
            n.due = t.due
            n.repeatRaw = t.repeatRaw
            for step in t.sortedSteps {
                let s = TaskStep(title: step.title, order: step.order)
                ctx.insert(s)
                s.isCompleted = step.isCompleted
                s.task = n
            }
        }
        return copy
    }

    static func delete(_ list: TaskList, ctx: ModelContext) {
        for t in list.tasks { delete(t, ctx: ctx) }
        ctx.delete(list)
    }

    /// "Neue Liste aus dieser Aufgabe erstellen": Liste mit dem Titel der Aufgabe, Schritte werden Aufgaben.
    static func listFromTask(_ task: TaskItem, ctx: ModelContext) -> TaskList {
        let list = newList(name: task.title, theme: task.list?.theme ?? .blue, group: task.list?.group, ctx: ctx)
        for (i, step) in task.sortedSteps.enumerated() {
            let t = TaskItem(title: step.title, order: Double(i))
            ctx.insert(t)
            t.list = list
            if step.isCompleted { t.isCompleted = true; t.completedAt = Date() }
        }
        delete(task, ctx: ctx)
        return list
    }

    static func promote(_ step: TaskStep, ctx: ModelContext) {
        guard let task = step.task, let list = task.list else { return }
        let t = addTask(title: step.title, to: list, ctx: ctx)
        t.isCompleted = step.isCompleted
        ctx.delete(step)
    }

    static func addAttachment(from url: URL, to task: TaskItem, ctx: ModelContext) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let stored = UUID().uuidString + "-" + url.lastPathComponent
        let target = Attachment.folder.appendingPathComponent(stored)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
            let a = Attachment(fileName: url.lastPathComponent, storedName: stored, byteCount: size)
            ctx.insert(a)
            a.task = task
        } catch {
            print("Anhang fehlgeschlagen: \(error)")
        }
    }
}

// MARK: - Kleine Bausteine

/// Wischen vom linken Rand zurück, auch wenn die Navigationsleiste ausgeblendet ist
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

struct CheckCircle: View {
    let done: Bool
    let accent: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? Color(.systemGray) : Color(.systemGray2), lineWidth: 1.5)
                .background(Circle().fill(done ? Color(.systemGray) : .clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

struct StarButton: View {
    let on: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(on ? accent : Color(.systemGray))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(on ? tr("Nicht mehr wichtig") : tr("Als wichtig markieren"))
    }
}

struct ListIcon: View {
    let name: String
    let fallback: String
    let color: Color

    var body: some View {
        if let emoji = name.splitEmoji.emoji {
            Text(emoji).font(.system(size: 21)).frame(width: 28)
        } else {
            Image(systemName: fallback).font(.system(size: 19)).foregroundStyle(color).frame(width: 28)
        }
    }
}
