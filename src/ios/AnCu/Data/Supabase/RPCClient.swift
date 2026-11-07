import Foundation

/// Cổng gọi RPC (Postgres function) — mỏng nhất có thể để repository test được bằng fake, không cần mạng.
/// Quy ước: chỉ ném `RepositoryError` hoặc `CancellationError`.
protocol RPCClient: Sendable {
    /// Trả raw JSON; repository tự decode bằng `RPCDecoder` để dùng lại DTO dùng chung.
    func call(_ function: String, params: some Encodable & Sendable) async throws -> Data
}

/// RPC không tham số.
struct NoRPCParams: Encodable, Sendable {}

extension RPCClient {
    func call<Response: Decodable>(
        _ function: String,
        params: some Encodable & Sendable = NoRPCParams(),
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await call(function, params: params)
        do {
            return try RPCDecoder.decode(Response.self, from: data)
        } catch {
            throw RepositoryError.decoding
        }
    }
}

enum RPCDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
