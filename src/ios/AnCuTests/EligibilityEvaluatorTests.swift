import Foundation
import Testing
@testable import AnCu

struct EligibilityEvaluatorTests {
    private static let rules: [EligibilityRule] = [
        rule("income_max_single_million", .number(25)),
        rule("income_max_single_with_child_million", .number(35)),
        rule("income_max_married_million", .number(50)),
        rule("income_ceiling_subjects", .codes(["thu_nhap_thap_do_thi", "cong_nhan", "can_bo_cong_chuc"])),
        rule("min_housing_area_per_person_sqm", .number(15)),
        rule("eligible_subjects", .codes([
            "thu_nhap_thap_do_thi", "cong_nhan", "can_bo_cong_chuc", "luc_luong_vu_trang", "ho_ngheo_can_ngheo", "nhieu_con",
        ])),
        EligibilityRule(key: "disclaimer", value: .text("Chỉ để tham khảo."), legalReference: "", effectiveFrom: .now, isMock: false),
    ]

    private static func rule(_ key: String, _ value: EligibilityRule.Value) -> EligibilityRule {
        EligibilityRule(key: key, value: value, legalReference: "NĐ 136/2026", effectiveFrom: .now, isMock: true)
    }

    private static let eligibleSingle = EligibilityAnswers(
        subject: .industrialWorker, housing: .noHouse, family: .single, monthlyIncomeMillion: 20
    )

    private func level(_ answers: EligibilityAnswers) -> EligibilityLevel {
        EligibilityEvaluator.evaluate(answers: answers, rules: Self.rules).level
    }

    @Test func allCriteriaMetIsLikelyEligible() {
        let result = EligibilityEvaluator.evaluate(answers: Self.eligibleSingle, rules: Self.rules)
        #expect(result.level == .likelyEligible)
        #expect(result.checks.map(\.criterion) == [.subject, .housing, .income])
        #expect(result.usesMockRules)
        #expect(result.disclaimer == "Chỉ để tham khảo.")
    }

    @Test func singleCeilingAtThresholdIsEligibleAboveIsNot() {
        var answers = Self.eligibleSingle
        answers.monthlyIncomeMillion = 25
        #expect(level(answers) == .likelyEligible)
        answers.monthlyIncomeMillion = Decimal(string: "25.1")
        #expect(level(answers) == .notEligible)
    }

    /// NĐ 136/2026: độc thân nuôi con nhỏ có trần riêng (35), cao hơn độc thân (25).
    @Test func singleWithMinorChildUsesHigherCeiling() {
        var answers = Self.eligibleSingle
        answers.monthlyIncomeMillion = 30
        #expect(level(answers) == .notEligible)
        answers.family = .singleWithMinorChild
        #expect(level(answers) == .likelyEligible)
    }

    @Test func marriedUsesCombinedCeiling() {
        var answers = Self.eligibleSingle
        answers.family = .married
        answers.monthlyIncomeMillion = 50
        #expect(level(answers) == .likelyEligible)
        answers.monthlyIncomeMillion = 51
        #expect(level(answers) == .notEligible)
    }

    @Test func owningHouseInProjectProvinceIsNotEligible() {
        var answers = Self.eligibleSingle
        answers.housing = .ownsHouse
        let result = EligibilityEvaluator.evaluate(answers: answers, rules: Self.rules)
        #expect(result.level == .notEligible)
        #expect(result.checks.first { $0.criterion == .housing }?.level == .notEligible)
    }

    @Test func otherSubjectNeedsReviewNotRejection() {
        var answers = Self.eligibleSingle
        answers.subject = .other
        #expect(level(answers) == .needsReview)
    }

    @Test func worstCriterionWins() {
        var answers = Self.eligibleSingle
        answers.subject = .other          // needsReview
        answers.housing = .ownsHouse      // notEligible
        #expect(level(answers) == .notEligible)
    }

    /// Thiếu luật thì không bao giờ kết luận "đủ điều kiện".
    @Test func missingRulesNeverConcludeEligible() {
        let result = EligibilityEvaluator.evaluate(answers: Self.eligibleSingle, rules: [])
        #expect(result.level == .needsReview)
        #expect(result.disclaimer == EligibilityEvaluator.defaultDisclaimer)
        #expect(!result.usesMockRules)
    }

    @Test(arguments: [EligibilitySubject.poorHousehold, .armedForces, .multipleChildren])
    func subjectsWithoutIncomeCeilingNeedReview(_ subject: EligibilitySubject) {
        var answers = Self.eligibleSingle
        answers.subject = subject
        answers.monthlyIncomeMillion = 999
        let result = EligibilityEvaluator.evaluate(answers: answers, rules: Self.rules)
        #expect(result.checks.first { $0.criterion == .subject }?.level == .likelyEligible)
        // Thu nhập cao không bị đánh "chưa đủ" vì nhóm này không xét trần.
        #expect(result.checks.first { $0.criterion == .income }?.level == .needsReview)
        #expect(EligibilityEvaluator.appliesIncomeCeiling(subject, rules: Self.rules) == false)
    }

    @Test func explanationUsesVietnameseDecimalComma() {
        var answers = Self.eligibleSingle
        answers.monthlyIncomeMillion = Decimal(string: "12.5")
        let income = EligibilityEvaluator.evaluate(answers: answers, rules: Self.rules).checks.first { $0.criterion == .income }
        #expect(income?.explanation.contains("12,5") == true)
    }

    @Test func worksWithBundledRules() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let rules = try await container.eligibility.currentRules()
        #expect(EligibilityEvaluator.evaluate(answers: Self.eligibleSingle, rules: rules).level == .likelyEligible)
        var tooHigh = Self.eligibleSingle
        tooHigh.monthlyIncomeMillion = 26
        #expect(EligibilityEvaluator.evaluate(answers: tooHigh, rules: rules).level == .notEligible)
    }
}

@MainActor
struct EligibilityViewModelTests {
    private func make() -> EligibilityViewModel {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        return EligibilityViewModel(container: container)
    }

    @Test(arguments: [("15", "15"), ("12,5", "12.5"), ("12.5", "12.5"), (" 8 ", "8")])
    func parsesIncome(_ input: String, _ expected: String) {
        #expect(EligibilityViewModel.parseIncome(input) == Decimal(string: expected))
    }

    @Test(arguments: ["", "abc", "-3", "1.2.3", "15000000"])
    func rejectsInvalidIncome(_ input: String) {
        #expect(EligibilityViewModel.parseIncome(input) == nil)
    }

    @Test func fullFlowProducesResultAndRestartClearsAnswers() async {
        let viewModel = make()
        await viewModel.load()
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.subjects.count == 7)
        #expect(EligibilityViewModel.Step.allCases.count == 4)

        #expect(!viewModel.canAdvance)
        viewModel.answers.subject = .industrialWorker; viewModel.next()
        viewModel.answers.housing = .noHouse; viewModel.next()
        viewModel.answers.family = .single; viewModel.next()
        #expect(viewModel.step == .income && viewModel.isLastStep)
        viewModel.incomeText = "abc"
        #expect(viewModel.isIncomeInvalid && !viewModel.canAdvance)
        viewModel.incomeText = "20"; viewModel.next()

        #expect(viewModel.result?.level == .likelyEligible)

        viewModel.back()
        #expect(viewModel.result == nil && viewModel.step == .income)

        viewModel.restart()
        #expect(viewModel.answers == EligibilityAnswers())
        #expect(viewModel.step == .subject)
    }

    @Test func subjectWithoutIncomeCeilingCanSkipIncome() async {
        let viewModel = make()
        await viewModel.load()
        viewModel.answers.subject = .poorHousehold; viewModel.next()
        viewModel.answers.housing = .noHouse; viewModel.next()
        viewModel.answers.family = .married; viewModel.next()
        #expect(viewModel.isIncomeExempt && viewModel.canAdvance)
    }
}
