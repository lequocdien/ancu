import CoreLocation

/// Vị trí thật cho nút "Gần tôi" (Phase 1 bước 3.3). Chỉ xin quyền "khi dùng app", chỉ lấy MỘT lần khi bấm nút
/// (không theo dõi liên tục) — compliance.md mục 2. Chuỗi giải thích: `NSLocationWhenInUseUsageDescription` (build setting).
struct CoreLocationService: LocationService {
    /// Quá thời gian này coi như không lấy được (trong nhà, GPS yếu).
    var timeout: Duration = .seconds(10)

    func currentLocation() async throws(LocationError) -> GeoPoint {
        let result = await withTaskGroup(of: Result<GeoPoint, LocationError>?.self) { group in
            group.addTask { await OneShotLocationRequest().run() }
            group.addTask { [timeout] in
                try? await Task.sleep(for: timeout)
                return Task.isCancelled ? nil : .failure(.unavailable)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(.unavailable)
        }
        return try result.get()
    }
}

/// `CLLocationManager` phải tạo và dùng trên main thread, delegate giữ continuation tới khi có kết quả.
@MainActor
private final class OneShotLocationRequest: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Result<GeoPoint, LocationError>, Never>?
    /// Kết quả tới trước khi continuation được gắn (vd hủy rất sớm) → giữ lại để trả ngay.
    private var pending: Result<GeoPoint, LocationError>?

    func run() async -> Result<GeoPoint, LocationError> {
        // Hết giờ → task group hủy task này; phải trả continuation, nếu không group chờ mãi.
        await withTaskCancellationHandler {
            await request()
        } onCancel: {
            Task { @MainActor in self.finish(.failure(.unavailable)) }
        }
    }

    private func request() async -> Result<GeoPoint, LocationError> {
        await withCheckedContinuation { continuation in
            if let pending {
                continuation.resume(returning: pending)
                return
            }
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()   // kết quả về `locationManagerDidChangeAuthorization`
            case .denied, .restricted:
                finish(.failure(.permissionDenied))
            default:
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(.failure(.permissionDenied))
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        finish(.success(GeoPoint(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        finish(.failure(denied ? .permissionDenied : .unavailable))
    }

    private func finish(_ result: Result<GeoPoint, LocationError>) {
        guard let continuation else {
            if pending == nil { pending = result }
            return
        }
        continuation.resume(returning: result)
        self.continuation = nil
        manager.delegate = nil
    }
}
