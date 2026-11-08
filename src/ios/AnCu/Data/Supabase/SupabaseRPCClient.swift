import Foundation
import Supabase

/// File DUY NHẤT (cùng `AppContainer`) biết tới Supabase SDK ở tầng đọc dữ liệu.
struct SupabaseRPCClient: RPCClient {
    let client: SupabaseClient

    func call(_ function: String, params: some Encodable & Sendable) async throws -> Data {
        do {
            return try await client.rpc(function, params: params).execute().data
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}

/// Lỗi SDK/HTTP → `RepositoryError` (architecture.md 5.5). Hủy Task giữ nguyên `CancellationError`.
enum SupabaseErrorMapper {
    static func map(_ error: any Error) -> any Error {
        switch error {
        case is CancellationError:
            return error
        case let error as RepositoryError:
            return error
        case let error as PostgrestError:
            return map(postgrestCode: error.code)
        case let error as HTTPError:
            return map(status: error.response.statusCode)
        case let error as URLError:
            return error.code == .cancelled ? CancellationError() : RepositoryError.network
        case is DecodingError, is EncodingError:
            return RepositoryError.decoding
        default:
            return RepositoryError.network
        }
    }

    /// Mã SQLSTATE / PostgREST: https://postgrest.org/en/stable/references/errors.html
    static func map(postgrestCode code: String?) -> RepositoryError {
        switch code {
        case "P0002", "PGRST116": .notFound
        case "AC429": .rateLimited   // giới hạn tự đặt trong RPC (vd report_data 10 lần/24h)
        case "AC403": .outsideServiceArea   // vị trí ngoài vùng MVP (create_saved_place, suggest_project)
        case "AC409": .limitReached         // vượt số lượng cho phép (200 địa điểm/tài khoản)
        case "28000": .unauthorized   // RPC tự kiểm tra auth.uid()
        case "42501", "PGRST301", "PGRST302", "PGRST303": .unauthorized
        // Lớp 22 (data exception) / 23 (vi phạm ràng buộc): dữ liệu gửi lên sai — thử lại vô ích.
        case let code? where code.hasPrefix("22") || code.hasPrefix("23"): .decoding
        default: .network
        }
    }

    static func map(status: Int) -> RepositoryError {
        switch status {
        case 401, 403: .unauthorized
        case 404: .notFound
        case 429: .rateLimited
        default: .network
        }
    }
}
