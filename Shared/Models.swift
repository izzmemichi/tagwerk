import Foundation
import SwiftData

@Model
final class ListGroup {
    var id: UUID = UUID()
    var name: String = ""
    var order: Double = 0
    var isExpanded: Bool = true
    @Relationship(deleteRule: .nullify, inverse: \TaskList.group)
    var lists: [TaskList] = []

    init(name: String, order: Double) {
        self.name = name
        self.order = order
    }
}

@Model
final class TaskList {
    var id: UUID = UUID()
    var name: String = ""
    var themeRaw: String = ListTheme.blue.rawValue
    var order: Double = 0
    var isDefault: Bool = false
    var created: Date = Date()
    var group: ListGroup?
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var tasks: [TaskItem] = []

    init(name: String, theme: ListTheme, order: Double, isDefault: Bool = false) {
        self.name = name
        self.themeRaw = theme.rawValue
        self.order = order
        self.isDefault = isDefault
    }

    var theme: ListTheme {
        get { ListTheme(rawValue: themeRaw) ?? .blue }
        set { themeRaw = newValue.rawValue }
    }

    var openCount: Int { tasks.filter { !$0.isCompleted }.count }

    /// Anzeigename mit Gruppe, wie in der Metazeile: "Tasks - Uni"
    var displayName: String { name.splitEmoji.rest.isEmpty ? name : name.splitEmoji.rest }
}

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var isImportant: Bool = false
    var myDayDate: Date?
    var myDayAddedAt: Date?
    var due: Date?
    var reminder: Date?
    var repeatRaw: String?
    var spawnedNext: Bool = false
    var created: Date = Date()
    var order: Double = 0
    var list: TaskList?
    @Relationship(deleteRule: .cascade, inverse: \TaskStep.task)
    var steps: [TaskStep] = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.task)
    var attachments: [Attachment] = []

    init(title: String, order: Double) {
        self.title = title
        self.order = order
    }

    var repeatRule: RepeatRule? {
        get {
            guard let repeatRaw, let data = repeatRaw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RepeatRule.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { repeatRaw = nil; return }
            repeatRaw = String(decoding: data, as: UTF8.self)
        }
    }

    /// Wie oft die Aufgabe im Jahr ansteht, 0 für einmalige. Grundlage der Sortierung nach Rhythmus.
    var rhythmRank: Double { repeatRule?.perYear ?? 0 }

    var sortedSteps: [TaskStep] { steps.sorted { $0.order < $1.order } }
    var sortedAttachments: [Attachment] { attachments.sorted { $0.added < $1.added } }

    var isInMyDayExplicit: Bool {
        guard let myDayDate else { return false }
        return Calendar.current.isDateInToday(myDayDate)
    }

    var isDueToday: Bool {
        guard let due else { return false }
        return Calendar.current.isDateInToday(due)
    }

    func isInMyDay(dueTodayCounts: Bool) -> Bool {
        isInMyDayExplicit || (dueTodayCounts && isDueToday)
    }
}

@Model
final class TaskStep {
    var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var order: Double = 0
    var task: TaskItem?

    init(title: String, order: Double) {
        self.title = title
        self.order = order
    }
}

@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var storedName: String = ""
    var byteCount: Int = 0
    var added: Date = Date()
    var task: TaskItem?

    init(fileName: String, storedName: String, byteCount: Int) {
        self.fileName = fileName
        self.storedName = storedName
        self.byteCount = byteCount
    }

    var url: URL { Attachment.folder.appendingPathComponent(storedName) }

    static var folder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Anhänge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Wiederholung

struct RepeatRule: Codable, Equatable, Hashable {
    enum Unit: String, Codable, CaseIterable, Identifiable {
        case day, week, month, year
        var id: String { rawValue }
        func label(_ n: Int) -> String {
            switch self {
            case .day: return n == 1 ? tr("Tag") : tr("Tage")
            case .week: return n == 1 ? tr("Woche") : tr("Wochen")
            case .month: return n == 1 ? tr("Monat") : tr("Monate")
            case .year: return n == 1 ? tr("Jahr") : tr("Jahre")
            }
        }
    }

    var unit: Unit
    var interval: Int = 1
    /// Calendar-Wochentage, 1 = Sonntag ... 7 = Samstag
    var weekdays: [Int] = []

    static let daily = RepeatRule(unit: .day)
    static let workdays = RepeatRule(unit: .week, interval: 1, weekdays: [2, 3, 4, 5, 6])
    static let monthly = RepeatRule(unit: .month)
    static let yearly = RepeatRule(unit: .year)
    static func weekly(from date: Date) -> RepeatRule {
        RepeatRule(unit: .week, interval: 1, weekdays: [Calendar.current.component(.weekday, from: date)])
    }

    /// Ungefähre Vorkommen pro Jahr: täglich 365, Wochentage 260, wöchentlich 52, monatlich 12, jährlich 1
    var perYear: Double {
        let n = Double(max(interval, 1))
        switch unit {
        case .day: return 365 / n
        case .week: return 52 * Double(max(weekdays.count, 1)) / n
        case .month: return 12 / n
        case .year: return 1 / n
        }
    }

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static var weekdayShort: [Int: String] { [1: tr("So"), 2: tr("Mo"), 3: tr("Di"), 4: tr("Mi"), 5: tr("Do"), 6: tr("Fr"), 7: tr("Sa")] }

    var label: String {
        let days = RepeatRule.weekdayOrder.filter { weekdays.contains($0) }.compactMap { RepeatRule.weekdayShort[$0] }
        if interval == 1 {
            switch unit {
            case .day: return tr("Täglich")
            case .month: return tr("Monatlich")
            case .year: return tr("Jährlich")
            case .week:
                if Set(weekdays) == Set([2, 3, 4, 5, 6]) { return tr("Wochentage") }
                if weekdays.count <= 1 { return tr("Wöchentlich") }
                return tr("Wöchentlich: ") + days.joined(separator: ", ")
            }
        }
        var text = tr("Alle %lld %@", interval, unit.label(interval))
        if unit == .week, !days.isEmpty { text += ": " + days.joined(separator: ", ") }
        return text
    }

    func next(after date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let base = cal.startOfDay(for: date)
        switch unit {
        case .day: return cal.date(byAdding: .day, value: interval, to: base) ?? base
        case .month: return cal.date(byAdding: .month, value: interval, to: base) ?? base
        case .year: return cal.date(byAdding: .year, value: interval, to: base) ?? base
        case .week:
            let days = weekdays.isEmpty ? [cal.component(.weekday, from: base)] : weekdays
            guard let startWeek = cal.dateInterval(of: .weekOfYear, for: base)?.start else { return base }
            for i in 1...(7 * interval + 7) {
                guard let d = cal.date(byAdding: .day, value: i, to: base),
                      let wStart = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
                let weeks = (cal.dateComponents([.day], from: startWeek, to: wStart).day ?? 0) / 7
                if days.contains(cal.component(.weekday, from: d)) && (weeks == 0 || weeks % interval == 0) {
                    return d
                }
            }
            return cal.date(byAdding: .day, value: 7 * interval, to: base) ?? base
        }
    }
}

// MARK: - Emoji am Listenanfang

extension String {
    /// Trennt ein führendes Emoji ab: "⭐ Tasks" -> ("⭐", "Tasks")
    var splitEmoji: (emoji: String?, rest: String) {
        guard let first = first else { return (nil, self) }
        let scalars = first.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
        guard isEmoji else { return (nil, self) }
        let rest = dropFirst().trimmingCharacters(in: .whitespaces)
        return (String(first), rest)
    }
}
