import Foundation

/// Phường/xã theo địa giới mới, giữ tên cũ để tìm kiếm ("Thủ Đức", "Dĩ An", "Biên Hòa"…).
struct AdministrativeUnit: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let name: String
    let province: String
    let serviceArea: ServiceArea
    let oldNames: [String]
    let center: GeoPoint
}

enum SearchResult: Identifiable, Hashable, Sendable {
    case project(Project)
    case place(AdministrativeUnit)

    var id: String {
        switch self {
        case .project(let project): "project-\(project.id.uuidString)"
        case .place(let unit): "place-\(unit.code)"
        }
    }
}
