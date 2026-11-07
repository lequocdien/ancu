import Foundation
import Testing
@testable import AnCu

private actor RecordingSink: AnalyticsSink {
    var batches: [[AnalyticsEvent]] = []
    var installIDs: Set<UUID> = []
    var failure: RepositoryError?

    func setFailure(_ error: RepositoryError?) { failure = error }

    func send(_ events: [AnalyticsEvent], installID: UUID) async throws {
        if let failure { throw failure }
        batches.append(events)
        installIDs.insert(installID)
    }
}

struct BatchingAnalyticsTests {
    private func make(_ sink: RecordingSink, suite: MockDefaultsSuite = MockDefaultsSuite(name: "test.\(UUID().uuidString)")) -> BatchingAnalytics {
        BatchingAnalytics(sink: sink, suite: suite, interval: .seconds(3600))
    }

    private func event(_ i: Int) -> AnalyticsEvent { AnalyticsEvent(name: "e\(i)") }

    @Test func sendsFullBatchesAndFlushesRemainder() async {
        let sink = RecordingSink()
        let analytics = make(sink)
        for i in 0..<25 { await analytics.enqueue(event(i)) }
        #expect(await sink.batches.map(\.count) == [20])
        #expect(await analytics.bufferedCount == 5)
        await analytics.flush()
        #expect(await sink.batches.map(\.count) == [20, 5])
        #expect(await sink.installIDs.count == 1)
    }

    @Test func networkErrorKeepsEventsDecodingErrorDropsThem() async {
        let sink = RecordingSink()
        let analytics = make(sink)
        await sink.setFailure(.network)
        await analytics.enqueue(event(1))
        await analytics.flush()
        #expect(await analytics.bufferedCount == 1)

        await sink.setFailure(.decoding)
        await analytics.flush()
        #expect(await analytics.bufferedCount == 0)
        #expect(await sink.batches.isEmpty)
    }

    @Test func optOutDropsEverything() async {
        let suite = MockDefaultsSuite(name: "test.\(UUID().uuidString)")
        let sink = RecordingSink()
        let analytics = make(sink, suite: suite)
        await analytics.enqueue(event(1))
        suite.open().set(false, forKey: BatchingAnalytics.enabledKey)
        await analytics.enqueue(event(2))
        await analytics.flush()
        #expect(await analytics.bufferedCount == 0)
        #expect(await sink.batches.isEmpty)
    }

    @Test func installIDIsStablePerInstall() async {
        let suite = MockDefaultsSuite(name: "test.\(UUID().uuidString)")
        let first = await make(RecordingSink(), suite: suite).installID
        #expect(await make(RecordingSink(), suite: suite).installID == first)
    }

    @Test func bufferIsBounded() async {
        let sink = RecordingSink()
        await sink.setFailure(.network)
        let analytics = make(sink)
        for i in 0..<(BatchingAnalytics.maxBuffered + 50) { await analytics.enqueue(event(i)) }
        #expect(await analytics.bufferedCount == BatchingAnalytics.maxBuffered)
    }

    @Test func metricKitEventHasCountsNotStacks() {
        let event = MetricKitReporter.event(crashes: 2, hangs: 1, cpuExceptions: 0, diskWrites: 0,
                                            signals: ["SIGSEGV", "SIGABRT", "SIGSEGV"], occurredAt: .now)
        #expect(event.name == "diagnostic")
        #expect(event.props["crashes"] == "2" && event.props["signals"] == "SIGABRT,SIGSEGV")
    }

    @Test func eventNamesMatchServerRule() {
        let names = [AnalyticsEvent.appOpen, AnalyticsEvent.projectViewed, AnalyticsEvent.projectSaved, AnalyticsEvent.notifyEnabled,
                     AnalyticsEvent.signInCompleted, AnalyticsEvent.eligibilityCompleted, AnalyticsEvent.reportSubmitted,
                     AnalyticsEvent.compareOpened, AnalyticsEvent.diagnostic]
        // Khớp CHECK name ~ '^[a-z][a-z0-9_]{1,39}$' (migration 08).
        #expect(names.allSatisfy { $0.wholeMatch(of: /[a-z][a-z0-9_]{1,39}/) != nil })
    }

    @Test func supabaseSinkSendsContractShape() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("track_events", json: "1")
        let id = UUID()
        try await SupabaseAnalyticsSink(rpc: rpc).send([AnalyticsEvent(name: "app_open", props: ["a": "b"])], installID: id)
        let params = try #require(rpc.lastParams("track_events"))
        #expect(params["install_id"] as? String == id.uuidString)
        #expect(params["app_version"] as? String == "0.1.0")
        let events = try #require(params["events"] as? [[String: Any]])
        #expect(events.first?["name"] as? String == "app_open" && events.first?["occurred_at"] is String)

        rpc.fail("track_events", with: .unauthorized)
        await #expect(throws: RepositoryError.decoding) {
            try await SupabaseAnalyticsSink(rpc: rpc).send([AnalyticsEvent(name: "x1")], installID: id)
        }
    }
}

@MainActor
struct SessionAnalyticsTests {
    private final class Recorder: AnalyticsTracker, @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [AnalyticsEvent] = []
        var names: [String] { lock.withLock { _events.map(\.name) } }
        func track(_ event: AnalyticsEvent) { lock.withLock { _events.append(event) } }
        func flush() async {}
    }

    @Test func tracksFunnelStepsWithoutPersonalData() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let recorder = Recorder()
        let session = SessionStore(auth: container.auth, bookmarks: container.bookmarks, analytics: recorder)
        let id = UUID()
        _ = try await session.toggleSave(id)
        try await session.sendEmailCode(to: "an@ancu.vn")
        try await session.verifyEmailCode(MockAuthService.emailCode, email: "an@ancu.vn")
        _ = try await session.setNotify(true, for: id)
        #expect(recorder.names == ["project_saved", "sign_in_completed", "notify_enabled"])
    }
}
