import Network
import Observation

/// Trạng thái mạng cho UI (Phase 1 bước 5.2): hiện "Đang ngoại tuyến" và tự tải lại khi có mạng.
/// Chỉ để hiển thị — không chặn gọi API (NWPath có thể báo sai ngắn hạn; lỗi thật vẫn đi qua `RepositoryError.network`).
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init(startsMonitoring: Bool = true) {
        guard startsMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "vn.ancu.connectivity"))
    }

    deinit {
        monitor.cancel()
    }
}
