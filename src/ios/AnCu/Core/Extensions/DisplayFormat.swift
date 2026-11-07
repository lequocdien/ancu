import Foundation

/// Format số liệu hiển thị theo tiếng Việt (dấu phẩy thập phân, dấu chấm hàng nghìn) và giờ Việt Nam.
/// Dùng FormatStyle (Sendable) thay vì NumberFormatter/DateFormatter dùng chung.
enum DisplayFormat {
    static let locale = Locale(identifier: "vi_VN")

    /// "15–18 tr/m²", hoặc "18 tr/m²" khi min = max.
    static func price(_ range: PriceRange) -> String {
        let style = Decimal.FormatStyle.number.locale(locale).precision(.fractionLength(0...1))
        let min = range.min.formatted(style)
        let max = range.max.formatted(style)
        return range.min == range.max ? "\(max) tr/m²" : "\(min)–\(max) tr/m²"
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Dưới 1 km: làm tròn 10 m ("850 m"). Từ 1 km: một chữ số thập phân ("1,2 km").
    static func distance(_ meters: Double) -> String {
        if meters < 1_000 {
            let rounded = Int((meters / 10).rounded()) * 10
            return "\(number(rounded)) m"
        }
        let km = (meters / 1_000).formatted(.number.locale(locale).precision(.fractionLength(0...1)))
        return "\(km) km"
    }

    /// dd/MM/yyyy theo giờ Việt Nam.
    static func date(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: Project.vietnamCalendar)
        style.timeZone = Project.vietnamCalendar.timeZone
        return date.formatted(style.day(.twoDigits).month(.twoDigits).year(.defaultDigits))
    }

    static func dateRange(_ interval: DateInterval) -> String {
        "\(date(interval.start)) – \(date(interval.end))"
    }

    static func phase(_ phase: ApplicationPhase) -> String {
        switch phase {
        case .notAnnounced: String(localized: "Chưa công bố")
        case .upcoming(0): String(localized: "Mở hôm nay")
        case .upcoming(let days): String(localized: "Mở sau \(days) ngày")
        case .open(0): String(localized: "Hạn cuối hôm nay")
        case .open(let days): String(localized: "Còn \(days) ngày")
        case .ended: String(localized: "Đã kết thúc")
        }
    }
}
