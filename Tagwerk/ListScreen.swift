import SwiftUI
import SwiftData

enum ListSource: Hashable {
    case smart(SmartList)
    case list(TaskList)

    var key: String {
        switch self {
        case .smart(let s): return s.rawValue
        case .list(let l): return l.id.uuidString
        }
    }
}

enum PlannedFilter: String, CaseIterable, Identifiable {
    case all, overdue, today, tomorrow, thisWeek, later
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return tr("Alles geplant")
        case .overdue: return tr("Überfällig")
        case .today: return tr("Heute")
        case .tomorrow: return tr("Morgen")
        case .thisWeek: return tr("Diese Woche")
        case .later: return tr("Später")
        }
    }

    func matches(_ day: Date) -> Bool {
        let o = Day.offset(day)
        let daysToSunday = (8 - Day.cal.component(.weekday, from: Day.today)) % 7
        switch self {
        case .all: return true
        case .overdue: return o < 0
        case .today: return o == 0
        case .tomorrow: return o == 1
        case .thisWeek: return o >= 0 && o <= daysToSunday
        case .later: return o > daysToSunday
        }
    }
}

private struct DateBucket: Identifiable {
    let day: Date
    let items: [TaskItem]
    var id: Date { day }
}

private struct ListBucket: Identifiable {
    let list: TaskList
    let items: [TaskItem]
    var id: PersistentIdentifier { list.persistentModelID }
}

private struct TaskGroup: Identifiable {
    let id: String
    let title: String
    let rank: Double
    let items: [TaskItem]
}

struct ListScreen: View {
    let source: ListSource

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    @Query(sort: \TaskList.order) private var lists: [TaskList]
    @Query(sort: \ListGroup.order) private var groups: [ListGroup]

    @AppStorage private var sortRaw: String
    @AppStorage private var sortAscending: Bool
    @AppStorage private var hideCompleted: Bool
    @AppStorage private var completedExpanded: Bool
    @AppStorage private var smartThemeRaw: String
    @AppStorage(Pref.importantToTop) private var importantToTop = true
    @AppStorage(Pref.dueTodayInMyDay) private var dueTodayInMyDay = true
    @AppStorage(Pref.confirmDelete) private var confirmDelete = true

    @State private var plannedFilter: PlannedFilter = .all
    @State private var showSuggestions = false
    @State private var showRename = false
    @State private var showTheme = false
    @State private var confirmListDelete = false
    @State private var taskToDelete: TaskItem?
    @State private var dueSheetTask: TaskItem?

    init(source: ListSource) {
        self.source = source
        let key = source.key
        var defaultSort = ""
        if case .smart(.myDay) = source { defaultSort = SortMode.rhythm.rawValue }
        _sortRaw = AppStorage(wrappedValue: defaultSort, "sort.\(key)")
        _sortAscending = AppStorage(wrappedValue: true, "sortAsc.\(key)")
        _hideCompleted = AppStorage(wrappedValue: false, "hideDone.\(key)")
        _completedExpanded = AppStorage(wrappedValue: true, "doneOpen.\(key)")
        _collapsedSectionsRaw = AppStorage(wrappedValue: "", "collapsed.\(key)")
        var defaultTheme = ""
        if case .smart(let s) = source { defaultTheme = s.defaultTheme.rawValue }
        _smartThemeRaw = AppStorage(wrappedValue: defaultTheme, "theme.\(key)")
    }

    // MARK: Ableitungen

    private var smart: SmartList? {
        if case .smart(let s) = source { return s }
        return nil
    }

    private var customList: TaskList? {
        if case .list(let l) = source { return l }
        return nil
    }

    private var title: String { customList?.name ?? smart?.title ?? "" }

    private var theme: ListTheme {
        if let customList { return customList.theme }
        return ListTheme(rawValue: smartThemeRaw) ?? smart?.defaultTheme ?? .blue
    }

    private var sortMode: SortMode? { SortMode(rawValue: sortRaw) }

    private var showListName: Bool {
        guard let smart else { return false }
        return smart != .tasks
    }

    private var canAdd: Bool { smart != .completed }

    private var scoped: [TaskItem] {
        if let customList { return allTasks.filter { $0.list?.id == customList.id } }
        switch smart ?? .tasks {
        case .myDay: return allTasks.filter { $0.isInMyDay(dueTodayCounts: dueTodayInMyDay) }
        case .important: return allTasks.filter { $0.isImportant && !$0.isCompleted }
        case .planned: return allTasks.filter { ($0.due != nil || $0.reminder != nil) && !$0.isCompleted }
        case .all: return allTasks.filter { !$0.isCompleted }
        case .completed: return allTasks.filter { $0.isCompleted }
        case .tasks: return allTasks.filter { $0.list?.isDefault == true }
        }
    }

    private func sorted(_ items: [TaskItem]) -> [TaskItem] {
        guard let mode = sortMode else {
            let base = items.sorted { $0.order < $1.order }
            return importantToTop ? base.filter(\.isImportant) + base.filter { !$0.isImportant } : base
        }
        let result = items.sorted { a, b in
            switch mode {
            case .rhythm:
                if a.rhythmRank != b.rhythmRank { return a.rhythmRank > b.rhythmRank }
                return Self.byImportance(a, b)
            case .list:
                let la: Double = Self.listPosition(a)
                let lb: Double = Self.listPosition(b)
                if la != lb { return la < lb }
                return Self.byImportance(a, b)
            case .importance:
                if a.isImportant != b.isImportant { return a.isImportant }
                return a.order < b.order
            case .alphabetical:
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .dueDate:
                switch (a.due, b.due) {
                case let (x?, y?): return x == y ? a.order < b.order : x < y
                case (nil, nil): return a.order < b.order
                case (nil, _): return false
                case (_, nil): return true
                }
            case .created:
                return a.created > b.created
            case .myDay:
                return (a.myDayAddedAt ?? .distantPast) > (b.myDayAddedAt ?? .distantPast)
            }
        }
        return sortAscending ? result : result.reversed()
    }

    private static func byImportance(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isImportant != b.isImportant { return a.isImportant }
        return a.order < b.order
    }

    private static func listPosition(_ task: TaskItem) -> Double {
        guard let list = task.list else { return Double.greatestFiniteMagnitude }
        return list.isDefault ? -1.0 : list.order
    }

    /// Abschnitte für "Nach Rhythmus" (täglich zuerst, einmalige zuletzt) und "Nach Liste"
    private func taskGroups(_ open: [TaskItem], by mode: SortMode) -> [TaskGroup] {
        var result: [TaskGroup] = []
        if mode == .list {
            for list in moveTargets {
                let items: [TaskItem] = open.filter { $0.list?.id == list.id }
                if items.isEmpty { continue }
                result.append(TaskGroup(id: "l" + list.id.uuidString, title: list.name,
                                        rank: 0, items: items.sorted(by: Self.byImportance)))
            }
            return result
        }
        let byRule: [String: [TaskItem]] = Dictionary(grouping: open) { (t: TaskItem) -> String in
            t.repeatRule?.label ?? tr("Einmalig")
        }
        for (label, items) in byRule {
            let rank: Double = items.map(\.rhythmRank).max() ?? 0
            result.append(TaskGroup(id: "r" + label, title: label, rank: rank, items: items.sorted(by: Self.byImportance)))
        }
        result.sort { (x: TaskGroup, y: TaskGroup) -> Bool in
            if x.rank != y.rank { return x.rank > y.rank }
            return x.title < y.title
        }
        return result
    }

    private var plannedBuckets: [DateBucket] {
        let dated = scoped.compactMap { t -> (Date, TaskItem)? in
            guard let d = t.due ?? t.reminder.map(Day.start) else { return nil }
            return (Day.start(d), t)
        }
        let filtered = dated.filter { plannedFilter.matches($0.0) }
        let grouped = Dictionary(grouping: filtered, by: { $0.0 })
        return grouped.keys.sorted().map { day in
            DateBucket(day: day, items: sorted(grouped[day]!.map(\.1)))
        }
    }

    private var listBuckets: [ListBucket] {
        let grouped = Dictionary(grouping: scoped, by: { $0.list?.persistentModelID })
        let ordered = lists.sorted { ($0.isDefault ? -1 : $0.order) < ($1.isDefault ? -1 : $1.order) }
        return ordered.compactMap { list in
            guard let items = grouped[list.persistentModelID], !items.isEmpty else { return nil }
            let sortedItems = smart == .completed
                ? items.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                : sorted(items)
            return ListBucket(list: list, items: sortedItems)
        }
    }

    private var moveTargets: [TaskList] {
        lists.sorted { ($0.isDefault ? -1 : $0.order) < ($1.isDefault ? -1 : $1.order) }
    }

    // MARK: Ansicht

    @State private var collapsed = false
    @AppStorage private var collapsedSectionsRaw: String

    private var collapsedSections: Set<String> {
        Set(collapsedSectionsRaw.split(separator: "|").map(String.init))
    }

    private func toggleSection(_ key: String) {
        var set = collapsedSections
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        withAnimation(.snappy(duration: 0.25)) { collapsedSectionsRaw = set.sorted().joined(separator: "|") }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            List {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 6, trailing: 18))
                content
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 46
            } action: { _, isCollapsed in
                withAnimation(.easeOut(duration: 0.15)) { collapsed = isCollapsed }
            }
            .animation(.default, value: allTasks.map(\.isCompleted))

            if canAdd {
                AddTaskBar(accent: theme.accent, placeholder: tr("Aufgabe hinzufügen")) { text, due, reminder, rule, important in
                    add(text, due: due, reminder: reminder, rule: rule, important: important)
                }
            }
        }
        .background(theme.gradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSuggestions) { SuggestionsSheet(accent: theme.accent) }
        .sheet(isPresented: $showTheme) { ThemePickerSheet(theme: themeBinding) }
        .sheet(isPresented: $showRename) {
            if let l = customList {
                ListEditorSheet(title: tr("Liste umbenennen"), name: l.name, theme: l.theme) { name, newTheme in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { l.name = trimmed }
                    l.theme = newTheme
                }
            }
        }
        .sheet(item: $dueSheetTask) { task in
            DatePickSheet(title: tr("Fälligkeitsdatum"), withTime: false, date: task.due ?? Day.today) { task.due = $0 }
        }
        .confirmationDialog(tr("„%@“ wird endgültig gelöscht.", title), isPresented: $confirmListDelete, titleVisibility: .visible) {
            Button(tr("Liste löschen"), role: .destructive) { deleteList() }
        } message: {
            Text(tr("Diese Aktion kann nicht rückgängig gemacht werden."))
        }
        .confirmationDialog(tr("„%@“ wird endgültig gelöscht.", taskToDelete?.title ?? ""),
                            isPresented: Binding(get: { taskToDelete != nil }, set: { if !$0 { taskToDelete = nil } }),
                            titleVisibility: .visible) {
            Button(tr("Aufgabe löschen"), role: .destructive) {
                if let t = taskToDelete { withAnimation { Store.delete(t, ctx: ctx) } }
                taskToDelete = nil
            }
        } message: {
            Text(tr("Diese Aktion kann nicht rückgängig gemacht werden."))
        }
    }

    private var themeBinding: Binding<ListTheme> {
        Binding(get: { theme }, set: { newValue in
            if let customList { customList.theme = newValue } else { smartThemeRaw = newValue.rawValue }
        })
    }

    /// Feste Kopfzeile: "‹ Listen", beim Scrollen der Titel klein in der Mitte, rechts Optionen
    private var topBar: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 110)
                .opacity(collapsed ? 1 : 0)
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 21, weight: .semibold))
                        Text(tr("Listen")).font(.system(size: 19))
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                Spacer()
                if smart == .myDay {
                    Button { showSuggestions = true } label: {
                        Image(systemName: "lightbulb").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("Vorschläge"))
                }
                optionsMenu
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 48)
    }

    private func chip(_ icon: String?, _ text: String) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.2)))
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)
                if smart == .myDay {
                    Text(Day.longToday()).font(.system(size: 17)).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            if smart == .planned || sortMode != nil {
                HStack(spacing: 8) {
                    if smart == .planned {
                        Menu {
                            Picker(tr("Filter"), selection: $plannedFilter) {
                                ForEach(PlannedFilter.allCases) { f in Text(f.title).tag(f) }
                            }
                        } label: {
                            chip("line.3.horizontal", plannedFilter.title)
                        }
                    }
                    if let mode = sortMode {
                        HStack(spacing: 0) {
                            Button { sortAscending.toggle() } label: {
                                HStack(spacing: 6) {
                                    Text(tr("Nach %@", mode.title))
                                    if !mode.groups {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                }
                                .padding(.leading, 14).padding(.trailing, 8)
                                .frame(height: 40)
                            }
                            .disabled(mode.groups)
                            Button { sortRaw = "" } label: {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                                    .padding(.trailing, 14).padding(.leading, 4)
                                    .frame(height: 40)
                            }
                            .accessibilityLabel(tr("Sortierung entfernen"))
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.2)))
                        .lineLimit(1)
                    }
                }
                .padding(.leading, -10)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var content: some View {
        if smart == .planned {
            ForEach(plannedBuckets) { bucket in
                let key = "d\(Int(bucket.day.timeIntervalSince1970))"
                sectionHeader(key, Day.label(bucket.day), alert: Day.offset(bucket.day) < 0)
                if !collapsedSections.contains(key) {
                    ForEach(bucket.items) { row($0) }
                }
            }
            if plannedBuckets.isEmpty { emptyState }
        } else if smart == .all || smart == .completed {
            ForEach(listBuckets) { bucket in
                let key = "l" + bucket.list.id.uuidString
                sectionHeader(key, bucket.list.name, alert: false)
                if !collapsedSections.contains(key) {
                    ForEach(bucket.items) { row($0) }
                }
            }
            if listBuckets.isEmpty { emptyState }
        } else {
            let open = sorted(scoped.filter { !$0.isCompleted })
            let done = scoped.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            openSection(open)
            if !done.isEmpty && !hideCompleted {
                sectionHeader("done", tr("Erledigt"), alert: false, count: done.count)
                if !collapsedSections.contains("done") {
                    ForEach(done) { row($0) }
                }
            }
            if open.isEmpty && (done.isEmpty || hideCompleted) { emptyState }
        }
    }

    /// Offene Aufgaben: in Abschnitten (Rhythmus, Liste) oder als eine verschiebbare Liste
    @ViewBuilder
    private func openSection(_ open: [TaskItem]) -> some View {
        if let mode = sortMode, mode.groups {
            ForEach(taskGroups(open, by: mode)) { (group: TaskGroup) in
                groupSection(group)
            }
        } else {
            ForEach(open) { row($0) }
                .onMove(perform: sortMode == nil ? moveHandler(open) : nil)
        }
    }

    @ViewBuilder
    private func groupSection(_ group: TaskGroup) -> some View {
        sectionHeader(group.id, group.title, alert: false, count: group.items.count)
        if !collapsedSections.contains(group.id) {
            ForEach(group.items) { row($0) }
        }
    }

    private func sectionHeader(_ key: String, _ text: String, alert: Bool, count: Int? = nil) -> some View {
        let isCollapsed = collapsedSections.contains(key)
        return Button { toggleSection(key) } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Text(text)
                if let count { Text("\(count)").opacity(0.75) }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(alert ? Color.red.opacity(0.55) : Color.black.opacity(0.2)))
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 6, trailing: 8))
    }

    @ViewBuilder
    private var emptyState: some View {
        let text: (String, String)? = {
            switch smart {
            case .myDay: return (tr("Konzentriere dich auf deinen Tag"), tr("Erledige Aufgaben mit „Mein Tag“, einer Liste, die jeden Tag neu beginnt."))
            case .important: return (tr("Nichts als wichtig markiert"), tr("Markiere Aufgaben mit dem Stern, damit sie hier erscheinen."))
            case .planned: return (tr("Nichts geplant"), tr("Aufgaben mit Fälligkeitsdatum oder Erinnerung erscheinen hier."))
            case .all: return (tr("Keine offenen Aufgaben"), tr("Alle offenen Aufgaben aus allen Listen erscheinen hier."))
            case .completed: return (tr("Noch nichts erledigt"), tr("Erledigte Aufgaben aus allen Listen erscheinen hier."))
            default: return nil
            }
        }()
        if let text {
            VStack(spacing: 8) {
                Image(systemName: smart?.icon ?? "checklist").font(.system(size: 40, weight: .light))
                Text(text.0).font(.headline)
                Text(text.1).font(.subheadline).multilineTextAlignment(.center).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task, showList: showListName, showMyDay: smart != .myDay, accent: theme.accent) {
            withAnimation { Store.toggleComplete(task, ctx: ctx) }
        }
        .background(NavigationLink(value: task) { EmptyView() }.opacity(0))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.card)
                .padding(.horizontal, 8)
                .padding(.vertical, 1.5)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1.5, leading: 22, bottom: 1.5, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { withAnimation { Store.setMyDay(task, !task.isInMyDayExplicit) } } label: {
                Label(task.isInMyDayExplicit ? tr("Entfernen") : tr("Mein Tag"),
                      systemImage: task.isInMyDayExplicit ? "sun.min" : "sun.max")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { requestDelete(task) } label: { Label(tr("Löschen"), systemImage: "trash") }
                .tint(.red)
        }
        .contextMenu {
            TaskMenu(task: task, lists: moveTargets,
                     onToggle: { withAnimation { Store.toggleComplete(task, ctx: ctx) } },
                     onPickDate: { dueSheetTask = task },
                     onDelete: { requestDelete(task) })
        }
    }

    private var optionsMenu: some View {
            Menu {
                if let l = customList {
                    Button { showRename = true } label: { Label(tr("Liste umbenennen"), systemImage: "pencil") }
                    Menu {
                        Button { l.group = nil } label: { Label(tr("Keine Gruppe"), systemImage: l.group == nil ? "checkmark" : "tray") }
                        ForEach(groups) { g in
                            Button { l.group = g } label: { Label(g.name, systemImage: l.group?.id == g.id ? "checkmark" : "folder") }
                        }
                    } label: { Label(tr("Liste verschieben in …"), systemImage: "folder") }
                }
                Menu {
                    ForEach(SortMode.allCases.filter { $0 != .list || showListName }) { mode in
                        Button {
                            if sortRaw == mode.rawValue { sortRaw = "" } else { sortRaw = mode.rawValue; sortAscending = true }
                        } label: {
                            Label(mode.title, systemImage: sortRaw == mode.rawValue ? "checkmark" : mode.icon)
                        }
                    }
                } label: { Label(tr("Sortieren"), systemImage: "arrow.up.arrow.down") }
                Button { showTheme = true } label: { Label(tr("Design ändern"), systemImage: "paintpalette") }
                if let l = customList {
                    Button { _ = Store.duplicate(l, ctx: ctx) } label: { Label(tr("Liste duplizieren"), systemImage: "plus.square.on.square") }
                }
                if smart != .completed {
                    Button { hideCompleted.toggle() } label: {
                        Label(hideCompleted ? tr("Erledigte Aufgaben anzeigen") : tr("Erledigte Aufgaben ausblenden"),
                              systemImage: hideCompleted ? "eye" : "checkmark.circle")
                    }
                }
                if customList != nil {
                    Divider()
                    Button(role: .destructive) { confirmListDelete = true } label: { Label(tr("Liste löschen"), systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(tr("Listenoptionen"))
    }

    // MARK: Aktionen

    private func add(_ text: String, due: Date?, reminder: Date?, rule: RepeatRule?, important: Bool) {
        let target = customList ?? Store.defaultList(ctx)
        withAnimation {
            _ = Store.addTask(title: text, to: target,
                              important: important || smart == .important,
                              myDay: smart == .myDay,
                              due: due ?? (smart == .planned ? Day.today : nil),
                              reminder: reminder, rule: rule, ctx: ctx)
        }
    }

    private func moveHandler(_ open: [TaskItem]) -> (IndexSet, Int) -> Void {
        { from, to in move(open, from: from, to: to) }
    }

    private func move(_ open: [TaskItem], from: IndexSet, to: Int) {
        var arranged = open
        arranged.move(fromOffsets: from, toOffset: to)
        for (index, task) in arranged.enumerated() { task.order = Double(index) }
    }

    private func requestDelete(_ task: TaskItem) {
        if confirmDelete { taskToDelete = task } else { withAnimation { Store.delete(task, ctx: ctx) } }
    }

    private func deleteList() {
        guard let l = customList else { return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            Store.delete(l, ctx: ctx)
        }
    }
}

// MARK: - Eingabeleiste

struct AddTaskBar: View {
    let accent: Color
    let placeholder: String
    let onAdd: (String, Date?, Date?, RepeatRule?, Bool) -> Void

    @State private var text = ""
    @State private var due: Date?
    @State private var reminder: Date?
    @State private var rule: RepeatRule?
    @State private var disabled: Set<QuickAddParser.Kind> = []
    @State private var showDue = false
    @State private var showReminder = false
    @State private var showCustom = false
    @State private var editing = false
    @FocusState private var focused: Bool

    private var parsed: QuickParse { QuickAddParser.parse(text, disabled: disabled) }
    private var effDue: Date? { due ?? parsed.due }
    private var effReminder: Date? { reminder ?? parsed.reminder }
    private var effRule: RepeatRule? { rule ?? parsed.rule }
    private var hasInput: Bool { !text.isEmpty || due != nil || reminder != nil || rule != nil }
    private var active: Bool { editing || focused || hasInput }
    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if active {
                activeField
            } else {
                Button { editing = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .light)).frame(width: 26)
                        Text(placeholder).font(.system(size: 19))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .sheet(isPresented: $showDue) {
            DatePickSheet(title: tr("Fälligkeitsdatum"), withTime: false, date: effDue ?? Day.today) { due = $0; focused = true }
        }
        .sheet(isPresented: $showReminder) {
            DatePickSheet(title: tr("Erinnerung"), withTime: true, date: effReminder ?? Day.at(Day.tomorrow, hour: 9)) { reminder = $0; focused = true }
        }
        .sheet(isPresented: $showCustom) {
            RepeatCustomSheet(rule: effRule ?? .weekly(from: effDue ?? Day.today), accent: accent) { rule = $0; focused = true }
        }
    }

    private var activeField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                CheckCircle(done: false, accent: accent, size: 24)
                TextField(placeholder, text: $text)
                    .font(.system(size: 17))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .tint(accent)
                    .onAppear {
                        // Feld existiert erst jetzt, deshalb den Fokus einen Takt später setzen
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                    }
                    .onChange(of: focused) { _, isFocused in
                        guard !isFocused else { return }
                        // Zuklappen, wenn die Tastatur ohne Eingabe geschlossen wurde (nicht während Menü oder Blatt)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if !focused && !hasInput && !showDue && !showReminder && !showCustom { editing = false }
                        }
                    }
                if canSubmit {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(accent)
                    }
                    .accessibilityLabel(tr("Aufgabe hinzufügen"))
                }
            }
            if canSubmit && parsed.title != text.trimmingCharacters(in: .whitespaces) {
                Text(Lang.code == "de" ? "„\(parsed.title)“" : "“\(parsed.title)”")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 38)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        DueMenuItems(hasValue: effDue != nil, set: { value in
                            due = value
                            if value == nil { disabled.insert(.date) }
                            focused = true
                        }, pick: { showDue = true })
                    } label: {
                        chip("calendar", effDue.map(Day.label) ?? tr("Fällig"), on: effDue != nil)
                    }
                    Menu {
                        ReminderMenuItems(hasValue: effReminder != nil, set: { value in
                            reminder = value
                            if value == nil { disabled.insert(.time) }
                            focused = true
                        }, pick: { showReminder = true })
                    } label: {
                        chip("bell", effReminder.map { Day.label($0) + ", " + Day.time($0) } ?? tr("Erinnerung"), on: effReminder != nil)
                    }
                    Menu {
                        RepeatMenuItems(current: effRule, base: effDue ?? Day.today, set: { value in
                            rule = value
                            if value == nil { disabled.insert(.repeating) }
                            focused = true
                        }, custom: { showCustom = true })
                    } label: {
                        chip("repeat", effRule?.label ?? tr("Wiederholen"), on: effRule != nil)
                    }
                    if parsed.important {
                        chip("star.fill", tr("Wichtig"), on: true)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.card))
    }

    private func chip(_ icon: String, _ label: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(label).lineLimit(1)
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(on ? accent.opacity(0.14) : Color(.systemGray6)))
        .foregroundStyle(on ? accent : Color.secondary)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { focused = false; editing = false; return }
        let p = parsed
        onAdd(p.title, due ?? p.due, reminder ?? p.reminder, rule ?? p.rule, p.important)
        text = ""
        due = nil
        reminder = nil
        rule = nil
        disabled = []
        focused = true
    }
}

// MARK: - Vorschläge für Mein Tag

private struct SuggestionSection: Identifiable {
    let id: String
    let items: [TaskItem]
}

struct SuggestionsSheet: View {
    let accent: Color
    @Query(sort: \TaskItem.created, order: .reverse) private var tasks: [TaskItem]
    @AppStorage(Pref.dueTodayInMyDay) private var dueTodayInMyDay = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    private var sections: [SuggestionSection] {
        let open = tasks.filter { !$0.isCompleted && !$0.isInMyDay(dueTodayCounts: dueTodayInMyDay) }
        var used = Set<PersistentIdentifier>()
        func take(_ test: (TaskItem) -> Bool) -> [TaskItem] {
            let picked = Array(open.filter { !used.contains($0.persistentModelID) && test($0) }.prefix(10))
            for t in picked { used.insert(t.persistentModelID) }
            return picked
        }
        let overdue = take { t in t.due.map { Day.offset($0) < 0 } ?? false }
        let today = take { t in t.due.map { Day.offset($0) == 0 } ?? false }
        let soon = take { t in t.due.map { (1...7).contains(Day.offset($0)) } ?? false }
        let earlier = take { t in t.myDayDate != nil }
        let recent = take { t in t.created > Day.add(-3, to: Day.today) }
        return [
            SuggestionSection(id: tr("Überfällig"), items: overdue),
            SuggestionSection(id: tr("Heute fällig"), items: today),
            SuggestionSection(id: tr("Später"), items: soon),
            SuggestionSection(id: tr("Früher"), items: earlier),
            SuggestionSection(id: tr("Zuletzt hinzugefügt"), items: recent)
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.id) {
                        ForEach(section.items) { task in
                            HStack(spacing: 12) {
                                Button { withAnimation { Store.toggleComplete(task, ctx: ctx) } } label: {
                                    CheckCircle(done: task.isCompleted, accent: accent)
                                }
                                .buttonStyle(.borderless)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                    HStack(spacing: 4) {
                                        Text(task.list?.name ?? tr("Aufgaben"))
                                        if let due = task.due {
                                            Text("•")
                                            Label(Day.label(due), systemImage: "calendar").labelStyle(TightLabel())
                                                .foregroundStyle(Day.offset(due) < 0 ? Color.red : Color.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { withAnimation { Store.setMyDay(task, true) } } label: {
                                    Image(systemName: "plus").font(.title3).foregroundStyle(accent)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(tr("Zu „Mein Tag“ hinzufügen"))
                            }
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView(tr("Keine Vorschläge"),
                                           systemImage: "lightbulb",
                                           description: Text(tr("Überfällige, bald fällige und neue Aufgaben erscheinen hier.")))
                }
            }
            .navigationTitle(tr("Vorschläge"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
        }
    }
}
