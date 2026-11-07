import Foundation

/// Erkennt Datum, Uhrzeit, Wiederholung und Wichtigkeit in einer Schnelleingabe, auf Deutsch und Englisch.
/// "Zahnarzt morgen 9 Uhr" oder "Dentist tomorrow 9am" -> Titel, fällig morgen, Erinnerung 09:00.
struct QuickParse: Equatable {
    var title: String
    var due: Date?
    var reminder: Date?
    var rule: RepeatRule?
    var important = false

    var hasAny: Bool { due != nil || reminder != nil || rule != nil || important }
}

enum QuickAddParser {
    enum Kind: Hashable { case date, time, repeating, important }

    private static let weekdays: [String: Int] = [
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7,
        "so": 1, "mo": 2, "di": 3, "mi": 4, "do": 5, "fr": 6, "sa": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7
    ]
    private static let longDays = "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|monday|tuesday|wednesday|thursday|friday|saturday|sunday"
    private static let shortDays = "mon|tue|wed|thu|fri|sat|sun|mo|di|mi|do|fr|sa|so"

    static func parse(_ input: String, disabled: Set<Kind> = [], now: Date = Date()) -> QuickParse {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        var working = " " + input + " "
        var result = QuickParse(title: input)
        var time: (h: Int, m: Int)?

        /// Sucht das erste Vorkommen, übergibt die Gruppen und entfernt den Treffer, wenn der Handler zustimmt.
        func take(_ pattern: String, _ handler: ([String]) -> Bool) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            let ns = working as NSString
            guard let match = regex.firstMatch(in: working, range: NSRange(location: 0, length: ns.length)) else { return }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            if handler(groups) {
                working = ns.replacingCharacters(in: match.range, with: " ")
            }
        }

        func nextWeekday(_ wd: Int, includeToday: Bool = true) -> Date {
            let current = cal.component(.weekday, from: today)
            var delta = (wd - current + 7) % 7
            if delta == 0 && !includeToday { delta = 7 }
            return cal.date(byAdding: .day, value: delta, to: today) ?? today
        }

        // Wiederholung
        if !disabled.contains(.repeating) {
            take("\\s(jeden tag|täglich|every day|daily)(?=\\s)") { _ in result.rule = .daily; return true }
            if result.rule == nil {
                take("\\s(werktags|wochentags|an werktagen|every weekday|on weekdays|weekdays)(?=\\s)") { _ in result.rule = .workdays; return true }
            }
            if result.rule == nil {
                take("\\s(?:jede[nrs]?|every)\\s(zweiten\\s|2\\.\\s|other\\s|2nd\\s)?(\(longDays)|\(shortDays))(?=\\s)") { g in
                    guard let wd = weekdays[g[2].lowercased()] else { return false }
                    result.rule = RepeatRule(unit: .week, interval: g[1].isEmpty ? 1 : 2, weekdays: [wd])
                    result.due = result.due ?? nextWeekday(wd)
                    return true
                }
            }
            if result.rule == nil {
                take("\\s(?:alle|every)\\s(\\d{1,2})\\s(tage|wochen|monate|jahre|days|weeks|months|years)(?=\\s)") { g in
                    guard let n = Int(g[1]), n > 0 else { return false }
                    let units: [String: RepeatRule.Unit] = ["tage": .day, "wochen": .week, "monate": .month, "jahre": .year,
                                                         "days": .day, "weeks": .week, "months": .month, "years": .year]
                    let unit = units[g[2].lowercased()] ?? .day
                    result.rule = RepeatRule(unit: unit, interval: n, weekdays: [])
                    return true
                }
            }
            if result.rule == nil {
                take("\\s(wöchentlich|jede woche|weekly|every week)(?=\\s)") { _ in result.rule = RepeatRule(unit: .week); return true }
            }
            if result.rule == nil {
                take("\\s(monatlich|jeden monat|monthly|every month)(?=\\s)") { _ in result.rule = .monthly; return true }
            }
            if result.rule == nil {
                take("\\s(jährlich|jedes jahr|yearly|annually|every year)(?=\\s)") { _ in result.rule = .yearly; return true }
            }
        }

        // Datum
        if !disabled.contains(.date) && result.due == nil {
            take("\\s(übermorgen|the day after tomorrow|day after tomorrow)(?=\\s)") { _ in result.due = cal.date(byAdding: .day, value: 2, to: today); return true }
            if result.due == nil {
                take("\\s(morgen|tomorrow)(?=\\s)") { _ in result.due = cal.date(byAdding: .day, value: 1, to: today); return true }
            }
            if result.due == nil {
                take("\\s(heute|today)(?=\\s)") { _ in result.due = today; return true }
            }
            if result.due == nil {
                take("\\s(nächste woche|next week)(?=\\s)") { _ in result.due = nextWeekday(2, includeToday: false); return true }
            }
            if result.due == nil {
                take("\\sin\\s(\\d{1,3})\\s(tag|tagen|woche|wochen|day|days|week|weeks)(?=\\s)") { g in
                    guard let n = Int(g[1]) else { return false }
                    let days = g[2].lowercased().hasPrefix("w") ? n * 7 : n
                    result.due = cal.date(byAdding: .day, value: days, to: today)
                    return true
                }
            }
            if result.due == nil {
                take("\\s(?:am\\s|bis\\s)?(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2,4})?(?=\\s)") { g in
                    guard let d = Int(g[1]), let m = Int(g[2]), (1...31).contains(d), (1...12).contains(m) else { return false }
                    var year = cal.component(.year, from: today)
                    if let y = Int(g[3]) { year = y < 100 ? 2000 + y : y }
                    guard var date = cal.date(from: DateComponents(year: year, month: m, day: d)) else { return false }
                    if g[3].isEmpty, date < today, let next = cal.date(byAdding: .year, value: 1, to: date) { date = next }
                    result.due = date
                    return true
                }
            }
            if result.due == nil {
                take("\\s(?:am\\s|bis\\s|on\\s|by\\s)?(\(longDays))(?=\\s)") { g in
                    guard let wd = weekdays[g[1].lowercased()] else { return false }
                    result.due = nextWeekday(wd)
                    return true
                }
            }
            if result.due == nil {
                // Kurzformen nur mit "am"/"bis", damit "so" oder "do" im Satz nicht verschluckt werden
                take("\\s(?:am|bis|on|by)\\s(\(shortDays))\\.?(?=\\s)") { g in
                    guard let wd = weekdays[g[1].lowercased()] else { return false }
                    result.due = nextWeekday(wd)
                    return true
                }
            }
        }

        // Uhrzeit
        if !disabled.contains(.time) {
            take("\\s(?:at\\s)?(\\d{1,2})(?::(\\d{2}))?\\s?(am|pm)(?=\\s)") { g in
                guard var h = Int(g[1]), h >= 1, h <= 12 else { return false }
                let pm = g[3].lowercased() == "pm"
                if h == 12 { h = pm ? 12 : 0 } else if pm { h += 12 }
                time = (h, Int(g[2]) ?? 0)
                return true
            }
            if time == nil {
                take("\\sat\\s(\\d{1,2})(?::(\\d{2}))?(?=\\s)") { g in
                    guard let h = Int(g[1]), h < 24 else { return false }
                    time = (h, Int(g[2]) ?? 0)
                    return true
                }
            }
            if time == nil { take("\\s(?:um\\s|ab\\s|gegen\\s)?(\\d{1,2})(?::(\\d{2}))?\\s?uhr(?=\\s)") { g in
                guard let h = Int(g[1]), h < 24 else { return false }
                time = (h, Int(g[2]) ?? 0)
                return true
            } }
            if time == nil {
                take("\\s(?:um\\s)?(\\d{1,2}):(\\d{2})(?=\\s)") { g in
                    guard let h = Int(g[1]), let m = Int(g[2]), h < 24, m < 60 else { return false }
                    time = (h, m)
                    return true
                }
            }
            if time == nil {
                take("\\s(morgens|früh|in the morning|morning)(?=\\s)") { _ in time = (9, 0); return true }
            }
            if time == nil {
                take("\\s(mittags|at noon|noon)(?=\\s)") { _ in time = (12, 0); return true }
            }
            if time == nil {
                take("\\s(abends|in the evening|evening|tonight)(?=\\s)") { _ in time = (19, 0); return true }
            }
        }

        // Wichtig
        if !disabled.contains(.important) {
            take("\\s(!+|wichtig|important)(?=\\s)") { _ in result.important = true; return true }
        }

        // Erinnerung aus Uhrzeit ableiten
        if let time {
            var day = result.due ?? today
            var at = cal.date(bySettingHour: time.h, minute: time.m, second: 0, of: day) ?? day
            if result.due == nil && at <= now {
                day = cal.date(byAdding: .day, value: 1, to: today) ?? today
                at = cal.date(bySettingHour: time.h, minute: time.m, second: 0, of: day) ?? day
            }
            result.reminder = at
            result.due = result.due ?? cal.startOfDay(for: day)
        }

        if let rule = result.rule, result.due == nil {
            result.due = rule.unit == .week && !rule.weekdays.isEmpty ? nextWeekday(rule.weekdays[0]) : today
        }
        if let rule = result.rule, rule.unit == .week, rule.weekdays.isEmpty, let due = result.due {
            result.rule = .weekly(from: due)
        }
        // Feste Wochentage: Fälligkeit auf den nächsten passenden Tag legen (z. B. werktags am Samstag -> Montag)
        if let rule = result.rule, rule.unit == .week, let due = result.due {
            var shift = 0
            while shift < 7, let d = cal.date(byAdding: .day, value: shift, to: due),
                  !rule.weekdays.contains(cal.component(.weekday, from: d)) { shift += 1 }
            if shift > 0 && shift < 7 {
                result.due = cal.date(byAdding: .day, value: shift, to: due)
                result.reminder = result.reminder.flatMap { cal.date(byAdding: .day, value: shift, to: $0) }
            }
        }

        let cleaned = working
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–"))
        result.title = cleaned.isEmpty ? input.trimmingCharacters(in: .whitespaces) : cleaned
        return result
    }
}
