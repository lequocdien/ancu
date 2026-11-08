import Foundation
import Testing
@testable import AnCu

struct MapperTests {
    private func projectDTO(
        status: String = "nhan_ho_so",
        start: String? = "2026-11-01",
        end: String? = "2026-11-18",
        priceMin: Double? = 22.5,
        priceMax: Double? = 24,
        sourceUrl: String = "https://mock.ancu.vn/x"
    ) -> ProjectDTO {
        ProjectDTO(
            id: UUID(), name: "A", address: "B", wardCode: nil, serviceArea: "tp_hcm",
            location: PointDTO(lat: 10.8, lng: 106.7), status: status, legalStatus: "du_dieu_kien_ban",
            applicationStart: start, applicationEnd: end, priceMin: priceMin, priceMax: priceMax,
            priceIsEstimated: false, unitCount: 100, developer: nil, coverImageUrl: nil,
            sourceUrl: sourceUrl, verifiedAt: "2026-11-02"
        )
    }

    @Test func mapsValidProject() throws {
        let project = try DTOMapper.project(projectDTO(), shift: .none)
        #expect(project.status == .acceptingApplications)
        #expect(project.price?.min == Decimal(string: "22.5"))
        #expect(project.applicationWindow != nil)
    }

    @Test func unknownStatusDoesNotFail() throws {
        #expect(try DTOMapper.project(projectDTO(status: "trang_thai_moi"), shift: .none).status == .unknown)
    }

    @Test func rejectsBrokenContracts() {
        #expect(throws: RepositoryError.decoding) { try DTOMapper.project(projectDTO(start: "2026-11-01", end: nil), shift: .none) }
        #expect(throws: RepositoryError.decoding) { try DTOMapper.project(projectDTO(start: "2026-11-20", end: "2026-11-01"), shift: .none) }
        #expect(throws: RepositoryError.decoding) { try DTOMapper.project(projectDTO(priceMin: 30, priceMax: 20), shift: .none) }
        #expect(throws: RepositoryError.decoding) { try DTOMapper.project(projectDTO(sourceUrl: "khong-phai-url"), shift: .none) }
        #expect(throws: RepositoryError.decoding) { try DTOMapper.project(projectDTO(start: "01/11/2026"), shift: .none) }
    }

    @Test func dateShiftMovesWindow() throws {
        let shifted = try DTOMapper.project(projectDTO(), shift: DateShift(days: 10))
        let start = try #require(shifted.applicationWindow?.start)
        #expect(start == Project.vietnamCalendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
    }

    @Test func dateShiftFromAnchor() {
        let anchor = MockDataStore.anchorDate
        let later = Project.vietnamCalendar.date(byAdding: .day, value: 40, to: anchor)!
        #expect(DateShift(anchor: anchor, now: later).days == 40)
    }

    @Test func eligibilityRuleValueTypes() throws {
        let number = EligibilityRuleDTO(ruleKey: "k", valueType: "number", valueNumber: 15, valueText: nil, valueCodes: nil,
                                        legalReference: "x", effectiveFrom: "2024-08-01", isMock: true)
        #expect(try DTOMapper.eligibilityRule(number).value == .number(15))

        let missing = EligibilityRuleDTO(ruleKey: "k", valueType: "codes", valueNumber: nil, valueText: nil, valueCodes: nil,
                                         legalReference: "x", effectiveFrom: "2024-08-01", isMock: true)
        #expect(throws: RepositoryError.decoding) { try DTOMapper.eligibilityRule(missing) }
    }
}
