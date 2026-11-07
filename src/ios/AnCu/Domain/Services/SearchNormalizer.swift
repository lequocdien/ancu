import Foundation

/// Bỏ dấu, chữ thường, "đ" → "d", để "thu duc" khớp "Thủ Đức".
enum SearchNormalizer {
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
