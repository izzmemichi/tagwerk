import Foundation
import SwiftData

/// Merkt sich, welche Datensätze lokal geändert wurden und noch zum Server müssen.
/// Liegt in der App Group, damit auch Änderungen aus dem Widget hochgeladen werden.
enum ChangeLog {
    static let tables = ["groups", "lists", "tasks", "steps"]
    private static let key = "sync.dirty"
    private static var defaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    /// Während Serveränderungen eingespielt werden, wird nichts protokolliert (sonst Echo).
    static var applyingRemote = false

    static var pending: Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }

    /// Vor jedem Speichern aufrufen: nimmt neue, geänderte und gelöschte Datensätze auf.
    static func record(_ ctx: ModelContext) {
        guard !applyingRemote else { return }
        let models: [any PersistentModel] = ctx.insertedModelsArray + ctx.changedModelsArray + ctx.deletedModelsArray
        let keys = models.compactMap(entry(for:))
        guard !keys.isEmpty else { return }
        defaults.set(Array(pending.union(keys)), forKey: key)
    }

    static func markAll(_ ctx: ModelContext) {
        var keys = pending
        for g in (try? ctx.fetch(FetchDescriptor<ListGroup>())) ?? [] { keys.insert("groups:" + g.id.uuidString) }
        for l in (try? ctx.fetch(FetchDescriptor<TaskList>())) ?? [] { keys.insert("lists:" + l.id.uuidString) }
        for t in (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [] { keys.insert("tasks:" + t.id.uuidString) }
        for s in (try? ctx.fetch(FetchDescriptor<TaskStep>())) ?? [] { keys.insert("steps:" + s.id.uuidString) }
        defaults.set(Array(keys), forKey: key)
    }

    static func clear(_ done: Set<String>) {
        defaults.set(Array(pending.subtracting(done)), forKey: key)
    }

    static func entry(for model: any PersistentModel) -> String? {
        switch model {
        case let g as ListGroup: return "groups:" + g.id.uuidString
        case let l as TaskList: return "lists:" + l.id.uuidString
        case let t as TaskItem: return "tasks:" + t.id.uuidString
        case let s as TaskStep: return "steps:" + s.id.uuidString
        default: return nil
        }
    }
}
