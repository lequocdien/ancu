import Testing
@testable import AnCu

/// Kiểm tra pipeline test chạy được. Sẽ thay bằng EligibilityEvaluatorTests, MapperTests (spec mục 11, bước 3).
struct SmokeTests {
    @Test func appModuleLoads() {
        #expect(RootTabView.Tab.map != RootTabView.Tab.account)
    }
}
