import Foundation
import Testing
@testable import AnCu

@MainActor
struct TrackingViewModelTests {
    private static let fixedNow: @Sendable () -> Date = { MockDataStore.anchorDate.addingTimeInterval(12 * 3600) }

    private func make() -> (TrackingViewModel, AppContainer) {
        let container = AppContainer.mock(
            defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none, now: Self.fixedNow
        )
        let viewModel = TrackingViewModel(
            projects: container.projects, notifications: container.notifications, lookup: container.lookup, now: Self.fixedNow
        )
        return (viewModel, container)
    }

    private func allIDs(_ container: AppContainer) async throws -> Set<Project.ID> {
        Set(try await container.projects.projects(in: .mvpArea, filter: .all).map(\.id))
    }

    @Test func savedProjectsSortedByNearestDeadline() async throws {
        let (viewModel, container) = make()
        await viewModel.loadSaved(ids: try await allIDs(container))

        #expect(viewModel.savedProjects.count == 15)
        let keys = viewModel.savedProjects.map { TrackingViewModel.sortKey($0, at: Self.fixedNow()) }
        #expect(keys == keys.sorted())
        // Dự án đang nhận hồ sơ luôn đứng đầu.
        if case .open = viewModel.phase(of: viewModel.savedProjects[0]) {} else { Issue.record("Đầu danh sách phải đang mở") }
    }

    @Test func emptyIDsGiveEmptyListWithoutError() async {
        let (viewModel, _) = make()
        await viewModel.loadSaved(ids: [])
        #expect(viewModel.savedProjects.isEmpty)
        #expect(viewModel.savedState == .loaded)
    }

    @Test func elapsedFractionOnlyForOpenWindows() async throws {
        let (viewModel, container) = make()
        await viewModel.loadSaved(ids: try await allIDs(container))
        for project in viewModel.savedProjects {
            let fraction = viewModel.elapsedFraction(of: project)
            if case .open = viewModel.phase(of: project) {
                #expect(fraction.map { (0...1).contains($0) } == true)
            } else {
                #expect(fraction == nil)
            }
        }
    }

    @Test func compareSelectionCapsAtThree() async throws {
        let (viewModel, container) = make()
        await viewModel.loadSaved(ids: try await allIDs(container))
        let ids = viewModel.savedProjects.prefix(4).map(\.id)

        #expect(viewModel.toggleCompare(ids[0]))
        #expect(!viewModel.canCompare)
        #expect(viewModel.toggleCompare(ids[1]))
        #expect(viewModel.toggleCompare(ids[2]))
        #expect(viewModel.canCompare)
        #expect(!viewModel.toggleCompare(ids[3]))
        #expect(viewModel.compareSelection == Array(ids.prefix(3)))

        // Bỏ lưu một dự án đang chọn → tự rời khỏi so sánh.
        await viewModel.loadSaved(ids: Set(ids.dropFirst()))
        #expect(viewModel.compareSelection == [ids[1], ids[2]])
    }

    @Test func comparisonKeepsSelectionOrderAndMarksCheapest() async throws {
        let (viewModel, container) = make()
        await viewModel.loadSaved(ids: try await allIDs(container))
        let picked = viewModel.savedProjects.filter { $0.price != nil }.prefix(3).map(\.id)
        picked.forEach { viewModel.toggleCompare($0) }

        await viewModel.loadComparison()

        #expect(viewModel.comparisonState == .loaded)
        #expect(viewModel.comparisonDetails.map(\.project.id) == picked)
        let priceRow = try #require(viewModel.comparisonRows.first { $0.id == "price" })
        let mins = viewModel.comparisonDetails.map { $0.project.price!.min }
        #expect(priceRow.bestIndex == TrackingViewModel.indexOfMinimum(mins))
    }

    @Test func indexOfMinimumRequiresUniqueWinner() {
        #expect(TrackingViewModel.indexOfMinimum([3, 1, 2]) == 1)
        #expect(TrackingViewModel.indexOfMinimum([1, 1, 2]) == nil)
        #expect(TrackingViewModel.indexOfMinimum([nil, 5]) == nil)
        #expect(TrackingViewModel.indexOfMinimum([Int?.none, 5, 7]) == 1)
    }

    @Test func inboxRequiresSignInAndMarksRead() async throws {
        let (viewModel, container) = make()
        await viewModel.loadInbox()
        #expect(viewModel.inboxState == .failed(.unauthorized))

        _ = try await container.auth.signIn(with: .apple)
        await viewModel.loadInbox()
        #expect(viewModel.notifications.count == 8)
        let unread = try #require(viewModel.notifications.first { !$0.isRead })
        let before = viewModel.unreadCount

        await viewModel.markAsRead(unread)
        #expect(viewModel.unreadCount == before - 1)
        await viewModel.loadInbox()
        #expect(viewModel.notifications.first { $0.id == unread.id }?.isRead == true)
    }
}
