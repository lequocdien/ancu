import Foundation
import Testing
@testable import AnCu

private let fixedNow: @Sendable () -> Date = { MockDataStore.anchorDate.addingTimeInterval(12 * 3600) }

private func makeContainer() -> AppContainer {
    .mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none, now: fixedNow)
}

@MainActor
struct SessionStoreTests {
    @Test func guestSaveIsLocalAndPromptsOnlyOnce() async throws {
        let container = makeContainer()
        let session = SessionStore(container: container)
        await session.load()
        let ids = try await container.projects.projects(in: .mvpArea, filter: .all).prefix(2).map(\.id)

        #expect(try await session.toggleSave(ids[0]) == .savedLocallyNeedsPrompt)
        #expect(try await session.toggleSave(ids[1]) == .saved)
        #expect(session.bookmarks.allSatisfy { $0.isLocalOnly })
        #expect(try await session.toggleSave(ids[0]) == .removed)
        #expect(!session.isSaved(ids[0]))
    }

    @Test func notifyRequiresSignIn() async throws {
        let container = makeContainer()
        let session = SessionStore(container: container)
        await session.load()
        let id = try #require(try await container.projects.projects(in: .mvpArea, filter: .all).first?.id)

        #expect(try await session.setNotify(true, for: id) == false)
        #expect(!session.isNotifying(id))

        try await session.signIn(with: .apple)
        #expect(try await session.setNotify(true, for: id))
        // Bật thông báo cho dự án chưa lưu thì tự lưu.
        #expect(session.isSaved(id) && session.isNotifying(id))
    }

    @Test func signInMergesGuestBookmarksAndSignOutKeepsOnlyGuestOnes() async throws {
        let container = makeContainer()
        let session = SessionStore(container: container)
        await session.load()
        let ids = try await container.projects.projects(in: .mvpArea, filter: .all).prefix(2).map(\.id)

        _ = try await session.toggleSave(ids[0])
        try await session.signIn(with: .google)
        #expect(session.isSignedIn)
        #expect(session.bookmarks.allSatisfy { !$0.isLocalOnly })

        _ = try await session.toggleSave(ids[1])
        try await session.signOut()
        #expect(!session.isSignedIn)
        // Bookmark của tài khoản nằm trên server; máy không giữ lại sau đăng xuất.
        #expect(session.bookmarks.isEmpty)
    }

    @Test func deleteAccountClearsEverything() async throws {
        let container = makeContainer()
        let session = SessionStore(container: container)
        try await session.signIn(with: .apple)
        let id = try #require(try await container.projects.projects(in: .mvpArea, filter: .all).first?.id)
        _ = try await session.toggleSave(id)

        try await session.deleteAccount()
        #expect(!session.isSignedIn)
        #expect(session.bookmarks.isEmpty)
    }
}

@MainActor
struct ProjectDetailViewModelTests {
    private func makeViewModel(container: AppContainer) async throws -> ProjectDetailViewModel {
        let project = try #require(try await container.projects.projects(in: .mvpArea, filter: .all).first)
        return ProjectDetailViewModel(project: project, projects: container.projects, dataReports: container.dataReports, now: fixedNow)
    }

    @Test func loadsNearestInfra() async throws {
        let viewModel = try await makeViewModel(container: makeContainer())
        await viewModel.load()
        guard case .loaded = viewModel.detailState else { Issue.record("Phải tải được chi tiết"); return }
        #expect(!viewModel.nearestInfra.isEmpty)
        #expect(viewModel.nearestInfra.allSatisfy { $0.distanceMeters >= 0 })
    }

    @Test func reportRequiresNonBlankNoteWithinLimit() async throws {
        let viewModel = try await makeViewModel(container: makeContainer())
        viewModel.reportNote = "   "
        #expect(!viewModel.canSubmitReport)
        viewModel.reportNote = String(repeating: "a", count: ProjectDetailViewModel.reportNoteLimit + 1)
        #expect(!viewModel.canSubmitReport)
        viewModel.reportNote = "Sai khung nhận hồ sơ"
        #expect(viewModel.canSubmitReport)
    }

    @Test func reportAsGuestFailsUnauthorizedAndKeepsNote() async throws {
        let viewModel = try await makeViewModel(container: makeContainer())
        viewModel.reportNote = "Sai giá"
        await viewModel.submitReport()
        #expect(viewModel.reportState == .failed(.unauthorized))
        #expect(viewModel.reportNote == "Sai giá")
    }

    @Test func reportWhenSignedInSucceedsAndClearsNote() async throws {
        let container = makeContainer()
        _ = try await container.auth.signIn(with: .apple)
        let viewModel = try await makeViewModel(container: container)
        viewModel.reportNote = "Sai giá"
        await viewModel.submitReport()
        #expect(viewModel.reportState == .sent)
        #expect(viewModel.reportNote.isEmpty)
    }
}

struct DisplayFormatTests {
    @Test func price() {
        #expect(DisplayFormat.price(PriceRange(min: 15, max: 18.5, isEstimated: false)) == "15–18,5 tr/m²")
        #expect(DisplayFormat.price(PriceRange(min: 20, max: 20, isEstimated: true)) == "20 tr/m²")
    }

    @Test func distance() {
        #expect(DisplayFormat.distance(846) == "850 m")
        #expect(DisplayFormat.distance(1_234) == "1,2 km")
        #expect(DisplayFormat.distance(12_000) == "12 km")
    }

    @Test func thousandsSeparator() {
        #expect(DisplayFormat.number(1_200) == "1.200")
    }

    @Test func dateUsesVietnamTimeZone() {
        // 2026-11-30 18:00 UTC = 01/12/2026 01:00 giờ Việt Nam.
        let date = Date(timeIntervalSince1970: 1_796_061_600)
        #expect(DisplayFormat.date(date) == "01/12/2026")
    }

    @Test(arguments: [
        (ApplicationPhase.notAnnounced, "Chưa công bố"),
        (.upcoming(daysUntilStart: 0), "Mở hôm nay"),
        (.upcoming(daysUntilStart: 5), "Mở sau 5 ngày"),
        (.open(daysLeft: 0), "Hạn cuối hôm nay"),
        (.open(daysLeft: 12), "Còn 12 ngày"),
        (.ended, "Đã kết thúc"),
    ])
    func phase(_ phase: ApplicationPhase, _ expected: String) {
        #expect(DisplayFormat.phase(phase) == expected)
    }
}

@MainActor
struct MapSavedLayerTests {
    @Test func savedOnlyShowsBookmarkedProjects() async throws {
        let container = makeContainer()
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero
        )
        await viewModel.start()
        let saved = try #require(viewModel.projects.first)

        viewModel.savedProjectIDs = [saved.id]
        viewModel.showsSavedOnly = true
        let shownIDs = viewModel.mapItems.flatMap { item -> [Project.ID] in
            switch item {
            case .project(let project): [project.id]
            case .cluster(let cluster): cluster.projects.map(\.id)
            }
        }
        #expect(shownIDs == [saved.id])
    }
}
