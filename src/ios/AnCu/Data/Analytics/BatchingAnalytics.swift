import Foundation

/// Nơi nhận lô sự kiện (Supabase RPC `track_events`; sau này .NET endpoint).
protocol AnalyticsSink: Sendable {
    func send(_ events: [AnalyticsEvent], installID: UUID) async throws
}

/// Gom sự kiện theo lô: gửi khi đủ `batchSize`, khi `flush()` (app vào nền) hoặc sau `interval`.
/// Người dùng tắt "Chia sẻ dữ liệu sử dụng" → bỏ qua mọi sự kiện và xóa bộ đệm.
actor BatchingAnalytics: AnalyticsTracker {
    static let enabledKey = "analytics.enabled"
    static let installIDKey = "analytics.installID"
    /// Khớp giới hạn 50/lô của RPC.
    static let batchSize = 20
    static let maxBuffered = 200

    private let sink: any AnalyticsSink
    private let defaults: UserDefaults
    private let interval: Duration
    private var buffer: [AnalyticsEvent] = []
    private var timer: Task<Void, Never>?
    private var isSending = false

    init(sink: any AnalyticsSink, suite: MockDefaultsSuite = .standard, interval: Duration = .seconds(30)) {
        self.sink = sink
        self.defaults = suite.open()
        self.interval = interval
    }

    /// Ngẫu nhiên, sinh một lần mỗi lần cài; không gắn với tài khoản.
    var installID: UUID {
        if let raw = defaults.string(forKey: Self.installIDKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.installIDKey)
        return id
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var bufferedCount: Int { buffer.count }

    nonisolated func track(_ event: AnalyticsEvent) {
        Task { await enqueue(event) }
    }

    func enqueue(_ event: AnalyticsEvent) async {
        guard isEnabled else {
            buffer.removeAll()
            return
        }
        buffer.append(event)
        if buffer.count > Self.maxBuffered { buffer.removeFirst(buffer.count - Self.maxBuffered) }
        if buffer.count >= Self.batchSize {
            await flush()
        } else if timer == nil {
            timer = Task { [interval] in
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self.flush()
            }
        }
    }

    func flush() async {
        timer?.cancel()
        timer = nil
        guard isEnabled else {
            buffer.removeAll()
            return
        }
        guard !isSending, !buffer.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        let batch = Array(buffer.prefix(Self.batchSize))
        do {
            try await sink.send(batch, installID: installID)
            buffer.removeFirst(min(batch.count, buffer.count))
        } catch RepositoryError.decoding {
            buffer.removeFirst(min(batch.count, buffer.count))   // lô bị server từ chối → bỏ, đừng gửi lại mãi
        } catch {
            return   // lỗi mạng: giữ lại, lần sau gửi
        }
        if !buffer.isEmpty { await flush() }
    }
}

struct SupabaseAnalyticsSink: AnalyticsSink {
    let rpc: any RPCClient

    private struct Params: Encodable, Sendable {
        struct Event: Encodable, Sendable {
            let name: String
            let props: [String: String]
            let occurredAt: String
            enum CodingKeys: String, CodingKey { case name, props, occurredAt = "occurred_at" }
        }

        let installID: UUID
        let appVersion: String
        let osVersion: String
        let events: [Event]
        enum CodingKeys: String, CodingKey {
            case installID = "install_id", appVersion = "app_version", osVersion = "os_version", events
        }
    }

    func send(_ events: [AnalyticsEvent], installID: UUID) async throws {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let params = Params(
            installID: installID,
            appVersion: AppVersion.current.description,
            osVersion: "\(os.majorVersion).\(os.minorVersion)",
            events: events.map {
                Params.Event(name: $0.name, props: $0.props, occurredAt: $0.occurredAt.formatted(.iso8601))
            }
        )
        do {
            let _: Data = try await rpc.call("track_events", params: params)
        } catch RepositoryError.network {
            throw RepositoryError.network
        } catch {
            // 22023 (lô sai định dạng) và lỗi khác ngoài mạng → coi như lô hỏng.
            throw RepositoryError.decoding
        }
    }
}
