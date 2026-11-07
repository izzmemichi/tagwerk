import SwiftUI

// MARK: - Menüinhalte für Fälligkeit, Erinnerung, Wiederholung

struct DueMenuItems: View {
    let hasValue: Bool
    let set: (Date?) -> Void
    let pick: () -> Void

    var body: some View {
        Button { set(Day.today) } label: {
            Label(tr("Heute (%@)", Day.weekdayShort(Day.today)), systemImage: "calendar")
        }
        Button { set(Day.tomorrow) } label: {
            Label(tr("Morgen (%@)", Day.weekdayShort(Day.tomorrow)), systemImage: "arrow.right.circle")
        }
        Button { set(Day.nextMonday) } label: {
            Label(tr("Nächste Woche (%@)", Day.weekdayShort(Day.nextMonday)), systemImage: "forward.circle")
        }
        Divider()
        Button { pick() } label: { Label(tr("Datum auswählen"), systemImage: "calendar.badge.plus") }
        if hasValue {
            Divider()
            Button(role: .destructive) { set(nil) } label: {
                Label(tr("Fälligkeitsdatum entfernen"), systemImage: "trash")
            }
        }
    }
}

struct ReminderMenuItems: View {
    let hasValue: Bool
    let set: (Date?) -> Void
    let pick: () -> Void

    var body: some View {
        if let later = Day.laterToday {
            Button { set(later) } label: {
                Label(tr("Später am Tag (%@)", Day.time(later)), systemImage: "clock.arrow.circlepath")
            }
        }
        let tomorrow = Day.at(Day.tomorrow, hour: 9)
        Button { set(tomorrow) } label: {
            Label(tr("Morgen (%@, 09:00)", Day.weekdayShort(tomorrow)), systemImage: "arrow.right.circle")
        }
        let nextWeek = Day.at(Day.nextMonday, hour: 9)
        Button { set(nextWeek) } label: {
            Label(tr("Nächste Woche (%@, 09:00)", Day.weekdayShort(nextWeek)), systemImage: "forward.circle")
        }
        Divider()
        Button { pick() } label: { Label(tr("Datum und Uhrzeit auswählen"), systemImage: "calendar.badge.clock") }
        if hasValue {
            Divider()
            Button(role: .destructive) { set(nil) } label: { Label(tr("Erinnerung entfernen"), systemImage: "trash") }
        }
    }
}

struct RepeatMenuItems: View {
    let current: RepeatRule?
    let base: Date
    let set: (RepeatRule?) -> Void
    let custom: () -> Void

    var body: some View {
        Button { set(.daily) } label: { Label(tr("Täglich"), systemImage: "sun.max") }
        Button { set(.workdays) } label: { Label(tr("Wochentage"), systemImage: "briefcase") }
        Button { set(.weekly(from: base)) } label: { Label(tr("Wöchentlich"), systemImage: "calendar") }
        Button { set(.monthly) } label: { Label(tr("Monatlich"), systemImage: "calendar.circle") }
        Button { set(.yearly) } label: { Label(tr("Jährlich"), systemImage: "gift") }
        Divider()
        Button { custom() } label: { Label(tr("Benutzerdefiniert"), systemImage: "slider.horizontal.3") }
        if current != nil {
            Divider()
            Button(role: .destructive) { set(nil) } label: { Label(tr("Nicht wiederholen"), systemImage: "trash") }
        }
    }
}

// MARK: - Auswahlblätter

struct DatePickSheet: View {
    let title: String
    let withTime: Bool
    @State var date: Date
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(title, selection: $date,
                           displayedComponents: withTime ? [.date, .hourAndMinute] : [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Day.locale)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Speichern")) { onSave(withTime ? date : Day.start(date)); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct RepeatCustomSheet: View {
    @State var rule: RepeatRule
    let accent: Color
    let onSave: (RepeatRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Wiederholen alle")) {
                    Stepper(value: $rule.interval, in: 1...99) {
                        Text("\(rule.interval)").monospacedDigit()
                    }
                    Picker(tr("Einheit"), selection: $rule.unit) {
                        ForEach(RepeatRule.Unit.allCases) { unit in
                            Text(unit.label(rule.interval)).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if rule.unit == .week {
                    Section(tr("An diesen Tagen")) {
                        HStack(spacing: 6) {
                            ForEach(RepeatRule.weekdayOrder, id: \.self) { wd in
                                let on = rule.weekdays.contains(wd)
                                Button {
                                    if on { rule.weekdays.removeAll { $0 == wd } } else { rule.weekdays.append(wd) }
                                } label: {
                                    Text(RepeatRule.weekdayShort[wd] ?? "")
                                        .font(.subheadline.weight(.medium))
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(on ? accent : Color.secondary.opacity(0.15)))
                                        .foregroundStyle(on ? .white : .primary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Section {
                    Text(rule.label).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Benutzerdefiniert"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fertig")) { onSave(rule); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(rule.unit == .week && rule.weekdays.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ThemePickerSheet: View {
    @Binding var theme: ListTheme
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ListTheme.allCases) { t in
                        Button { theme = t } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(t.gradient)
                                    .frame(height: 56)
                                    .overlay {
                                        if t == theme {
                                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                        }
                                    }
                                Text(t.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(tr("Design ändern"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Name und Design einer Liste, für "Neue Liste" und "Liste umbenennen"
struct ListEditorSheet: View {
    let title: String
    @State var name: String
    @State var theme: ListTheme
    let onSave: (String, ListTheme) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Unbenannte Liste"), text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text(tr("Beginnt der Name mit einem Emoji, wird es als Symbol der Liste verwendet."))
                }
                Section(tr("Design")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                        ForEach(ListTheme.allCases) { t in
                            Circle()
                                .fill(t.gradient)
                                .frame(width: 34, height: 34)
                                .overlay { if t == theme { Circle().stroke(Color.primary, lineWidth: 2).padding(-4) } }
                                .onTapGesture { theme = t }
                                .accessibilityLabel(t.name)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig"), action: save).fontWeight(.semibold) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        onSave(name, theme)
        dismiss()
    }
}
