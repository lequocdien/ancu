import Foundation
import SwiftUI
import Testing
@testable import AnCu

struct DesignSystemTests {
    @Test(arguments: [
        ("#0D9488", UInt32(0x0D9488)),
        ("ff5a3c", UInt32(0xFF5A3C)),
    ])
    func parsesValidHex(_ input: String, _ expected: UInt32) {
        #expect(Color.rgbValue(fromHex: input) == expected)
    }

    @Test(arguments: ["", "#FFF", "#GG0000", "#0D948800", "0x0D9488"])
    func rejectsInvalidHex(_ input: String) {
        #expect(Color.rgbValue(fromHex: input) == nil)
    }

    @Test func lineStyleFollowsCatalogAttribute() {
        // Server đổi kiểu nét qua catalog: "quy hoạch" được cấu hình thành nét liền mảnh.
        let catalog = LookupCatalog(items: [
            .routeStatus: [LookupItem(code: "quy_hoach", label: "Quy hoạch", sortOrder: 1, attributes: ["line_style": "thin"])],
        ])
        #expect(catalog.lineStyle(for: .planned) == .underConstruction)
    }

    @Test func lineStyleFallsBackWhenCatalogMissing() {
        let catalog = LookupCatalog.empty
        #expect(catalog.lineStyle(for: .operational) == .operational)
        #expect(catalog.lineStyle(for: .underConstruction) == .underConstruction)
        #expect(catalog.lineStyle(for: .planned) == .planned)
        // Trạng thái lạ không được trông như tuyến đã chạy.
        #expect(catalog.lineStyle(for: .unknown) == .planned)
    }

    /// Quy tắc spec mục 1: mọi API kính/material chỉ được gọi trong Core/DesignSystem/Glass.swift.
    @Test func glassAPIsOnlyInGlassFile() throws {
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AnCu")
        let forbidden = [
            ".glassEffect(", "glassEffectID(", "GlassEffectContainer", ".ultraThinMaterial",
            ".thinMaterial", ".regularMaterial", "buttonStyle(.glass", "tabBarMinimizeBehavior",
        ]
        let enumerator = try #require(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var violations: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" && url.lastPathComponent != "Glass.swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden where source.contains(token) {
                violations.append("\(url.lastPathComponent): \(token)")
            }
        }
        #expect(scanned > 10, "Không tìm thấy source app tại \(appSources.path)")
        #expect(violations.isEmpty, "Dùng modifier trong Glass.swift thay vì: \(violations)")
    }
}
