import SwiftUI
import SwiftData

struct TaskRow: View {
    let task: TaskItem
    let showList: Bool
    let showMyDay: Bool
    let accent: Color
    let onToggle: () -> Void

    @State private var completing = false
    private var shownDone: Bool { task.isCompleted || completing }

    private func toggle() {
        guard !task.isCompleted else { onToggle(); return }
        withAnimation(.snappy(duration: 0.2)) { completing = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            onToggle()
            completing = false
        }
    }

    private enum Part: Hashable {
        case list(String)
        case myDay
        case steps(Int, Int)
        case due(Date, Bool)
        case reminder(Date)
        case note
        case attachment
    }

    private var parts: [Part] {
        var p: [Part] = []
        if showMyDay, task.isInMyDayExplicit { p.append(.myDay) }
        if showList, let list = task.list { p.append(.list(list.name)) }
        if !task.steps.isEmpty {
            p.append(.steps(task.steps.filter(\.isCompleted).count, task.steps.count))
        }
        if let due = task.due { p.append(.due(due, task.repeatRaw != nil)) }
        if let reminder = task.reminder, !task.isCompleted { p.append(.reminder(reminder)) }
        if !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p.append(.note) }
        if !task.attachments.isEmpty { p.append(.attachment) }
        return p
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: toggle) {
                CheckCircle(done: shownDone, accent: accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isCompleted ? tr("Als nicht erledigt markieren") : tr("Als erledigt markieren"))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 17))
                    .strikethrough(shownDone)
                    .foregroundStyle(shownDone ? .secondary : .primary)
                    .lineLimit(3)
                let metaParts = parts
                if !metaParts.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(metaParts.enumerated()), id: \.offset) { index, part in
                            if index > 0 { Text("•") }
                            partView(part)
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            StarButton(on: task.isImportant, accent: accent) {
                withAnimation { task.isImportant.toggle() }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func partView(_ part: Part) -> some View {
        switch part {
        case .list(let name):
            Text(name)
        case .myDay:
            Label(tr("Mein Tag"), systemImage: "sun.max").labelStyle(TightLabel())
        case .steps(let done, let total):
            Text(tr("%lld von %lld", done, total))
        case .due(let date, let repeats):
            let offset = Day.offset(date)
            let color: Color = task.isCompleted ? .secondary : (offset < 0 ? .red : (offset == 0 ? .blue : .secondary))
            HStack(spacing: 2) {
                Image(systemName: "calendar")
                Text(Day.label(date))
                if repeats { Image(systemName: "repeat") }
            }
            .foregroundStyle(color)
        case .reminder(let date):
            HStack(spacing: 2) {
                Image(systemName: "bell")
                Text(Day.offset(date) == 0 ? Day.time(date) : Day.label(date))
            }
        case .note:
            Image(systemName: "note.text").accessibilityLabel(tr("Notiz"))
        case .attachment:
            Image(systemName: "paperclip").accessibilityLabel(tr("Datei"))
        }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon; configuration.title }
    }
}

/// Kontextmenü einer Aufgabe, wie in der Mac-App beobachtet
struct TaskMenu: View {
    let task: TaskItem
    let lists: [TaskList]
    let onToggle: () -> Void
    let onPickDate: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Button { Store.setMyDay(task, !task.isInMyDayExplicit) } label: {
            Label(task.isInMyDayExplicit ? tr("Aus „Mein Tag“ entfernen") : tr("Zu „Mein Tag“ hinzufügen"), systemImage: "sun.max")
        }
        Button { task.isImportant.toggle() } label: {
            Label(task.isImportant ? tr("Als nicht wichtig markieren") : tr("Als wichtig markieren"),
                  systemImage: task.isImportant ? "star.slash" : "star")
        }
        Button(action: onToggle) {
            Label(task.isCompleted ? tr("Als nicht erledigt markieren") : tr("Als erledigt markieren"),
                  systemImage: task.isCompleted ? "circle" : "checkmark.circle")
        }
        Divider()
        Button { task.due = Day.today } label: { Label(tr("Fällig Heute"), systemImage: "calendar") }
        Button { task.due = Day.tomorrow } label: { Label(tr("Fällig Morgen"), systemImage: "arrow.right.circle") }
        Button(action: onPickDate) { Label(tr("Datum auswählen"), systemImage: "calendar.badge.plus") }
        if task.due != nil {
            Button { task.due = nil } label: { Label(tr("Fälligkeitsdatum entfernen"), systemImage: "calendar.badge.minus") }
        }
        Divider()
        Button { _ = Store.listFromTask(task, ctx: ctx) } label: {
            Label(tr("Neue Liste aus dieser Aufgabe erstellen"), systemImage: "list.bullet.rectangle")
        }
        Menu {
            ForEach(lists) { list in
                Button(list.name) { Store.move(task, to: list) }
                    .disabled(list.id == task.list?.id)
            }
        } label: {
            Label(tr("Aufgabe verschieben in …"), systemImage: "arrow.right.square")
        }
        Divider()
        Button(role: .destructive, action: onDelete) { Label(tr("Aufgabe löschen"), systemImage: "trash") }
    }
}
