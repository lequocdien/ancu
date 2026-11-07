import Foundation

/// Phần tử hiển thị trên map: một dự án, hoặc một cụm nhiều dự án khi zoom out.
enum MapItem: Identifiable, Hashable, Sendable {
    case project(Project)
    case cluster(ProjectCluster)

    var id: String {
        switch self {
        case .project(let project): "p-\(project.id.uuidString)"
        case .cluster(let cluster): cluster.id
        }
    }

    var location: GeoPoint {
        switch self {
        case .project(let project): project.location
        case .cluster(let cluster): cluster.center
        }
    }
}

struct ProjectCluster: Identifiable, Hashable, Sendable {
    let id: String
    let center: GeoPoint
    let projects: [Project]

    /// Khung bao các dự án trong cụm, nới thêm lề — dùng để zoom vào khi bấm cụm.
    var boundingRegion: MapRegion {
        let lats = projects.map(\.location.latitude)
        let lons = projects.map(\.location.longitude)
        let (minLat, maxLat) = (lats.min() ?? center.latitude, lats.max() ?? center.latitude)
        let (minLon, maxLon) = (lons.min() ?? center.longitude, lons.max() ?? center.longitude)
        return MapRegion(
            center: GeoPoint(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.01)
        )
    }
}

/// Gom cụm theo lưới. Đủ cho vài trăm dự án/khung nhìn; nhiều hơn thì chuyển sang gom cụm phía server.
///
/// - Lưới neo theo tọa độ tuyệt đối (không theo mép khung nhìn) → kéo map không làm cụm xáo trộn.
/// - Kích thước ô làm tròn theo lũy thừa 2 → zoom nhẹ không đổi cách gom, chỉ đổi khi qua một "nấc".
enum ProjectClusterer {
    /// Số ô theo chiều ngang của khung nhìn (≈ khoảng cách tối thiểu giữa hai ghim).
    static let divisions: Double = 8
    /// Zoom sâu hơn mức này (độ kinh) thì hiện từng ghim, không gom.
    static let clusteringThreshold: Double = 0.04

    static func items(for projects: [Project], in region: MapRegion) -> [MapItem] {
        guard region.longitudeDelta > clusteringThreshold else {
            return projects.map(MapItem.project)
        }
        let cell = cellSize(for: region)
        let groups = Dictionary(grouping: projects) { project in
            CellKey(
                x: Int((project.location.longitude / cell).rounded(.down)),
                y: Int((project.location.latitude / cell).rounded(.down))
            )
        }
        return groups
            .map { key, members -> MapItem in
                guard members.count > 1 else { return .project(members[0]) }
                let center = GeoPoint(
                    latitude: members.map(\.location.latitude).reduce(0, +) / Double(members.count),
                    longitude: members.map(\.location.longitude).reduce(0, +) / Double(members.count)
                )
                return .cluster(ProjectCluster(
                    id: "c-\(cell)-\(key.x)-\(key.y)",
                    center: center,
                    projects: members.sorted { $0.name < $1.name }
                ))
            }
            .sorted { $0.id < $1.id }
    }

    static func cellSize(for region: MapRegion) -> Double {
        let raw = region.longitudeDelta / divisions
        return pow(2, log2(raw).rounded())
    }

    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }
}
