import Foundation

/// `MapPreferences` dạng JSON trong UserDefaults (chỉ trên máy, mất khi gỡ app).
struct UserDefaultsMapPreferencesStore: MapPreferencesStore {
    static let key = "map.preferences"

    let suite: MockDefaultsSuite

    func load() -> MapPreferences? {
        guard let data = suite.open().data(forKey: Self.key) else { return nil }
        // Hỏng định dạng → coi như chưa lưu (về mặc định), không chặn mở bản đồ.
        return try? JSONDecoder().decode(MapPreferences.self, from: data)
    }

    func save(_ preferences: MapPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        suite.open().set(data, forKey: Self.key)
    }

    func clear() {
        suite.open().removeObject(forKey: Self.key)
    }
}

/// Không lưu gì giữa các lần chạy — mặc định cho ViewModel trong test/preview.
final class InMemoryMapPreferencesStore: MapPreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MapPreferences?

    init(_ initial: MapPreferences? = nil) {
        stored = initial
    }

    func load() -> MapPreferences? {
        lock.withLock { stored }
    }

    func save(_ preferences: MapPreferences) {
        lock.withLock { stored = preferences }
    }

    func clear() {
        lock.withLock { stored = nil }
    }
}
