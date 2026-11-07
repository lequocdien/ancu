import Foundation
import Observation

/// Luồng xóa tài khoản 2 bước (bắt buộc với App Store) + đăng xuất. Trạng thái phiên nằm ở `SessionStore`.
@MainActor
@Observable
final class AccountViewModel {
    enum DeleteStep: Equatable {
        case idle
        /// Bước 1: giải thích hậu quả.
        case explaining
        /// Bước 2: xác nhận cuối, không hoàn tác.
        case finalConfirm
        case deleting
        case deleted
    }

    var deleteStep: DeleteStep = .idle
    var error: RepositoryError?
    private(set) var isSigningOut = false

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func requestDelete() {
        deleteStep = .explaining
    }

    func continueDelete() {
        guard deleteStep == .explaining else { return }
        deleteStep = .finalConfirm
    }

    func cancelDelete() {
        deleteStep = .idle
    }

    func confirmDelete() async {
        guard deleteStep == .finalConfirm else { return }
        deleteStep = .deleting
        do {
            try await session.deleteAccount()
            deleteStep = .deleted
        } catch {
            self.error = error
            deleteStep = .idle
        }
    }

    func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await session.signOut()
        } catch {
            self.error = error
        }
    }
}
