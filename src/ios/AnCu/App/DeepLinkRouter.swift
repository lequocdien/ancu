import Foundation
import Observation

/// Điều hướng từ bên ngoài vào app (bấm thông báo; sau này Universal Link từ trang web công khai).
@MainActor
@Observable
final class DeepLinkRouter {
    /// Dự án cần mở. Màn Bản đồ tiêu thụ rồi đặt lại `nil`.
    private(set) var pendingProjectID: Project.ID?

    func open(projectID: Project.ID) {
        pendingProjectID = projectID
    }

    func consume() -> Project.ID? {
        defer { pendingProjectID = nil }
        return pendingProjectID
    }
}
