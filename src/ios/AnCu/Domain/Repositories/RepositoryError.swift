import Foundation

/// Lỗi chung cho mọi backend (Mock, Supabase, .NET). Mỗi repository tự map lỗi riêng
/// (PostgrestError, HTTP 4xx/5xx…) về đây để ViewModel không phụ thuộc backend.
enum RepositoryError: Error, Equatable, Sendable {
    /// Cần đăng nhập (hoặc phiên hết hạn).
    case unauthorized
    case notFound
    case rateLimited
    /// Mất mạng, timeout, server 5xx.
    case network
    /// Dữ liệu trả về không đúng contract (hoặc dữ liệu gửi đi không hợp lệ).
    case decoding
    /// Vị trí ngoài vùng app hỗ trợ (server `AC403`).
    case outsideServiceArea
    /// Vượt giới hạn số lượng, vd 200 địa điểm/tài khoản (server `AC409`).
    case limitReached
}
