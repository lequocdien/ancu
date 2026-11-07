import Foundation
import Testing
@testable import AnCu

@MainActor
struct AccountViewModelTests {
    private func make() async throws -> (AccountViewModel, SessionStore) {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let session = SessionStore(container: container)
        try await session.signIn(with: .apple)
        return (AccountViewModel(session: session), session)
    }

    @Test func deleteRequiresBothSteps() async throws {
        let (viewModel, session) = try await make()

        // Không thể nhảy thẳng tới xác nhận cuối.
        await viewModel.confirmDelete()
        #expect(session.isSignedIn)

        viewModel.requestDelete()
        #expect(viewModel.deleteStep == .explaining)
        await viewModel.confirmDelete()
        #expect(session.isSignedIn)

        viewModel.continueDelete()
        #expect(viewModel.deleteStep == .finalConfirm)
        await viewModel.confirmDelete()
        #expect(viewModel.deleteStep == .deleted)
        #expect(!session.isSignedIn)
    }

    @Test func cancelAtAnyStepKeepsAccount() async throws {
        let (viewModel, session) = try await make()
        viewModel.requestDelete()
        viewModel.continueDelete()
        viewModel.cancelDelete()
        #expect(viewModel.deleteStep == .idle)
        await viewModel.confirmDelete()
        #expect(session.isSignedIn)
    }

    @Test func signOut() async throws {
        let (viewModel, session) = try await make()
        await viewModel.signOut()
        #expect(!session.isSignedIn)
        #expect(viewModel.error == nil)
    }
}
