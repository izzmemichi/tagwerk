import SwiftUI
import SwiftData
import Security

// MARK: - Verbindung

enum SupabaseConfig {
    /// Aus Config.xcconfig (SUPABASE_HOST, SUPABASE_ANON_KEY). Der Schlüssel ist öffentlich, die Daten schützt der Zeilenschutz.
    static let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "") ?? URL(string: "https://invalid.local")!
    static let publishableKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseKey") as? String ?? ""
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
}

enum SessionStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "tagwerk") + ".session"

    static func load() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum SyncError: LocalizedError {
    case server(String)
    case confirmEmail

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .confirmEmail: return tr("Bitte bestätige zuerst deine E-Mail-Adresse über den Link in der Mail, dann anmelden.")
        }
    }
}

// MARK: - Zeitstempel

enum ISO {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func string(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return withFraction.string(from: date)
    }

    /// Optionaler Text als JSON-Wert (null statt fehlend)
    static func text(_ value: String?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    /// Postgres liefert bis zu 6 Nachkommastellen, der Formatter versteht 3
    static func date(_ value: Any?) -> Date? {
        guard var s = value as? String else { return nil }
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = s[s.index(after: dot)..<end]
            let ms = String((digits + "000").prefix(3))
            s.replaceSubrange(s.index(after: dot)..<end, with: ms)
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - Konto in den Einstellungen

struct AccountSection: View {
    @State private var sync = Sync.shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Section {
            if sync.isSignedIn {
                LabeledContent(tr("Konto"), value: sync.email ?? "")
                LabeledContent(tr("Status")) {
                    HStack(spacing: 6) {
                        Circle().fill(sync.liveSince != nil ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(sync.liveSince != nil ? tr("Verbunden") : tr("Offline"))
                    }
                }
                Button(tr("Abmelden"), role: .destructive) { sync.signOut() }
            } else {
                TextField(tr("E-Mail"), text: $email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(tr("Passwort"), text: $password).textContentType(.password)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button(tr("Anmelden")) { submit(signUp: false) }.disabled(busy || email.isEmpty || password.isEmpty)
                Button(tr("Konto erstellen")) { submit(signUp: true) }.disabled(busy || email.isEmpty || password.isEmpty)
            }
        } header: {
            Text(tr("Abgleich mit der Web-App"))
        } footer: {
            if sync.isSignedIn, sync.liveSince == nil, let error = sync.lastError {
                Text(error)
            } else {
                Text(tr("Änderungen erscheinen sofort auf allen Geräten. Anhänge bleiben auf dem iPhone."))
            }
        }
    }

    private func submit(signUp: Bool) {
        busy = true
        message = nil
        Task {
            do {
                if signUp {
                    try await sync.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password)
                } else {
                    try await sync.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                }
                password = ""
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Abgleich

@MainActor
@Observable
final class Sync {
    static let shared = Sync()

    private(set) var email: String?
    private(set) var isRunning = false
    private(set) var lastError: String?

    /// Liefert den aktuellen Datenbank-Kontext der App (er wird nach Widget-Änderungen neu geladen)
    var context: (() -> ModelContext)?

    private var session: AuthSession?
    private var soon: Task<Void, Never>?
    private let cursorKey = "sync.cursor."
    private let pageSize = 1000

    private init() {
        session = SessionStore.load()
        email = session?.email
    }

    var isSignedIn: Bool { session != nil }

    // MARK: Anmeldung

    func signIn(email: String, password: String) async throws {
        let body = ["email": email, "password": password]
        let json = try await auth("token?grant_type=password", body: body)
        try adopt(json, email: email)
        if let ctx = context?() { ChangeLog.markAll(ctx) }
        await run()
        await connectLive()
    }

    func signUp(email: String, password: String) async throws {
        let json = try await auth("signup", body: ["email": email, "password": password])
        if json["access_token"] != nil {
            try adopt(json, email: email)
            if let ctx = context?() { ChangeLog.markAll(ctx) }
            await run()
            await connectLive()
        } else {
            throw SyncError.confirmEmail
        }
    }

    func signOut() {
        disconnectLive()
        session = nil
        email = nil
        SessionStore.save(nil)
        for table in ChangeLog.tables { UserDefaults.standard.removeObject(forKey: cursorKey + table) }
    }

    private func adopt(_ json: [String: Any], email: String) throws {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw SyncError.server(tr("Anmeldung fehlgeschlagen"))
        }
        let expires = (json["expires_in"] as? Double) ?? 3600
        let mail = ((json["user"] as? [String: Any])?["email"] as? String) ?? email
        session = AuthSession(accessToken: access, refreshToken: refresh,
                              expiresAt: Date().addingTimeInterval(expires - 60), email: mail)
        self.email = mail
        SessionStore.save(session)
        // Neuen Schlüssel auch der Live-Verbindung geben
        if socket != nil { sendLive(event: "access_token", payload: ["access_token": access], topic: topic) }
    }

    private func validToken() async throws -> String {
        guard var s = session else { throw SyncError.server(tr("Nicht angemeldet")) }
        if s.expiresAt > Date() { return s.accessToken }
        let json = try await auth("token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
        try adopt(json, email: s.email)
        s = session!
        return s.accessToken
    }

    private func auth(_ path: String, body: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "/auth/v1/" + path, relativeTo: SupabaseConfig.url)!)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (json["msg"] ?? json["error_description"] ?? json["message"]) as? String
            throw SyncError.server(Self.german(message))
        }
        return json
    }

    private static func german(_ message: String?) -> String {
        switch message ?? "" {
        case let m where m.contains("Invalid login"): return tr("E-Mail oder Passwort falsch.")
        case let m where m.contains("not confirmed"): return SyncError.confirmEmail.errorDescription!
        case let m where m.contains("already registered"): return tr("Diese E-Mail ist schon registriert. Bitte anmelden.")
        case let m where m.contains("at least"): return tr("Das Passwort ist zu kurz (mindestens 6 Zeichen).")
        case "": return tr("Server nicht erreichbar.")
        default: return message!
        }
    }

    // MARK: Ablauf

    /// Kurz nach einer Änderung abgleichen (schnell aufeinanderfolgende Änderungen werden gebündelt)
    /// Ein laufender Abgleich wird nie abgebrochen: Kommt währenddessen etwas Neues, läuft danach einfach noch ein Durchgang.
    func scheduleSoon() {
        guard isSignedIn, soon == nil else { return }
        soon = Task {
            try? await Task.sleep(for: .milliseconds(300))
            soon = nil
            await run()
        }
    }

    /// iOS speichert Änderungen nur gelegentlich. Jede Sekunde aufgerufen: ungespeicherte Änderungen sofort sichern,
    /// das löst über das Änderungsprotokoll den Upload aus.
    func flushLocal() {
        guard let ctx = context?(), ctx.hasChanges else { return }
        commit(ctx)
        scheduleSoon()
    }

    /// Speichert und merkt die Änderungen fürs Hochladen vor. Alle Speicherungen der App laufen hierüber,
    /// automatisches Speichern ist aus, damit keine Änderung am Protokoll vorbeigeht.
    func commit(_ ctx: ModelContext) {
        guard ctx.hasChanges else { return }
        ChangeLog.record(ctx)
        try? ctx.save()
    }

    private var rerun = false

    func run() async {
        guard isSignedIn, let ctx = context?() else { return }
        if isRunning { rerun = true; return }
        isRunning = true
        defer { isRunning = false }
        repeat {
            rerun = false
            do {
                commit(ctx)
                try await push(ctx)
                try await pull(ctx)
                lastError = nil
                SharedStore.reloadWidgets()
            } catch {
                // Kein Netz oder abgebrochene Anfrage ist kein Fehler zum Anzeigen; der nächste Durchgang holt es nach
                if (error as? URLError)?.code != .cancelled { lastError = error.localizedDescription }
                rerun = false
            }
        } while rerun
    }

    // MARK: Live-Verbindung (Supabase Realtime)
    // Solange die App offen ist, meldet der Server jede Änderung sofort. Dann wird abgeglichen.

    private var socket: URLSessionWebSocketTask?
    private(set) var liveSince: Date?
    var isLive: Bool { socket != nil }
    private var heartbeat: Task<Void, Never>?
    private var messageRef = 0
    private let topic = "realtime:tagwerk"

    func connectLive() async {
        guard isSignedIn, socket == nil, let token = try? await validToken() else { return }
        var comps = URLComponents(url: SupabaseConfig.url, resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.path = "/realtime/v1/websocket"
        comps.queryItems = [URLQueryItem(name: "apikey", value: SupabaseConfig.publishableKey),
                            URLQueryItem(name: "vsn", value: "1.0.0")]
        guard let url = comps.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        let changes: [[String: Any]] = ChangeLog.tables.map { ["event": "*", "schema": "public", "table": $0] }
        let join: [String: Any] = ["config": ["postgres_changes": changes], "access_token": token]
        sendLive(event: "phx_join", payload: join, topic: topic)
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                self?.sendLive(event: "heartbeat", payload: [:], topic: "phoenix")
            }
        }
        listen(task)
    }

    func disconnectLive() {
        liveSince = nil
        heartbeat?.cancel()
        heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func sendLive(event: String, payload: [String: Any], topic: String) {
        messageRef = event == "phx_join" ? 1 : messageRef + 1
        let message: [String: Any] = ["topic": topic, "event": event, "payload": payload,
                                      "ref": String(messageRef), "join_ref": "1"]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while let self, self.socket === task {
                do {
                    let message = try await task.receive()
                    guard case .string(let text) = message,
                          let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { continue }
                    let event = json["event"] as? String
                    let payload = json["payload"] as? [String: Any]
                    if event == "phx_reply", json["topic"] as? String == self.topic, (json["ref"] as? String) == "1" || self.liveSince == nil {
                        if payload?["status"] as? String == "ok" { self.liveSince = Date() } else {
                            self.lastError = tr("Live-Verbindung abgelehnt: %@", (payload?["response"] as? [String: Any])?["reason"] as? String ?? tr("unbekannt"))
                        }
                    }
                    if event == "postgres_changes" { self.scheduleSoon() }
                } catch {
                    // Verbindung weg: kurz warten und neu verbinden, solange die App offen ist
                    guard self.socket === task else { return }
                    self.disconnectLive()
                    try? await Task.sleep(for: .seconds(3))
                    if UIApplication.shared.applicationState == .active { await self.connectLive() }
                    return
                }
            }
        }
    }

    // MARK: Hochladen

    private func push(_ ctx: ModelContext) async throws {
        let snapshot = ChangeLog.pending
        guard !snapshot.isEmpty else { return }
        var ids: [String: [UUID]] = [:]
        for entry in snapshot {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { continue }
            ids[parts[0], default: []].append(id)
        }
        for table in ChangeLog.tables {
            guard let wanted = ids[table], !wanted.isEmpty else { continue }
            let wantedSet = Set(wanted)
            let current: [[String: Any]] = encode(table, ids: wantedSet, ctx: ctx)
            let present = Set(current.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) })
            let tombstones: [[String: Any]] = wantedSet.subtracting(present).map { (id: UUID) -> [String: Any] in
                ["id": id.uuidString, "deleted": true]
            }
            if !current.isEmpty { try await upsert(table, current) }
            if !tombstones.isEmpty { try await upsert(table, tombstones) }
        }
        ChangeLog.clear(snapshot)
    }

    private func encode(_ table: String, ids: Set<UUID>, ctx: ModelContext) -> [[String: Any]] {
        var out: [[String: Any]] = []
        switch table {
        case "groups":
            for g in (try? ctx.fetch(FetchDescriptor<ListGroup>())) ?? [] where ids.contains(g.id) {
                var r: [String: Any] = [:]
                r["id"] = g.id.uuidString
                r["name"] = g.name
                r["sort"] = g.order
                r["is_expanded"] = g.isExpanded
                r["deleted"] = false
                out.append(r)
            }
        case "lists":
            for l in (try? ctx.fetch(FetchDescriptor<TaskList>())) ?? [] where ids.contains(l.id) {
                var r: [String: Any] = [:]
                r["id"] = l.id.uuidString
                r["name"] = l.name
                r["theme"] = l.themeRaw
                r["sort"] = l.order
                r["is_default"] = l.isDefault
                r["group_id"] = ISO.text(l.group?.id.uuidString)
                r["created_at"] = ISO.string(l.created)
                r["deleted"] = false
                out.append(r)
            }
        case "tasks":
            for t in (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [] where ids.contains(t.id) {
                var r: [String: Any] = [:]
                r["id"] = t.id.uuidString
                r["list_id"] = ISO.text(t.list?.id.uuidString)
                r["title"] = t.title
                r["note"] = t.note
                r["is_completed"] = t.isCompleted
                r["completed_at"] = ISO.string(t.completedAt)
                r["is_important"] = t.isImportant
                r["my_day_date"] = ISO.string(t.myDayDate)
                r["my_day_added_at"] = ISO.string(t.myDayAddedAt)
                r["due"] = ISO.string(t.due)
                r["reminder"] = ISO.string(t.reminder)
                r["repeat_raw"] = ISO.text(t.repeatRaw)
                r["spawned_next"] = t.spawnedNext
                r["created_at"] = ISO.string(t.created)
                r["sort"] = t.order
                r["deleted"] = false
                out.append(r)
            }
        case "steps":
            for s in (try? ctx.fetch(FetchDescriptor<TaskStep>())) ?? [] where ids.contains(s.id) {
                var r: [String: Any] = [:]
                r["id"] = s.id.uuidString
                r["task_id"] = ISO.text(s.task?.id.uuidString)
                r["title"] = s.title
                r["is_completed"] = s.isCompleted
                r["sort"] = s.order
                r["deleted"] = false
                out.append(r)
            }
        default:
            break
        }
        return out
    }

    private func upsert(_ table: String, _ rows: [[String: Any]]) async throws {
        for start in stride(from: 0, to: rows.count, by: 500) {
            let chunk = Array(rows[start..<min(start + 500, rows.count)])
            var req = try await request("/rest/v1/" + table)
            req.httpMethod = "POST"
            req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: chunk)
            try await send(req)
        }
    }

    // MARK: Herunterladen

    private func pull(_ ctx: ModelContext) async throws {
        for table in ChangeLog.tables {
            var page = 0
            while page < 50 {
                page += 1
                let stored = UserDefaults.standard.object(forKey: cursorKey + table) as? Date
                var path = "/rest/v1/\(table)?select=*&order=updated_at.asc&limit=\(pageSize)"
                if let stored, let iso = ISO.string(stored.addingTimeInterval(-10)) as? String {
                    path += "&updated_at=gt." + (iso.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? iso)
                }
                let data = try await send(try await request(path))
                let rows: [[String: Any]] = ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
                apply(table, rows, ctx: ctx)
                let newest: Date? = rows.compactMap { ISO.date($0["updated_at"]) }.max()
                guard let newest, newest > (stored ?? .distantPast) else { break }
                UserDefaults.standard.set(newest, forKey: cursorKey + table)
                if rows.count < pageSize { break }
            }
        }
    }

    private struct Row {
        let r: [String: Any]
        func str(_ k: String) -> String { r[k] as? String ?? "" }
        func num(_ k: String) -> Double { (r[k] as? NSNumber)?.doubleValue ?? 0 }
        func flag(_ k: String) -> Bool { r[k] as? Bool ?? false }
        func date(_ k: String) -> Date? { ISO.date(r[k]) }
        func ref(_ k: String) -> UUID? { (r[k] as? String).flatMap { UUID(uuidString: $0) } }
        func text(_ k: String) -> String? { r[k] as? String }
    }

    private func byID<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext, _ key: (T) -> UUID) -> [UUID: T] {
        var out: [UUID: T] = [:]
        for model in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { out[key(model)] = model }
        return out
    }

    private func apply(_ table: String, _ rows: [[String: Any]], ctx: ModelContext) {
        guard !rows.isEmpty else { return }
        // Gerade bearbeitete Datensätze zuerst normal sichern: Sie landen im Änderungsprotokoll,
        // werden unten übersprungen und beim nächsten Durchlauf hochgeladen
        commit(ctx)
        let pending = ChangeLog.pending
        ChangeLog.applyingRemote = true
        defer {
            try? ctx.save()
            ChangeLog.applyingRemote = false
        }
        let groups = byID(ListGroup.self, ctx) { $0.id }
        let lists = byID(TaskList.self, ctx) { $0.id }
        var tasks = byID(TaskItem.self, ctx) { $0.id }
        var steps = byID(TaskStep.self, ctx) { $0.id }
        var newGroups = groups
        var newLists = lists

        for raw in rows {
            let row = Row(r: raw)
            guard let id = row.ref("id") else { continue }
            // Noch nicht hochgeladene lokale Änderung gewinnt
            if pending.contains(table + ":" + id.uuidString) { continue }
            let deleted = row.flag("deleted")

            switch table {
            case "groups":
                if deleted {
                    if let g = newGroups[id] { ctx.delete(g) }
                    continue
                }
                let g: ListGroup
                if let existing = newGroups[id] { g = existing } else {
                    g = ListGroup(name: "", order: 0)
                    g.id = id
                    ctx.insert(g)
                    newGroups[id] = g
                }
                g.name = row.str("name")
                g.order = row.num("sort")
                g.isExpanded = row.flag("is_expanded")
            case "lists":
                if deleted {
                    if let l = newLists[id] { ctx.delete(l) }
                    continue
                }
                let l: TaskList
                if let existing = newLists[id] { l = existing } else {
                    l = TaskList(name: "", theme: .blue, order: 0)
                    l.id = id
                    ctx.insert(l)
                    newLists[id] = l
                }
                l.name = row.str("name")
                l.themeRaw = row.str("theme")
                l.order = row.num("sort")
                l.isDefault = row.flag("is_default")
                l.created = row.date("created_at") ?? l.created
                if let gid = row.ref("group_id") { l.group = newGroups[gid] } else { l.group = nil }
            case "tasks":
                if deleted {
                    if let t = tasks[id] {
                        Reminders.cancel(t)
                        ctx.delete(t)
                    }
                    continue
                }
                let t: TaskItem
                if let existing = tasks[id] { t = existing } else {
                    t = TaskItem(title: "", order: 0)
                    t.id = id
                    ctx.insert(t)
                    tasks[id] = t
                }
                t.title = row.str("title")
                t.note = row.str("note")
                t.isCompleted = row.flag("is_completed")
                t.completedAt = row.date("completed_at")
                t.isImportant = row.flag("is_important")
                t.myDayDate = row.date("my_day_date")
                t.myDayAddedAt = row.date("my_day_added_at")
                t.due = row.date("due")
                t.reminder = row.date("reminder")
                t.repeatRaw = row.text("repeat_raw")
                t.spawnedNext = row.flag("spawned_next")
                t.created = row.date("created_at") ?? t.created
                t.order = row.num("sort")
                if let lid = row.ref("list_id"), let list = newLists[lid] { t.list = list }
                Reminders.schedule(t)
            case "steps":
                if deleted {
                    if let s = steps[id] { ctx.delete(s) }
                    continue
                }
                let s: TaskStep
                if let existing = steps[id] { s = existing } else {
                    s = TaskStep(title: "", order: 0)
                    s.id = id
                    ctx.insert(s)
                    steps[id] = s
                }
                s.title = row.str("title")
                s.isCompleted = row.flag("is_completed")
                s.order = row.num("sort")
                if let tid = row.ref("task_id"), let task = tasks[tid] { s.task = task }
            default:
                break
            }
        }
    }

    // MARK: HTTP

    private func request(_ path: String) async throws -> URLRequest {
        let token = try await validToken()
        var req = URLRequest(url: URL(string: SupabaseConfig.url.absoluteString + path)!)
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.server(tr("Keine Antwort")) }
        if http.statusCode == 401 { signOut(); throw SyncError.server(tr("Sitzung abgelaufen, bitte neu anmelden.")) }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw SyncError.server((json?["message"] as? String) ?? tr("Serverfehler %lld", http.statusCode))
        }
        return data
    }
}
