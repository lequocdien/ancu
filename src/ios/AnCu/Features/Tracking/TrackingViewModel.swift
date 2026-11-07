import Foundation
import Observation

@MainActor
@Observable
final class TrackingViewModel {
    enum Segment: Hashable { case saved, inbox }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(RepositoryError)
    }

    /// Một hàng trong bảng so sánh. `bestIndex` = cột có giá trị tốt nhất (nil khi không so được).
    struct ComparisonRow: Identifiable, Equatable {
        let id: String
        let title: String
        let values: [String]
        let bestIndex: Int?
    }

    static let maxCompare = 3

    var segment: Segment = .saved
    private(set) var catalog: LookupCatalog = .empty
    private(set) var savedProjects: [Project] = []
    private(set) var savedState: LoadState = .idle
    private(set) var notifications: [AppNotification] = []
    private(set) var inboxState: LoadState = .idle

    var isComparing = false
    private(set) var compareSelection: [Project.ID] = []
    private(set) var comparisonDetails: [ProjectDetail] = []
    private(set) var comparisonState: LoadState = .idle

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }
    var canCompare: Bool { compareSelection.count >= 2 }

    private let projectRepository: any ProjectRepository
    private let notificationRepository: any NotificationRepository
    private let lookupRepository: any LookupRepository
    private let now: @Sendable () -> Date

    init(
        projects: any ProjectRepository,
        notifications: any NotificationRepository,
        lookup: any LookupRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.projectRepository = projects
        self.notificationRepository = notifications
        self.lookupRepository = lookup
        self.now = now
    }

    convenience init(container: AppContainer) {
        self.init(projects: container.projects, notifications: container.notifications, lookup: container.lookup)
    }

    // MARK: Đã lưu

    func loadSaved(ids: Set<Project.ID>) async {
        if catalog.items(in: .projectStatus).isEmpty {
            catalog = (try? await lookupRepository.catalog()) ?? .empty
        }
        guard !ids.isEmpty else {
            savedProjects = []
            savedState = .loaded
            compareSelection = []
            return
        }
        if savedProjects.isEmpty { savedState = .loading }
        do {
            let projects = try await projectRepository.projects(ids: ids)
            let at = now()
            savedProjects = projects.sorted { Self.sortKey($0, at: at) < Self.sortKey($1, at: at) }
            // Bỏ khỏi so sánh những dự án vừa bị bỏ lưu.
            compareSelection.removeAll { !ids.contains($0) }
            savedState = .loaded
        } catch {
            savedState = .failed(error as? RepositoryError ?? .network)
        }
    }

    func phase(of project: Project) -> ApplicationPhase {
        project.applicationPhase(at: now())
    }

    /// Phần thời gian nhận hồ sơ đã trôi qua (0…1). `nil` khi không trong đợt nhận hồ sơ.
    func elapsedFraction(of project: Project) -> Double? {
        guard case .open = phase(of: project), let window = project.applicationWindow, window.duration > 0 else { return nil }
        return min(max(now().timeIntervalSince(window.start) / window.duration, 0), 1)
    }

    /// Hạn gần nhất lên đầu: đang mở (còn ít ngày trước) → sắp mở → chưa công bố → đã kết thúc.
    static func sortKey(_ project: Project, at date: Date) -> SortKey {
        switch project.applicationPhase(at: date) {
        case .open(let days): SortKey(rank: 0, days: days, name: project.name)
        case .upcoming(let days): SortKey(rank: 1, days: days, name: project.name)
        case .notAnnounced: SortKey(rank: 2, days: 0, name: project.name)
        case .ended: SortKey(rank: 3, days: 0, name: project.name)
        }
    }

    struct SortKey: Comparable {
        let rank: Int
        let days: Int
        let name: String

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            (lhs.rank, lhs.days, lhs.name) < (rhs.rank, rhs.days, rhs.name)
        }
    }

    // MARK: So sánh

    func isSelectedForCompare(_ id: Project.ID) -> Bool {
        compareSelection.contains(id)
    }

    /// Chọn tối đa 3. Trả `false` khi đã đủ 3 mà chọn thêm.
    @discardableResult
    func toggleCompare(_ id: Project.ID) -> Bool {
        if let index = compareSelection.firstIndex(of: id) {
            compareSelection.remove(at: index)
            return true
        }
        guard compareSelection.count < Self.maxCompare else { return false }
        compareSelection.append(id)
        return true
    }

    func endComparing() {
        isComparing = false
        compareSelection = []
        comparisonDetails = []
        comparisonState = .idle
    }

    func loadComparison() async {
        comparisonState = .loading
        do {
            let repository = projectRepository
            var details: [ProjectDetail] = []
            try await withThrowingTaskGroup(of: ProjectDetail.self) { group in
                for id in compareSelection {
                    group.addTask { try await repository.project(id: id) }
                }
                for try await detail in group { details.append(detail) }
            }
            // Giữ đúng thứ tự người dùng chọn.
            comparisonDetails = compareSelection.compactMap { id in details.first { $0.project.id == id } }
            comparisonState = .loaded
        } catch {
            comparisonState = .failed(error as? RepositoryError ?? .network)
        }
    }

    var comparisonRows: [ComparisonRow] {
        let projects = comparisonDetails.map(\.project)
        let prices = projects.map { $0.price?.min }
        let metro = comparisonDetails.map { detail in
            detail.nearestInfra.filter { $0.node.type == .metroStation }.map(\.distanceMeters).min()
        }
        return [
            ComparisonRow(
                id: "status",
                title: String(localized: "Trạng thái"),
                values: projects.map { catalog.label(for: $0.status) },
                bestIndex: nil
            ),
            ComparisonRow(
                id: "window",
                title: String(localized: "Nhận hồ sơ"),
                values: projects.map { DisplayFormat.phase(phase(of: $0)) },
                bestIndex: nil
            ),
            ComparisonRow(
                id: "price",
                title: String(localized: "Giá tham khảo"),
                values: projects.map { $0.price.map(DisplayFormat.price) ?? "—" },
                bestIndex: Self.indexOfMinimum(prices)
            ),
            ComparisonRow(
                id: "metro",
                title: String(localized: "Ga Metro gần nhất"),
                values: metro.map { $0.map(DisplayFormat.distance) ?? "—" },
                bestIndex: Self.indexOfMinimum(metro)
            ),
            ComparisonRow(
                id: "units",
                title: String(localized: "Số căn"),
                values: projects.map { $0.unitCount.map(DisplayFormat.number) ?? "—" },
                bestIndex: nil
            ),
        ]
    }

    /// Chỉ đánh dấu "tốt nhất" khi có ít nhất 2 giá trị và giá trị nhỏ nhất là duy nhất.
    static func indexOfMinimum<T: Comparable>(_ values: [T?]) -> Int? {
        let present = values.enumerated().compactMap { index, value in value.map { (index, $0) } }
        guard present.count >= 2, let minimum = present.map(\.1).min() else { return nil }
        let matches = present.filter { $0.1 == minimum }
        return matches.count == 1 ? matches[0].0 : nil
    }

    // MARK: Thông báo

    func loadInbox() async {
        if notifications.isEmpty { inboxState = .loading }
        do {
            notifications = try await notificationRepository.inbox()
            inboxState = .loaded
        } catch {
            inboxState = .failed(error as? RepositoryError ?? .network)
        }
    }

    func markAsRead(_ notification: AppNotification) async {
        guard !notification.isRead else { return }
        // Cập nhật lạc quan; lỗi thì để lần tải sau đồng bộ lại.
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
        try? await notificationRepository.markAsRead(id: notification.id)
    }

    func project(for notification: AppNotification) async -> Project? {
        if let project = savedProjects.first(where: { $0.id == notification.projectID }) { return project }
        return try? await projectRepository.projects(ids: [notification.projectID]).first
    }

    func relativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(DisplayFormat.locale))
    }
}
