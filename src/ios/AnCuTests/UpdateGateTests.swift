import Foundation
import Testing
@testable import AnCu

struct AppVersionTests {
    @Test(arguments: [("1", "1.0.0"), ("1.2", "1.2.0"), ("1.2.3", "1.2.3"), (" 0.10.0 ", "0.10.0")])
    func parses(_ input: String, _ expected: String) {
        #expect(AppVersion(input)?.description == expected)
    }

    @Test(arguments: ["", "1.2.3.4", "a.b", "1..2", "-1.0", "v1.0"])
    func rejects(_ input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test func comparesNumericallyNotLexically() throws {
        #expect(try #require(AppVersion("0.9.0")) < #require(AppVersion("0.10.0")))
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
        #expect(try #require(AppVersion("2.0.0")) > #require(AppVersion("1.99.99")))
    }

    @Test func currentBuildMatchesMarketingVersion() {
        #expect(AppVersion.current == AppVersion(0, 1, 0))
    }
}

private struct StubConfigRepository: ConfigRepository {
    let result: Result<ClientConfig, RepositoryError>
    func clientConfig() async throws -> ClientConfig { try result.get() }
}

@MainActor
struct UpdateGateViewModelTests {
    private func make(_ result: Result<ClientConfig, RepositoryError>, current: AppVersion = AppVersion(1, 0, 0)) -> UpdateGateViewModel {
        UpdateGateViewModel(repository: StubConfigRepository(result: result), current: current)
    }

    private func config(_ min: AppVersion) -> ClientConfig {
        ClientConfig(minSupportedVersion: min, appStoreURL: nil)
    }

    @Test func blocksOnlyWhenBelowMinimum() async {
        let older = make(.success(config(AppVersion(1, 1, 0))))
        await older.check()
        #expect(older.requiresUpdate)

        let equal = make(.success(config(AppVersion(1, 0, 0))))
        await equal.check()
        #expect(!equal.requiresUpdate)
    }

    @Test func networkErrorNeverBlocks() async {
        let viewModel = make(.failure(.network))
        await viewModel.check()
        #expect(!viewModel.requiresUpdate)
    }

    @Test func mockDefaultDoesNotBlockCurrentBuild() async throws {
        let config = try await MockConfigRepository().clientConfig()
        #expect(!config.requiresUpdate(current: .current))
    }

    @Test func supabaseRepositoryMapsRPC() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("client_config", json: #"{"min_supported_version": "0.2", "app_store_url": null}"#)
        let config = try await SupabaseConfigRepository(rpc: rpc).clientConfig()
        #expect(config == ClientConfig(minSupportedVersion: AppVersion(0, 2, 0), appStoreURL: nil))
        #expect(rpc.lastParams("client_config")?["platform"] as? String == "ios")

        rpc.respond("client_config", json: #"{"min_supported_version": "mới nhất", "app_store_url": null}"#)
        await #expect(throws: RepositoryError.decoding) { try await SupabaseConfigRepository(rpc: rpc).clientConfig() }
    }
}
