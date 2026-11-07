import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

struct TaskDetailView: View {
    @Bindable var task: TaskItem

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.order) private var lists: [TaskList]
    @AppStorage(Pref.confirmDelete) private var confirmDelete = true

    @State private var newStep = ""
    @State private var showDuePicker = false
    @State private var showReminderPicker = false
    @State private var showRepeatCustom = false
    @State private var showImporter = false
    @State private var previewURL: URL?
    @State private var confirmDeletion = false
    @FocusState private var stepFocused: Bool

    private var accent: Color { task.list?.theme.accent ?? ListTheme.blue.accent }

    private var moveTargets: [TaskList] {
        lists.sorted { ($0.isDefault ? -1 : $0.order) < ($1.isDefault ? -1 : $1.order) }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Button { withAnimation { Store.toggleComplete(task, ctx: ctx) } } label: {
                        CheckCircle(done: task.isCompleted, accent: accent, size: 26)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                    TextField(tr("Titel"), text: $task.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    StarButton(on: task.isImportant, accent: accent) { task.isImportant.toggle() }
                }
                .padding(.vertical, 6)

                ForEach(task.sortedSteps) { step in
                    StepRow(step: step, accent: accent)
                        .swipeActions {
                            Button(role: .destructive) { ctx.delete(step) } label: { Label(tr("Löschen"), systemImage: "trash") }
                        }
                        .contextMenu {
                            Button { step.isCompleted.toggle() } label: {
                                Label(step.isCompleted ? tr("Als nicht erledigt markieren") : tr("Als erledigt markieren"),
                                      systemImage: "checkmark.circle")
                            }
                            Button { Store.promote(step, ctx: ctx) } label: {
                                Label(tr("Zu Aufgabe heraufstufen"), systemImage: "arrow.up.square")
                            }
                            Button(role: .destructive) { ctx.delete(step) } label: { Label(tr("Schritt löschen"), systemImage: "trash") }
                        }
                }

                HStack(spacing: 12) {
                    Image(systemName: "plus").foregroundStyle(accent).frame(width: 26)
                    TextField(task.steps.isEmpty ? tr("Schritt hinzufügen") : tr("Nächster Schritt"), text: $newStep)
                        .focused($stepFocused)
                        .submitLabel(.next)
                        .onSubmit(addStep)
                        .tint(accent)
                }
            }

            Section {
                HStack {
                    Button {
                        Store.setMyDay(task, !task.isInMyDayExplicit)
                    } label: {
                        detailLabel("sun.max",
                                    task.isInMyDayExplicit ? tr("Zu „Mein Tag“ hinzugefügt") : tr("Zu „Mein Tag“ hinzufügen"),
                                    on: task.isInMyDayExplicit)
                    }
                    .buttonStyle(.borderless)
                    if task.isInMyDayExplicit { clearButton { Store.setMyDay(task, false) } }
                }
            }

            Section {
                HStack {
                    Menu {
                        ReminderMenuItems(hasValue: task.reminder != nil, set: setReminder, pick: { showReminderPicker = true })
                    } label: {
                        detailLabel("bell",
                                    task.reminder.map { tr("Erinnerung um %@", Day.time($0)) } ?? tr("Erinnerung"),
                                    sub: task.reminder.map { Day.label($0) },
                                    on: task.reminder != nil)
                    }
                    if task.reminder != nil { clearButton { setReminder(nil) } }
                }
                HStack {
                    Menu {
                        DueMenuItems(hasValue: task.due != nil, set: { task.due = $0 }, pick: { showDuePicker = true })
                    } label: {
                        detailLabel("calendar",
                                    task.due.map { tr("Fällig %@", Day.label($0)) } ?? tr("Fälligkeitsdatum hinzufügen"),
                                    on: task.due != nil,
                                    alert: task.due.map { Day.offset($0) < 0 && !task.isCompleted } ?? false)
                    }
                    if task.due != nil { clearButton { task.due = nil } }
                }
                HStack {
                    Menu {
                        RepeatMenuItems(current: task.repeatRule, base: task.due ?? Day.today,
                                        set: setRepeat, custom: { showRepeatCustom = true })
                    } label: {
                        detailLabel("repeat", task.repeatRule?.label ?? tr("Wiederholen"), on: task.repeatRule != nil)
                    }
                    if task.repeatRule != nil { clearButton { setRepeat(nil) } }
                }
            }

            Section {
                ForEach(task.sortedAttachments) { file in
                    Button { previewURL = file.url } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").foregroundStyle(accent).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.fileName).foregroundStyle(.primary).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? FileManager.default.removeItem(at: file.url)
                            ctx.delete(file)
                        } label: { Label(tr("Löschen"), systemImage: "trash") }
                    }
                }
                Button { showImporter = true } label: { detailLabel("paperclip", tr("Datei hinzufügen"), on: false) }
            }

            Section {
                TextField(tr("Notiz hinzufügen"), text: $task.note, axis: .vertical)
                    .lineLimit(4...)
                    .tint(accent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(task.list?.name ?? tr("Aufgaben")).font(.subheadline.weight(.semibold))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Menu {
                        ForEach(moveTargets) { list in
                            Button(list.name) { Store.move(task, to: list) }.disabled(list.id == task.list?.id)
                        }
                    } label: { Label(tr("Aufgabe verschieben in …"), systemImage: "arrow.right.square") }
                    Button { _ = Store.listFromTask(task, ctx: ctx); dismiss() } label: {
                        Label(tr("Neue Liste aus dieser Aufgabe erstellen"), systemImage: "list.bullet.rectangle")
                    }
                    ShareLink(item: shareText) { Label(tr("Aufgabe teilen"), systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .tint(accent)
        .sheet(isPresented: $showDuePicker) {
            DatePickSheet(title: tr("Fälligkeitsdatum"), withTime: false, date: task.due ?? Day.today) { task.due = $0 }
        }
        .sheet(isPresented: $showReminderPicker) {
            DatePickSheet(title: tr("Erinnerung"), withTime: true, date: task.reminder ?? Day.at(Day.tomorrow, hour: 9)) { setReminder($0) }
        }
        .sheet(isPresented: $showRepeatCustom) {
            RepeatCustomSheet(rule: task.repeatRule ?? .weekly(from: task.due ?? Day.today), accent: accent) { setRepeat($0) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { Store.addAttachment(from: url, to: task, ctx: ctx) }
            }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(tr("„%@“ wird endgültig gelöscht.", task.title), isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button(tr("Aufgabe löschen"), role: .destructive) { deleteTask() }
        } message: {
            Text(tr("Diese Aktion kann nicht rückgängig gemacht werden."))
        }
        .onDisappear {
            if task.modelContext != nil, task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                task.title = tr("Unbenannte Aufgabe")
            }
            if task.modelContext != nil { Reminders.schedule(task) }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(footerText).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button {
                if confirmDelete { confirmDeletion = true } else { deleteTask() }
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .accessibilityLabel(tr("Aufgabe löschen"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footerText: String {
        if task.isCompleted, let done = task.completedAt {
            return tr("Erledigt am %@", done.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Day.locale)))
        }
        let seconds = Date().timeIntervalSince(task.created)
        if seconds < 60 { return tr("Vor wenigen Momenten erstellt") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Day.locale
        formatter.unitsStyle = .full
        return tr("Erstellt %@", formatter.localizedString(for: task.created, relativeTo: Date()))
    }

    private var shareText: String {
        var lines = [task.title]
        for step in task.sortedSteps { lines.append((step.isCompleted ? "☑︎ " : "☐ ") + step.title) }
        if let due = task.due { lines.append(tr("Fällig: %@", Day.label(due))) }
        if !task.note.isEmpty { lines.append(""); lines.append(task.note) }
        return lines.joined(separator: "\n")
    }

    private func detailLabel(_ icon: String, _ text: String, sub: String? = nil, on: Bool, alert: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                if let sub { Text(sub).font(.caption) }
            }
            Spacer()
        }
        .foregroundStyle(alert ? Color.red : (on ? accent : Color.secondary))
        .contentShape(Rectangle())
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(tr("Entfernen"))
    }

    private func addStep() {
        let trimmed = newStep.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let step = TaskStep(title: trimmed, order: (task.steps.map(\.order).max() ?? 0) + 1)
        ctx.insert(step)
        step.task = task
        newStep = ""
        stepFocused = true
    }

    private func setReminder(_ date: Date?) {
        task.reminder = date
        Reminders.schedule(task)
    }

    private func setRepeat(_ rule: RepeatRule?) {
        task.repeatRule = rule
        task.spawnedNext = false
        if rule != nil, task.due == nil { task.due = Day.today }
    }

    private func deleteTask() {
        let doomed = task
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            Store.delete(doomed, ctx: ctx)
        }
    }
}

struct StepRow: View {
    @Bindable var step: TaskStep
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Button { withAnimation { step.isCompleted.toggle() } } label: {
                CheckCircle(done: step.isCompleted, accent: accent, size: 18)
            }
            .buttonStyle(.borderless)
            .frame(width: 26)
            TextField(tr("Schritt"), text: $step.title, axis: .vertical)
                .strikethrough(step.isCompleted)
                .foregroundStyle(step.isCompleted ? .secondary : .primary)
        }
    }
}
