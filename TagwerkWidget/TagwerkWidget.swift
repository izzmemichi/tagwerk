import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Daten

struct WidgetTask: Identifiable, Hashable {
    let id: String
    let title: String
    let meta: String
    let overdue: Bool
}

struct MyDayEntry: TimelineEntry {
    let date: Date
    let open: [WidgetTask]
    let doneCount: Int

    /// Beispiel für die Widget-Galerie
    static var sample: MyDayEntry {
        MyDayEntry(date: .now, open: [
            WidgetTask(id: "1", title: tr("Wasser trinken"), meta: tr("Aufgaben"), overdue: false),
            WidgetTask(id: "2", title: tr("Wochenbericht schreiben"), meta: tr("Arbeit"), overdue: false),
            WidgetTask(id: "3", title: tr("Paket abholen"), meta: tr("Einkaufen"), overdue: false)
        ], doneCount: 2)
    }
}

enum WidgetData {
    static var storeAvailable: Bool {
        guard let url = SharedStore.groupURL?.appendingPathComponent("Tagwerk.store") else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func load() -> MyDayEntry {
        guard storeAvailable, let container = try? SharedStore.makeContainer() else {
            return MyDayEntry(date: .now, open: [], doneCount: 0)
        }
        let ctx = ModelContext(container)
        Badge.update(ctx)
        let all = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let mine = all.filter { $0.isInMyDay(dueTodayCounts: Badge.dueTodayCounts) }
        // Gleiche Reihenfolge wie "Nach Rhythmus" in der App: täglich zuerst, einmalige zuletzt
        let open = mine.filter { !$0.isCompleted }
            .sorted { a, b in
                if a.rhythmRank != b.rhythmRank { return a.rhythmRank > b.rhythmRank }
                if a.isImportant != b.isImportant { return a.isImportant }
                return a.order < b.order
            }
            .map { t in
                let list = t.list?.name.splitEmoji.rest ?? tr("Aufgaben")
                let overdue = t.due.map { Day.offset($0) < 0 } ?? false
                return WidgetTask(id: t.id.uuidString, title: t.title,
                                  meta: overdue ? list + " • " + Day.label(t.due!) : list,
                                  overdue: overdue)
            }
        return MyDayEntry(date: .now, open: open, doneCount: mine.filter(\.isCompleted).count)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MyDayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (MyDayEntry) -> Void) {
        completion(context.isPreview ? .sample : WidgetData.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyDayEntry>) -> Void) {
        let entry = WidgetData.load()
        let midnight = Day.tomorrow
        let refresh = min(midnight, Date().addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Abhaken direkt im Widget

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgabe abhaken"
    static var isDiscoverable = false

    @Parameter(title: "Aufgabe")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        guard WidgetData.storeAvailable, let container = try? SharedStore.makeContainer() else { return .result() }
        let ctx = ModelContext(container)
        let all = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        if let task = all.first(where: { $0.id.uuidString == taskID }) {
            TaskOps.toggleComplete(task, ctx: ctx)
            ChangeLog.record(ctx)
            try? ctx.save()
            Badge.update(ctx)
            UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: SharedStore.widgetChangedKey)
        }
        return .result()
    }
}

// MARK: - Darstellung

private let sunColor = Color(red: 0.93, green: 0.55, blue: 0.20)

struct MyDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MyDayEntry

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 8
        default: return 2
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text("☀︎ " + tr("%lld offen", entry.open.count))
        default: system
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 15, weight: .semibold)).foregroundStyle(sunColor)
                Text(tr("Mein Tag")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(entry.open.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
            if family != .systemSmall {
                Text(Day.longToday()).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, -6)
            }
            if entry.open.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.doneCount > 0 ? tr("Alles erledigt") : tr("Mein Tag ist leer")).font(.system(size: 14, weight: .semibold))
                    Text(entry.doneCount > 0 ? tr("%lld erledigt", entry.doneCount) : tr("Tippen, um Aufgaben hinzuzufügen"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
                    ForEach(entry.open.prefix(maxRows)) { task in
                        row(task)
                    }
                }
                Spacer(minLength: 0)
                if entry.open.count > maxRows {
                    Text(tr("+%lld weitere", entry.open.count - maxRows)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "tagwerk://myday"))
    }

    private func row(_ task: WidgetTask) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(intent: ToggleTaskIntent(taskID: task.id)) {
                Circle()
                    .strokeBorder(Color(.systemGray2), lineWidth: 1.4)
                    .frame(width: family == .systemSmall ? 16 : 18, height: family == .systemSmall ? 16 : 18)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(.system(size: family == .systemSmall ? 13 : 14))
                    .lineLimit(1)
                if family == .systemLarge {
                    Text(task.meta)
                        .font(.system(size: 11))
                        .foregroundStyle(task.overdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "sun.max").font(.system(size: 12, weight: .semibold))
                Text("\(entry.open.count)").font(.system(size: 20, weight: .semibold))
            }
        }
        .widgetURL(URL(string: "tagwerk://myday"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(tr("Mein Tag · %lld", entry.open.count), systemImage: "sun.max").font(.system(size: 13, weight: .semibold))
            if entry.open.isEmpty {
                Text(tr("Alles erledigt")).font(.system(size: 13))
            } else {
                ForEach(entry.open.prefix(2)) { task in
                    Text("◦ " + task.title).font(.system(size: 13)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "tagwerk://myday"))
    }
}

struct MyDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TagwerkMyDay", provider: Provider()) { entry in
            MyDayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.card }
        }
        .configurationDisplayName(tr("Mein Tag"))
        .description(tr("Deine Aufgaben für heute, direkt abhaken."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TagwerkWidgets: WidgetBundle {
    var body: some Widget {
        MyDayWidget()
    }
}
