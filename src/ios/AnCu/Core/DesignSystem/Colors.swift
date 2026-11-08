import SwiftUI

// MARK: - Token màu
//
// Token adaptive (Light / Dark / High Contrast) nằm trong `Assets.xcassets/Tokens`. Xcode tự sinh
// `Color.brandPrimary`, `.brandAccent`, `.statusOpen`, `.statusSoon`, `.statusClosed`, `.statusBuilding`
// (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS) — KHÔNG khai báo lại ở đây.
// `brandAccent` dùng cho cảnh báo/nhấn, không dùng làm tint kính.
// `onBrandPrimary`: chữ/icon trên nền brandPrimary. Dark mode là chữ tối vì brandPrimary dark (#2DD4BF) quá sáng cho chữ trắng.
//
// File này giữ: màu tuyến (content trên map, một giá trị cho cả Light/Dark), nền mesh, và parse hex từ Domain.

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Hex "#RRGGBB" hoặc "RRGGBB" từ `LookupItem.colorHex` / `InfraRoute.colorHex`. Sai định dạng → `nil`.
    init?(hex: String) {
        guard let rgb = Self.rgbValue(fromHex: hex) else { return nil }
        self.init(rgb: rgb)
    }

    static func rgbValue(fromHex hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}

// MARK: - Màu tuyến THEO LOẠI (2026-11-07, architecture.md 5.6) — fallback khi catalog thiếu `color_hex`.
// Màu = loại, kiểu nét = trạng thái. Metro xanh dương (không đỏ: cạnh cam Vành đai khó phân biệt với người mù màu
// đỏ–lục); Cao tốc hồng đậm (không tím: trùng ghim "Đang xây").

extension Color {
    static let routeMetro = Color(rgb: 0x2563EB)
    static let routeRing = Color(rgb: 0xF97316)
    static let routeExpressway = Color(rgb: 0xDB2777)
    static let routeNational = Color(rgb: 0x64748B)
}

// MARK: - Nền mesh (màn không có map)

enum MeshPalette {
    /// Thứ tự: tông brand nhạt · trung tính · tông accent ấm.
    static let light = [Color(rgb: 0xCCFBF1), Color(rgb: 0xF0FDFA), Color(rgb: 0xFFE4DC)]
    static let dark = [Color(rgb: 0x042F2E), Color(rgb: 0x0B1120), Color(rgb: 0x3B1A12)]

    static func colors(for scheme: ColorScheme) -> [Color] {
        scheme == .dark ? dark : light
    }
}
