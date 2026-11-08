import Foundation
import Observation

/// Lưu / sửa địa điểm ngoài hệ thống (PRD 4.6): tên, loại, ghi chú; kiểm tra vùng MVP; gợi ý dự án trùng trong An Cư;
/// đề xuất An Cư thêm dự án (chỉ loại NOXH, người dùng tự chọn).
@MainActor
@Observable
final class PlaceEditorViewModel {
    /// Điểm bắt đầu khi tạo mới: kết quả Apple Maps hoặc ghim tay.
    struct Origin: Hashable, Sendable {
        var name: String
        var address: String?
        var location: GeoPoint
        var externalRef: String?
        /// Cho analytics: `search` | `pin`.
        var source: String

        init(candidate: PlaceCandidate) {
            name = candidate.name
            address = candidate.address
            location = candidate.location
            externalRef = candidate.externalRef
            source = "search"
        }

        init(pin location: GeoPoint) {
            name = ""
            address = nil
            self.location = location
            externalRef = nil
            source = "pin"
        }
    }

    enum Mode: Hashable, Sendable {
        case create(Origin)
        case edit(SavedPlace)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case failed(RepositoryError)
    }

    enum SuggestionOutcome: Equatable {
        case sent
        case failed(RepositoryError)
    }

    /// Trùng dự án trong An Cư nếu cách ≤ khoảng này (PRD 4.6).
    static let duplicateRadiusMeters: Double = 300

    let mode: Mode
    var name: String
    var kind: PlaceKind
    /// Mã icon (`place_icons`); `nil` = icon theo loại.
    var icon: String?
    var note: String
    /// "Đề xuất An Cư thêm dự án này" — chỉ hiện khi tạo mới, loại NOXH.
    var suggestsToAnCu = false

    private(set) var area: ServiceArea?
    private(set) var isCheckingArea: Bool
    /// Dự án trong hệ thống gần nhất trong `duplicateRadiusMeters` — gợi ý theo dõi thay vì lưu riêng.
    private(set) var nearbyProject: Project?
    private(set) var saveState: SaveState = .idle
    private(set) var suggestionOutcome: SuggestionOutcome?

    private let session: SessionStore
    private let projects: any ProjectRepository
    private let dataReports: any DataReportRepository
    private let resolveArea: @MainActor (GeoPoint) async -> ServiceArea?

    init(
        mode: Mode,
        session: SessionStore,
        projects: any ProjectRepository,
        dataReports: any DataReportRepository,
        resolveArea: @escaping @MainActor (GeoPoint) async -> ServiceArea?
    ) {
        self.mode = mode
        self.session = session
        self.projects = projects
        self.dataReports = dataReports
        self.resolveArea = resolveArea
        switch mode {
        case .create(let origin):
            name = origin.name
            kind = .commercial
            note = ""
            isCheckingArea = true
        case .edit(let place):
            name = place.name
            kind = place.kind
            icon = place.icon
            note = place.note ?? ""
            area = place.serviceArea
            isCheckingArea = false
        }
    }

    var isEditing: Bool { if case .edit = mode { true } else { false } }

    var location: GeoPoint {
        switch mode {
        case .create(let origin): origin.location
        case .edit(let place): place.location
        }
    }

    var address: String? {
        switch mode {
        case .create(let origin): origin.address
        case .edit(let place): place.address
        }
    }

    /// Tạo mới ngoài vùng (đã kiểm tra xong) → không lưu được.
    var isOutsideServiceArea: Bool { !isEditing && !isCheckingArea && area == nil }

    var noteCount: Int { note.count }
    var isNoteTooLong: Bool { note.trimmingCharacters(in: .whitespacesAndNewlines).count > SavedPlace.maxNoteLength }

    var canSave: Bool {
        guard saveState != .saving, !isCheckingArea, !isOutsideServiceArea, !isNoteTooLong, kind != .unknown,
              let cleaned = UserText.cleaned(name), cleaned.count <= SavedPlace.maxNameLength
        else { return false }
        return true
    }

    var canSuggest: Bool { !isEditing && kind == .socialHousing }

    func load() async {
        if !isEditing {
            area = await resolveArea(location)
            isCheckingArea = false
        }
        await findNearbyProject()
    }

    /// Dùng lại `projects_in_bbox` với khung nhỏ quanh điểm — không cần RPC mới (architecture.md 5.6).
    private func findNearbyProject() async {
        let span = 2 * Self.duplicateRadiusMeters / 111_000 * 1.2
        let region = MapRegion(center: location, latitudeDelta: span, longitudeDelta: span)
        guard let candidates = try? await projects.projects(in: region, filter: .all) else { return }
        nearbyProject = candidates
            .map { ($0, $0.location.distance(to: location)) }
            .filter { $0.1 <= Self.duplicateRadiusMeters }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Trả `true` khi đã lưu xong (sheet đóng). Đề xuất lỗi không làm hỏng việc lưu — chỉ báo lại.
    func save() async -> Bool {
        guard canSave else { return false }
        saveState = .saving
        do {
            switch mode {
            case .create(let origin):
                let draft = SavedPlaceDraft(
                    name: name, address: origin.address, location: origin.location, kind: kind,
                    note: note, externalRef: origin.externalRef, icon: icon
                )
                _ = try await session.createPlace(draft, source: origin.source)
                if canSuggest && suggestsToAnCu { await suggest(origin) }
            case .edit(let place):
                try await session.updatePlace(place.id, name: name, kind: kind, icon: icon, note: note)
            }
            saveState = .idle
            return true
        } catch {
            saveState = .failed(error)
            return false
        }
    }

    func delete() async -> Bool {
        guard case .edit(let place) = mode else { return false }
        saveState = .saving
        do {
            try await session.deletePlace(place.id)
            saveState = .idle
            return true
        } catch {
            saveState = .failed(error)
            return false
        }
    }

    /// Chỉ tên/địa chỉ/vị trí — KHÔNG gửi ghi chú riêng.
    private func suggest(_ origin: Origin) async {
        do {
            try await dataReports.suggestProject(name: name, address: origin.address, location: origin.location)
            suggestionOutcome = .sent
        } catch {
            suggestionOutcome = .failed(error as? RepositoryError ?? .network)
        }
    }
}
