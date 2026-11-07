import Foundation
import Observation

@MainActor
@Observable
final class EligibilityViewModel {
    /// Hôn nhân hỏi TRƯỚC thu nhập: trần và nghĩa của "thu nhập" (cá nhân hay tổng vợ chồng) phụ thuộc vào nó.
    /// Không còn bước "nơi làm việc": NĐ 54/2026 bỏ điều kiện cư trú/nơi làm việc.
    enum Step: Int, CaseIterable {
        case subject, housing, family, income
    }

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(RepositoryError)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var catalog: LookupCatalog = .empty
    private(set) var rules: [EligibilityRule] = []
    private(set) var step: Step = .subject
    private(set) var result: EligibilityResult?

    var answers = EligibilityAnswers()
    var incomeText = "" {
        didSet { answers.monthlyIncomeMillion = Self.parseIncome(incomeText) }
    }

    /// Chặn số vô lý (gõ nhầm đơn vị đồng thay vì triệu).
    static let maxIncomeMillion: Decimal = 1_000

    private let eligibilityRepository: any EligibilityRepository
    private let lookupRepository: any LookupRepository

    init(eligibility: any EligibilityRepository, lookup: any LookupRepository) {
        self.eligibilityRepository = eligibility
        self.lookupRepository = lookup
    }

    convenience init(container: AppContainer) {
        self.init(eligibility: container.eligibility, lookup: container.lookup)
    }

    var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }
    var stepNumber: Int { step.rawValue + 1 }
    var isFirstStep: Bool { step == .subject }
    var isLastStep: Bool { step == .income }

    var subjects: [EligibilitySubject] { catalog.orderedCases(EligibilitySubject.self) }
    var housingConditions: [HousingCondition] { catalog.orderedCases(HousingCondition.self) }

    var isIncomeInvalid: Bool {
        !incomeText.trimmingCharacters(in: .whitespaces).isEmpty && answers.monthlyIncomeMillion == nil
    }

    var canAdvance: Bool {
        switch step {
        case .subject: answers.subject != nil
        case .housing: answers.housing != nil
        case .family: answers.family != nil
        case .income: answers.monthlyIncomeMillion != nil || isIncomeExempt
        }
    }

    /// Nhóm không xét trần thu nhập (hộ nghèo, lực lượng vũ trang…, theo `income_ceiling_subjects`) → bỏ qua bước thu nhập.
    var isIncomeExempt: Bool {
        EligibilityEvaluator.appliesIncomeCeiling(answers.subject, rules: rules) == false
    }

    func load() async {
        loadState = .loading
        do {
            async let catalog = lookupRepository.catalog()
            async let rules = eligibilityRepository.currentRules()
            (self.catalog, self.rules) = try await (catalog, rules)
            loadState = .ready
        } catch {
            loadState = .failed(error as? RepositoryError ?? .network)
        }
    }

    func next() {
        guard canAdvance else { return }
        if isLastStep {
            result = EligibilityEvaluator.evaluate(answers: answers, rules: rules)
        } else if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }

    func back() {
        if result != nil {
            result = nil
        } else if let previous = Step(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    /// Xóa toàn bộ câu trả lời (chỉ có trong bộ nhớ).
    func restart() {
        answers = EligibilityAnswers()
        incomeText = ""
        result = nil
        step = .subject
    }

    /// Nhận "15", "15,5" hoặc "15.5". Âm, rỗng hoặc vượt `maxIncomeMillion` → nil.
    static func parseIncome(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isNumber || $0 == "." }),
              normalized.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0, value <= maxIncomeMillion
        else { return nil }
        return value
    }
}
