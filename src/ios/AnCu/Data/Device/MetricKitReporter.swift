import MetricKit

/// Crash / treo / lỗi CPU từ MetricKit (Phase 1 bước 5.1) → sự kiện `diagnostic` (chỉ số đếm + loại, không gửi call stack
/// để giữ lô nhỏ và không lộ dữ liệu). iOS giao payload ~1 lần/ngày, payload crash sẽ đến ở lần mở app sau.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let analytics: any AnalyticsTracker

    init(analytics: any AnalyticsTracker) {
        self.analytics = analytics
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            analytics.track(Self.event(
                crashes: payload.crashDiagnostics?.count ?? 0,
                hangs: payload.hangDiagnostics?.count ?? 0,
                cpuExceptions: payload.cpuExceptionDiagnostics?.count ?? 0,
                diskWrites: payload.diskWriteExceptionDiagnostics?.count ?? 0,
                signals: payload.crashDiagnostics?.compactMap { $0.signal?.stringValue } ?? [],
                occurredAt: payload.timeStampEnd
            ))
        }
    }

    static func event(
        crashes: Int, hangs: Int, cpuExceptions: Int, diskWrites: Int, signals: [String], occurredAt: Date
    ) -> AnalyticsEvent {
        var props = [
            "crashes": String(crashes), "hangs": String(hangs),
            "cpu_exceptions": String(cpuExceptions), "disk_writes": String(diskWrites),
        ]
        if !signals.isEmpty { props["signals"] = Set(signals).sorted().joined(separator: ",") }
        return AnalyticsEvent(name: AnalyticsEvent.diagnostic, props: props, occurredAt: occurredAt)
    }
}
