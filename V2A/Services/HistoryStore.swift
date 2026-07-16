import Foundation

struct Session: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let raw: String
    let cleaned: String
    let providerId: String
    let mode: String?  // "light" / "deep" / "custom1" / "custom2"; nil for legacy records
}

enum HistoryStore {
    private static let storeKey = "v2a.history.v1"
    private static let enabledKey = "v2a.history_enabled.v1"
    static let cap = 20

    static func isEnabled() -> Bool {
        // Default ON; user can turn off in Settings.
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    static func load() -> [Session] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else {
            return []
        }
        return sessions
    }

    static func save(_ sessions: [Session]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    static func append(_ session: Session) {
        var list = load()
        list.insert(session, at: 0)  // newest first
        if list.count > cap {
            list = Array(list.prefix(cap))
        }
        save(list)
    }

    static func remove(id: UUID) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}
