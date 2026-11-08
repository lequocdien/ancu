import Foundation
import Testing
@testable import AnCu

struct RouteHitTesterTests {
    private func route(_ name: String, _ type: RouteType, _ points: [(Double, Double)]) -> InfraRoute {
        InfraRoute(
            id: UUID(), name: name, type: type, status: .operational, expectedYear: nil, colorHex: "#000000",
            segments: [points.map { GeoPoint(latitude: $0.0, longitude: $0.1) }],
            sourceURL: URL(string: "https://example.com")!, verifiedAt: .now
        )
    }

    @Test func picksNearestRouteWithinTolerance() {
        // Hai tuyến song song cách nhau ~1,1 km (0,01° vĩ độ).
        let a = route("A", .metro, [(10.80, 106.60), (10.80, 106.70)])
        let b = route("B", .metro, [(10.81, 106.60), (10.81, 106.70)])
        let tap = GeoPoint(latitude: 10.8003, longitude: 106.65)   // ~33 m từ A
        #expect(RouteHitTester.nearestRoute(to: tap, in: [a, b], toleranceMeters: 50)?.name == "A")
        #expect(RouteHitTester.nearestRoute(to: tap, in: [a, b], toleranceMeters: 20) == nil)
    }

    @Test func distanceToSegmentEndIsMeasuredToEndpoint() {
        let a = route("A", .ringRoad, [(10.80, 106.60), (10.80, 106.70)])
        // Ra ngoài đầu mút 0,001° kinh độ ≈ 109 m.
        let distance = RouteHitTester.distanceMeters(from: GeoPoint(latitude: 10.80, longitude: 106.701), to: a)
        #expect(abs(distance - 109) < 3)
    }
}

@MainActor
struct RouteSelectionTests {
    private func make() async -> MapViewModel {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero
        )
        await viewModel.start()
        return viewModel
    }

    @Test func allRoutesOfATypeShareOneColorFromCatalog() async {
        let viewModel = await make()
        let catalog = viewModel.catalog
        #expect(catalog.item(for: RouteType.metro)?.colorHex == "#2563EB")
        #expect(catalog.item(for: RouteType.expressway)?.colorHex == "#DB2777")
        // 4 loại → 4 màu khác nhau.
        let hexes = Set(catalog.orderedCases(RouteType.self).compactMap { catalog.item(for: $0)?.colorHex })
        #expect(hexes.count == 4)
    }

    /// Ga Bến Thành (10.7721, 106.6983) là điểm đầu Metro 1 và Metro 2 — chạm vào là trúng metro.
    @Test func tapOnRouteSelectsItAndEmptyTapClears() async {
        let viewModel = await make()
        #expect(viewModel.selectRoute(near: GeoPoint(latitude: 10.7766, longitude: 106.7031), toleranceMeters: 60))
        #expect(viewModel.selectedRoute?.type == .metro)

        #expect(!viewModel.selectRoute(near: GeoPoint(latitude: 10.45, longitude: 106.40), toleranceMeters: 60))
        #expect(viewModel.selectedRoute == nil)
    }

    @Test func hiddenTypeIsNotSelectableAndHidingClearsSelection() async {
        let viewModel = await make()
        let onMetro1 = GeoPoint(latitude: 10.7766, longitude: 106.7031)
        viewModel.selectRoute(near: onMetro1, toleranceMeters: 60)
        viewModel.toggleRouteType(.metro)
        #expect(viewModel.selectedRoute == nil)
        #expect(viewModel.selectedRoute?.type != .metro)
        viewModel.selectRoute(near: onMetro1, toleranceMeters: 60)
        #expect(viewModel.selectedRoute?.type != .metro)
    }

    @Test func pickingPlaceClearsAndBlocksRouteSelection() async {
        let viewModel = await make()
        viewModel.selectRoute(near: GeoPoint(latitude: 10.7766, longitude: 106.7031), toleranceMeters: 60)
        viewModel.startPick(at: GeoPoint(latitude: 10.80, longitude: 106.70))
        #expect(viewModel.selectedRoute == nil)
        #expect(!viewModel.selectRoute(near: GeoPoint(latitude: 10.7766, longitude: 106.7031), toleranceMeters: 60))
    }
}

/// Cùng độ rộng cho mọi tuyến; trạng thái chỉ khác ở kiểu nét (góp ý 2026-11-07: "line không đều").
struct RouteLineStyleTests {
    private let all: [RouteLineStyle] = [.operational, .underConstruction, .planned]

    @Test func everyStatusHasSameWidth() {
        #expect(Set(all.map(\.lineWidth)) == [RouteLineStyle.width])
    }

    @Test func statusesAreDistinguishableByPattern() {
        #expect(Set(all.map(\.dash)).count == 3)
        #expect(RouteLineStyle.operational.dash.isEmpty)
        #expect(RouteLineStyle.underConstruction.dash == [12, 4])
        #expect(RouteLineStyle.planned.dash == [4, 6])
    }

    /// Đầu tròn lấn lineWidth/2 mỗi bên vào khe → nét đứt phải dùng đầu vuông để khe còn thấy được.
    @Test func dashedLinesUseButtCapsSoGapsStayVisible() {
        for style in all where !style.dash.isEmpty {
            #expect(style.strokeStyle.lineCap == .butt)
            #expect(style.dash[1] >= 4)
        }
        #expect(RouteLineStyle.operational.strokeStyle.lineCap == .round)
    }
}

/// geometry_accuracy (migration 16): thiếu/lạ → minh họa; chỉ tuyến chính xác mới không có cảnh báo.
@MainActor
struct GeometryAccuracyTests {
    @Test func unknownOrMissingIsIllustrative() {
        #expect(GeometryAccuracy(code: nil) == .illustrative)
        #expect(GeometryAccuracy(code: "rat_chinh_xac") == .illustrative)
        #expect(GeometryAccuracy(code: "chinh_xac") == .exact)
        #expect(GeometryAccuracy(code: "gan_dung") == .approximate)
    }

    @Test func onlyExactRoutesHaveNoCaveat() {
        #expect(RouteInfoCard.caveat(.exact) == nil)
        #expect(RouteInfoCard.caveat(.approximate) != nil)
        #expect(RouteInfoCard.caveat(.illustrative) != nil)
    }

    @Test func mockRoutesDecodeAsIllustrative() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let routes = try await container.infrastructure.routes(types: [])
        #expect(!routes.isEmpty && routes.allSatisfy { $0.geometryAccuracy == .illustrative })
    }
}
