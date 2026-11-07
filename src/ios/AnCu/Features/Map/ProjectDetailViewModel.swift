import Foundation
import Observation

@MainActor
@Observable
final class ProjectDetailViewModel {
    enum DetailState: Equatable {
        case loading
        case loaded(ProjectDetail)
        case failed(RepositoryError)
    }

    enum ReportState: Equatable {
        case idle
        case sending
        case sent
        case failed(RepositoryError)
    }

    /// Có sẵn từ ghim/tìm kiếm → header hiện ngay, không chờ tải chi tiết.
    let project: Project
    private(set) var detailState: DetailState = .loading
    private(set) var reportState: ReportState = .idle
    var reportNote = ""

    static let reportNoteLimit = 500

    private let projectRepository: any ProjectRepository
    private let dataReportRepository: any DataReportRepository
    private let now: @Sendable () -> Date

    init(
        project: Project,
        projects: any ProjectRepository,
        dataReports: any DataReportRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.project = project
        self.projectRepository = projects
        self.dataReportRepository = dataReports
        self.now = now
    }

    convenience init(project: Project, container: AppContainer) {
        self.init(project: project, projects: container.projects, dataReports: container.dataReports)
    }

    var phase: ApplicationPhase { project.applicationPhase(at: now()) }
    var isStale: Bool { project.isStale(at: now()) }

    var nearestInfra: [NearestInfra] {
        if case .loaded(let detail) = detailState { detail.nearestInfra } else { [] }
    }

    var canSubmitReport: Bool {
        let trimmed = reportNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= Self.reportNoteLimit && reportState != .sending
    }

    func load() async {
        detailState = .loading
        do {
            detailState = .loaded(try await projectRepository.project(id: project.id))
        } catch {
            detailState = .failed(error as? RepositoryError ?? .network)
        }
    }

    func submitReport() async {
        guard canSubmitReport else { return }
        reportState = .sending
        do {
            try await dataReportRepository.reportIncorrectData(
                projectID: project.id,
                note: reportNote.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            reportState = .sent
            reportNote = ""
        } catch {
            reportState = .failed(error as? RepositoryError ?? .network)
        }
    }

    func resetReport() {
        reportState = .idle
    }
}
