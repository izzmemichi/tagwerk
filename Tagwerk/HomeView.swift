import SwiftUI
import SwiftData

private enum HomeItem: Identifiable {
    case group(ListGroup)
    case list(TaskList)

    var id: PersistentIdentifier {
        switch self {
        case .group(let g): return g.persistentModelID
        case .list(let l): return l.persistentModelID
        }
    }

    var order: Double {
        switch self {
        case .group(let g): return g.order
        case .list(let l): return l.order
        }
    }

    func setOrder(_ value: Double) {
        switch self {
        case .group(let g): g.order = value
        case .list(let l): l.order = value
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TaskList.order) private var lists: [TaskList]
    @Query(sort: \ListGroup.order) private var groups: [ListGroup]
    @Query private var tasks: [TaskItem]

    @AppStorage(Pref.showImportant) private var showImportant = true
    @AppStorage(Pref.showPlanned) private var showPlanned = true
    @AppStorage(Pref.showAll) private var showAll = true
    @AppStorage(Pref.showCompleted) private var showCompleted = false
    @AppStorage(Pref.autoHideEmpty) private var autoHideEmpty = true
    @AppStorage(Pref.dueTodayInMyDay) private var dueTodayInMyDay = true

    @State private var path = NavigationPath()
    @State private var showNewList = false
    @State private var showNewGroup = false
    @State private var groupName = ""
    @State private var renamingGroup: ListGroup?
    @State private var editingList: TaskList?
    @State private var listToDelete: TaskList?

    private func count(_ s: SmartList) -> Int {
        switch s {
        case .myDay: return tasks.filter { !$0.isCompleted && $0.isInMyDay(dueTodayCounts: dueTodayInMyDay) }.count
        case .important: return tasks.filter { !$0.isCompleted && $0.isImportant }.count
        case .planned: return tasks.filter { !$0.isCompleted && ($0.due != nil || $0.reminder != nil) }.count
        case .all: return tasks.filter { !$0.isCompleted }.count
        case .completed: return tasks.filter(\.isCompleted).count
        case .tasks: return tasks.filter { !$0.isCompleted && $0.list?.isDefault == true }.count
        }
    }

    private var visibleSmart: [SmartList] {
        SmartList.allCases.filter { s in
            switch s {
            case .myDay, .tasks: return true
            case .important: return showImportant && !(autoHideEmpty && count(s) == 0)
            case .planned: return showPlanned && !(autoHideEmpty && count(s) == 0)
            case .all: return showAll && !(autoHideEmpty && count(s) == 0)
            case .completed: return showCompleted && !(autoHideEmpty && count(s) == 0)
            }
        }
    }

    private var topItems: [HomeItem] {
        let looseLists = lists.filter { !$0.isDefault && $0.group == nil }.map(HomeItem.list)
        return (groups.map(HomeItem.group) + looseLists).sorted { $0.order < $1.order }
    }

    private var customLists: [TaskList] { lists.filter { !$0.isDefault } }

    @AppStorage(Pref.profileName) private var profileName = ""
    private let blue = ListTheme.blue.accent

    private var initials: String {
        let parts = profileName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "T" : letters.uppercased()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ForEach(visibleSmart) { s in
                        Button { path.append(Route.smart(s)) } label: {
                            row(icon: Image(systemName: s.icon)
                                    .font(.system(size: 21, weight: .light))
                                    .foregroundStyle(s.iconColor),
                                title: s.title, count: s == .completed ? 0 : count(s))
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                    Divider().padding(.horizontal, 16).padding(.vertical, 12)
                    ForEach(topItems) { item in
                        switch item {
                        case .list(let l): listRow(l, indented: false)
                        case .group(let g): groupBlock(g)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .smart(let s): ListScreen(source: .smart(s))
                case .list(let l): ListScreen(source: .list(l))
                case .search: SearchScreen()
                case .settings: SettingsView()
                }
            }
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "tagwerk" else { return }
            path = NavigationPath()
            if url.host == "myday" { path.append(Route.smart(.myDay)) }
        }
        .sheet(isPresented: $showNewList) {
            ListEditorSheet(title: tr("Neue Liste"), name: "",
                            theme: ListTheme.allCases[customLists.count % 9]) { name, theme in
                let list = Store.newList(name: name, theme: theme, group: newListGroup, ctx: ctx)
                newListGroup = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    path.append(Route.list(list))
                }
            }
        }
        .sheet(item: $editingList) { list in
            ListEditorSheet(title: tr("Liste umbenennen"), name: list.name, theme: list.theme) { name, theme in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { list.name = trimmed }
                list.theme = theme
            }
        }
        .alert(tr("Neue Gruppe"), isPresented: $showNewGroup) {
            TextField(tr("Unbenannte Gruppe"), text: $groupName)
            Button(tr("Abbrechen"), role: .cancel) { groupName = "" }
            Button(tr("Erstellen")) {
                let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                let g = ListGroup(name: trimmed.isEmpty ? tr("Unbenannte Gruppe") : trimmed, order: Store.nextListOrder(ctx))
                ctx.insert(g)
                groupName = ""
            }
        }
        .alert(tr("Gruppe umbenennen"),
               isPresented: Binding(get: { renamingGroup != nil }, set: { if !$0 { renamingGroup = nil } })) {
            TextField(tr("Name"), text: $groupName)
            Button(tr("Abbrechen"), role: .cancel) { renamingGroup = nil }
            Button(tr("Speichern")) {
                let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                if let g = renamingGroup, !trimmed.isEmpty { g.name = trimmed }
                renamingGroup = nil
            }
        }
        .confirmationDialog(tr("„%@“ wird endgültig gelöscht.", listToDelete?.name ?? ""),
                            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
                            titleVisibility: .visible) {
            Button(tr("Liste löschen"), role: .destructive) {
                if let l = listToDelete { withAnimation { Store.delete(l, ctx: ctx) } }
                listToDelete = nil
            }
        } message: {
            Text(tr("Diese Aktion kann nicht rückgängig gemacht werden."))
        }
    }

    @State private var newListGroup: ListGroup?

    private var header: some View {
        HStack(spacing: 14) {
            Button { path.append(Route.settings) } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(ListTheme.lagoon.gradient)
                        Text(initials).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    Text(profileName.isEmpty ? "Tagwerk" : profileName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Einstellungen"))
            Spacer()
            Button { path.append(Route.search) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(blue)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("Suchen"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func row<Icon: View>(icon: Icon, title: String, count: Int) -> some View {
        HStack(spacing: 18) {
            icon.frame(width: 28)
            Text(title)
                .font(.system(size: 19))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)").font(.system(size: 17)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }

    private func listRow(_ list: TaskList, indented: Bool) -> some View {
        let parts = list.name.splitEmoji
        return Button { path.append(Route.list(list)) } label: {
            row(icon: ListIcon(name: list.name, fallback: "list.bullet", color: list.theme.accent),
                title: parts.rest.isEmpty ? list.name : parts.rest,
                count: list.openCount)
        }
        .buttonStyle(RowButtonStyle())
        .contextMenu {
            Button { editingList = list } label: { Label(tr("Liste umbenennen"), systemImage: "pencil") }
            Menu {
                Button { list.group = nil } label: { Label(tr("Keine Gruppe"), systemImage: list.group == nil ? "checkmark" : "tray") }
                ForEach(groups) { g in
                    Button { list.group = g } label: {
                        Label(g.name, systemImage: list.group?.id == g.id ? "checkmark" : "folder")
                    }
                }
            } label: { Label(tr("Liste verschieben in …"), systemImage: "folder") }
            Button { _ = Store.duplicate(list, ctx: ctx) } label: { Label(tr("Liste duplizieren"), systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { listToDelete = list } label: { Label(tr("Liste löschen"), systemImage: "trash") }
        }
    }

    private func groupBlock(_ group: ListGroup) -> some View {
        let members = group.lists.sorted { $0.order < $1.order }
        let parts = group.name.splitEmoji
        return VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                HStack(spacing: 8) {
                    if let emoji = parts.emoji { Text(emoji).font(.system(size: 19)) }
                    Text(parts.rest.isEmpty ? group.name : parts.rest)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Menu {
                    Button { newListGroup = group; showNewList = true } label: { Label(tr("Neue Liste in dieser Gruppe"), systemImage: "plus") }
                    Button { groupName = group.name; renamingGroup = group } label: { Label(tr("Gruppe umbenennen"), systemImage: "pencil") }
                    Button {
                        for l in group.lists { l.group = nil }
                        ctx.delete(group)
                    } label: { Label(tr("Gruppierung aufheben"), systemImage: "folder.badge.minus") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 44)
                }
                Button { withAnimation(.snappy(duration: 0.25)) { group.isExpanded.toggle() } } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(group.isExpanded ? 0 : -90))
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel(group.isExpanded ? tr("Gruppe einklappen") : tr("Gruppe ausklappen"))
            }
            .frame(height: 52)
            .padding(.leading, 18)
            .padding(.trailing, 6)

            if group.isExpanded {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 2)
                        .padding(.leading, 31)
                    VStack(spacing: 0) {
                        ForEach(members) { listRow($0, indented: true) }
                        if members.isEmpty {
                            Text(tr("Halte eine Liste gedrückt und wähle „Liste verschieben in …“."))
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { newListGroup = nil; showNewList = true } label: {
                HStack(spacing: 18) {
                    Image(systemName: "plus").font(.system(size: 24, weight: .light)).frame(width: 28)
                    Text(tr("Neue Liste")).font(.system(size: 19))
                }
                .foregroundStyle(blue)
            }
            Spacer()
            Button { groupName = ""; showNewGroup = true } label: {
                Image(systemName: "rectangle.badge.plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(blue)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("Neue Gruppe"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

/// Zeile mit dezenter Hervorhebung beim Antippen, ohne Pfeil und Trennlinie
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray5) : Color.clear)
    }
}

// MARK: - Suche

struct SearchScreen: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TaskItem.created, order: .reverse) private var tasks: [TaskItem]
    @AppStorage("search.showDone") private var showDone = true
    @State private var query = ""
    @State private var searching = true

    private var results: [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return tasks.filter { t in
            (showDone || !t.isCompleted) && (
                t.title.localizedStandardContains(q)
                || t.note.localizedStandardContains(q)
                || t.steps.contains { $0.title.localizedStandardContains(q) }
            )
        }
    }

    var body: some View {
        List {
            ForEach(results) { task in
                TaskRow(task: task, showList: true, showMyDay: true, accent: task.list?.theme.accent ?? ListTheme.blue.accent) {
                    withAnimation { Store.toggleComplete(task, ctx: ctx) }
                }
                .background(NavigationLink(value: task) { EmptyView() }.opacity(0))
            }
        }
        .listStyle(.plain)
        .overlay {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(tr("Suchen"), systemImage: "magnifyingglass",
                                       description: Text(tr("Durchsucht Titel, Schritte und Notizen aller Listen.")))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("Suchen"))
        .navigationTitle(tr("Suchen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(tr("Erledigte Aufgaben anzeigen"), isOn: $showDone)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @AppStorage(Pref.addToTop) private var addToTop = true
    @AppStorage(Pref.importantToTop) private var importantToTop = true
    @AppStorage(Pref.sound) private var sound = true
    @AppStorage(Pref.confirmDelete) private var confirmDelete = true
    @AppStorage(Pref.showImportant) private var showImportant = true
    @AppStorage(Pref.showPlanned) private var showPlanned = true
    @AppStorage(Pref.showAll) private var showAll = true
    @AppStorage(Pref.showCompleted) private var showCompleted = false
    @AppStorage(Pref.autoHideEmpty) private var autoHideEmpty = true
    @AppStorage(Pref.dueTodayInMyDay) private var dueTodayInMyDay = true
    @AppStorage(Pref.profileName) private var profileName = ""
    @AppStorage(Lang.key, store: Lang.store) private var language = ""

    var body: some View {
        Form {
            Section(tr("Sprache")) {
                Picker(tr("Sprache"), selection: $language) {
                    Text(tr("Systemsprache")).tag("")
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                .onChange(of: language) { _, value in
                    // Auch Systemtexte (Tastatur, Teilen-Menü) folgen ab dem nächsten Start
                    if value.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                    else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
                    SharedStore.reloadWidgets()
                }
            }
            Section(tr("Profil")) {
                TextField(tr("Dein Name"), text: $profileName)
            }
            AccountSection()
            Section(tr("Allgemein")) {
                Toggle(tr("Neue Aufgaben oben hinzufügen"), isOn: $addToTop)
                Toggle(tr("Aufgaben mit Stern nach oben verschieben"), isOn: $importantToTop)
                Toggle(tr("Sound bei Fertigstellung"), isOn: $sound)
                Toggle(tr("Vor dem Löschen bestätigen"), isOn: $confirmDelete)
            }
            Section(tr("Intelligente Listen")) {
                Toggle(tr("Wichtig"), isOn: $showImportant)
                Toggle(tr("Geplant"), isOn: $showPlanned)
                Toggle(tr("Alle"), isOn: $showAll)
                Toggle(tr("Abgeschlossen"), isOn: $showCompleted)
                Toggle(tr("Leere intelligente Listen automatisch ausblenden"), isOn: $autoHideEmpty)
                Toggle(tr("„Heute fällig“-Aufgaben in „Mein Tag“ anzeigen"), isOn: $dueTodayInMyDay)
            }
            Section {
                LabeledContent(tr("Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } footer: {
                Text(tr("Eigenständige App, nicht mit Microsoft verbunden."))
            }
        }
        .navigationTitle(tr("Einstellungen"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
