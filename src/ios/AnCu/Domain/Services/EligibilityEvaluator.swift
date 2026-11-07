import Foundation

/// Câu trả lời của người dùng. Chỉ nằm trong bộ nhớ — KHÔNG gửi lên server, không lưu máy (prd.md mục 4.5).
struct EligibilityAnswers: Hashable, Sendable {
    /// Quyết định trần thu nhập áp dụng (NĐ 100/2024 Điều 30 khoản 1, sửa đổi bởi NĐ 136/2026).
    enum Family: String, CaseIterable, Sendable {
        case single
        /// Độc thân đang nuôi con dưới tuổi thành niên — trần cao hơn người độc thân.
        case singleWithMinorChild
        /// Trần áp cho TỔNG thu nhập hai vợ chồng.
        case married
    }

    var subject: EligibilitySubject?
    /// Tình trạng nhà ở TẠI TỈNH/THÀNH CÓ DỰ ÁN.
    var housing: HousingCondition?
    var family: Family?
    /// Triệu VND/tháng, bình quân 12 tháng liền kề. Đã kết hôn: tổng thu nhập hai vợ chồng.
    var monthlyIncomeMillion: Decimal?
}

enum EligibilityLevel: Int, Comparable, Sendable {
    case likelyEligible = 0
    case needsReview = 1
    case notEligible = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct EligibilityCheck: Identifiable, Hashable, Sendable {
    enum Criterion: String, Sendable { case subject, housing, income }

    var id: Criterion { criterion }
    let criterion: Criterion
    let level: EligibilityLevel
    let explanation: String
    /// Điều khoản dẫn chiếu (rỗng khi không có).
    let legalReference: String
}

struct EligibilityResult: Hashable, Sendable {
    let level: EligibilityLevel
    let checks: [EligibilityCheck]
    let disclaimer: String
    /// Có luật chưa đối chiếu văn bản chính thức → UI gắn nhãn.
    let usesMockRules: Bool
}

/// Hàm thuần: cùng câu trả lời + cùng bộ luật → cùng kết quả. Mọi ngưỡng và danh sách đối tượng lấy từ
/// `eligibility_rules`, không hardcode — luật đổi chỉ cần sửa dữ liệu.
/// Kết quả tổng = tiêu chí tệ nhất. Thiếu luật / thiếu câu trả lời → "Cần kiểm tra thêm", không bao giờ kết luận "đủ".
///
/// Từ NĐ 54/2026 + NĐ 136/2026: không còn điều kiện cư trú/nơi làm việc; điều kiện nhà ở xét tại tỉnh có dự án.
enum EligibilityEvaluator {
    enum RuleKey {
        static let incomeSingle = "income_max_single_million"
        static let incomeSingleWithChild = "income_max_single_with_child_million"
        static let incomeMarried = "income_max_married_million"
        /// Nhóm đối tượng xét theo trần thu nhập. Nhóm khác (hộ nghèo, lực lượng vũ trang…) xét theo quy định riêng.
        static let incomeCeilingSubjects = "income_ceiling_subjects"
        static let eligibleSubjects = "eligible_subjects"
        static let minHousingArea = "min_housing_area_per_person_sqm"
        static let disclaimer = "disclaimer"
    }

    static let defaultDisclaimer = "Kết quả chỉ để tham khảo, cơ quan có thẩm quyền xét duyệt mới là căn cứ cuối cùng."

    static func evaluate(answers: EligibilityAnswers, rules: [EligibilityRule]) -> EligibilityResult {
        let byKey = Dictionary(rules.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let checks = [
            subjectCheck(answers, byKey),
            housingCheck(answers, byKey),
            incomeCheck(answers, byKey),
        ]
        var disclaimer = defaultDisclaimer
        if case .text(let text)? = byKey[RuleKey.disclaimer]?.value, !text.isEmpty {
            disclaimer = text
        }
        return EligibilityResult(
            level: checks.map(\.level).max() ?? .needsReview,
            checks: checks,
            disclaimer: disclaimer,
            usesMockRules: rules.contains { $0.isMock }
        )
    }

    /// Nhóm đối tượng có xét trần thu nhập không. `nil` khi thiếu luật.
    static func appliesIncomeCeiling(_ subject: EligibilitySubject?, rules: [EligibilityRule]) -> Bool? {
        guard let subject,
              case .codes(let codes)? = rules.first(where: { $0.key == RuleKey.incomeCeilingSubjects })?.value
        else { return nil }
        return codes.contains(subject.rawValue)
    }

    private static func subjectCheck(_ answers: EligibilityAnswers, _ rules: [String: EligibilityRule]) -> EligibilityCheck {
        let rule = rules[RuleKey.eligibleSubjects]
        let reference = rule?.legalReference ?? ""
        guard let subject = answers.subject, subject != .unknown, case .codes(let codes)? = rule?.value else {
            return EligibilityCheck(criterion: .subject, level: .needsReview,
                                    explanation: "Chưa xác định được nhóm đối tượng.", legalReference: reference)
        }
        if codes.contains(subject.rawValue) {
            return EligibilityCheck(criterion: .subject, level: .likelyEligible,
                                    explanation: "Thuộc nhóm đối tượng được mua nhà ở xã hội.", legalReference: reference)
        }
        // "Đối tượng khác" có thể vẫn thuộc diện nếu khai lại đúng nhóm → không kết luận "chưa đủ" ngay.
        return EligibilityCheck(criterion: .subject, level: subject == .other ? .needsReview : .notEligible,
                                explanation: "Nhóm này không nằm trong danh sách đối tượng được mua nhà ở xã hội. Kiểm tra lại xem bạn có thuộc nhóm khác không.",
                                legalReference: reference)
    }

    private static func housingCheck(_ answers: EligibilityAnswers, _ rules: [String: EligibilityRule]) -> EligibilityCheck {
        let rule = rules[RuleKey.minHousingArea]
        let reference = rule?.legalReference ?? ""
        let area = rule.flatMap { if case .number(let n) = $0.value { n } else { nil } }
        let areaText = area.map { "\(format($0)) m²/người" } ?? "mức tối thiểu"
        switch answers.housing {
        case .noHouse?:
            return EligibilityCheck(criterion: .housing, level: .likelyEligible,
                                    explanation: "Vợ chồng chưa đứng tên nhà ở tại tỉnh/thành có dự án.", legalReference: reference)
        case .under15SqmPerPerson?:
            return EligibilityCheck(criterion: .housing, level: area == nil ? .needsReview : .likelyEligible,
                                    explanation: "Có nhà tại tỉnh/thành có dự án nhưng diện tích bình quân dưới \(areaText).",
                                    legalReference: reference)
        case .ownsHouse?:
            return EligibilityCheck(criterion: .housing, level: .notEligible,
                                    explanation: "Đã có nhà tại tỉnh/thành có dự án với diện tích bình quân từ \(areaText) trở lên.",
                                    legalReference: reference)
        case .unknown?, nil:
            return EligibilityCheck(criterion: .housing, level: .needsReview,
                                    explanation: "Chưa xác định được tình trạng nhà ở.", legalReference: reference)
        }
    }

    private static func incomeCheck(_ answers: EligibilityAnswers, _ rules: [String: EligibilityRule]) -> EligibilityCheck {
        switch appliesIncomeCeiling(answers.subject, rules: Array(rules.values)) {
        case nil:
            return EligibilityCheck(criterion: .income, level: .needsReview,
                                    explanation: "Chưa xác định được điều kiện thu nhập áp dụng.", legalReference: "")
        case false?:
            return EligibilityCheck(criterion: .income, level: .needsReview,
                                    explanation: exemptExplanation(answers.subject), legalReference: "")
        case true?:
            break
        }

        guard let family = answers.family else {
            return EligibilityCheck(criterion: .income, level: .needsReview,
                                    explanation: "Chưa xác định tình trạng hôn nhân để áp trần thu nhập.", legalReference: "")
        }
        let key = switch family {
        case .single: RuleKey.incomeSingle
        case .singleWithMinorChild: RuleKey.incomeSingleWithChild
        case .married: RuleKey.incomeMarried
        }
        guard let rule = rules[key], case .number(let limit) = rule.value else {
            return EligibilityCheck(criterion: .income, level: .needsReview,
                                    explanation: "Chưa có trần thu nhập áp dụng.", legalReference: "")
        }
        guard let income = answers.monthlyIncomeMillion, income >= 0 else {
            return EligibilityCheck(criterion: .income, level: .needsReview,
                                    explanation: "Chưa nhập thu nhập.", legalReference: rule.legalReference)
        }
        let who = family == .married ? "Tổng thu nhập hai vợ chồng" : "Thu nhập"
        if income <= limit {
            return EligibilityCheck(criterion: .income, level: .likelyEligible,
                                    explanation: "\(who) \(format(income)) triệu/tháng, không vượt trần \(format(limit)) triệu.",
                                    legalReference: rule.legalReference)
        }
        return EligibilityCheck(criterion: .income, level: .notEligible,
                                explanation: "\(who) \(format(income)) triệu/tháng, vượt trần \(format(limit)) triệu.",
                                legalReference: rule.legalReference)
    }

    private static func exemptExplanation(_ subject: EligibilitySubject?) -> String {
        switch subject {
        case .poorHousehold?: "Hộ nghèo, cận nghèo xét theo chuẩn nghèo của Chính phủ, không theo trần thu nhập."
        case .armedForces?: "Lực lượng vũ trang xét theo quy định riêng của Bộ Quốc phòng, Bộ Công an."
        default: "Nhóm này không xét theo trần thu nhập thông thường; điều kiện cụ thể cần hỏi Sở Xây dựng hoặc chủ đầu tư."
        }
    }

    /// "15,5" theo tiếng Việt.
    private static func format(_ value: Decimal) -> String {
        value.formatted(.number.locale(Locale(identifier: "vi_VN")).precision(.fractionLength(0...1)))
    }
}
