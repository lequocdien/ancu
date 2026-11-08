import SwiftUI

/// Sự kiện sử dụng ẩn danh (Phase 1 bước 5.1). KHÔNG đưa vào props: tên, email, SĐT, từ khóa tìm kiếm, vị trí,
/// câu trả lời kiểm tra điều kiện — chỉ mã danh mục / số đếm / cờ.
struct AnalyticsEvent: Equatable, Sendable {
    let name: String
    var props: [String: String] = [:]
    var occurredAt: Date = .now

    static let appOpen = "app_open"
    static let projectViewed = "project_viewed"
    static let projectSaved = "project_saved"
    static let notifyEnabled = "notify_enabled"
    static let signInCompleted = "sign_in_completed"
    static let eligibilityCompleted = "eligibility_completed"
    static let reportSubmitted = "report_submitted"
    static let compareOpened = "compare_opened"
    /// Props chỉ có `kind` / `source` — KHÔNG bao giờ tên, địa chỉ, ghi chú (PRD 4.6).
    static let placeSaved = "place_saved"
    static let noteEdited = "note_edited"
    static let projectSuggested = "project_suggested"
    static let diagnostic = "diagnostic"
}

protocol AnalyticsTracker: Sendable {
    /// Không ném lỗi, không chặn UI: mất vài sự kiện chấp nhận được.
    func track(_ event: AnalyticsEvent)
    /// Gửi ngay phần còn trong bộ đệm (khi app vào nền).
    func flush() async
}

struct NoopAnalytics: AnalyticsTracker {
    func track(_ event: AnalyticsEvent) {}
    func flush() async {}
}

extension EnvironmentValues {
    @Entry var analytics: any AnalyticsTracker = NoopAnalytics()
}
