import UIKit
import UserNotifications

/// APNs + UNUserNotificationCenter (Phase 1 bước 4.4). Cần capability "Push Notifications" (Apple Developer account);
/// thiếu thì `registerForRemoteNotifications` báo lỗi → chỉ log, thông báo vẫn có trong hộp thư trong app.
@MainActor
final class PushNotificationService: NSObject, PushRegistering, UNUserNotificationCenterDelegate {
    static let tokenDefaultsKey = "push.deviceToken"

    private let repository: any PushTokenRepository
    private let router: DeepLinkRouter
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()

    init(repository: any PushTokenRepository, router: DeepLinkRouter, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.router = router
        self.defaults = defaults
        super.init()
        center.delegate = self
        PushBridge.service = self
    }

    /// Token hex của máy (lưu để gỡ khi đăng xuất).
    private(set) var deviceToken: String? {
        get { defaults.string(forKey: Self.tokenDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.tokenDefaultsKey) }
    }

    func requestPermissionAndRegister() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func registerIfAuthorized() async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func unregister() async {
        guard let deviceToken else { return }
        // Lỗi mạng: token cũ còn trên server tới khi APNs báo hết hạn — chấp nhận được, không chặn đăng xuất.
        try? await repository.unregister(token: deviceToken)
    }

    // MARK: Callback từ AppDelegate

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { try? await repository.register(token: token, environment: .current) }   // khách → server từ chối, bỏ qua
    }

    func didFailToRegister(_ error: any Error) {
        print("APNs: không đăng ký được — \(error.localizedDescription)")
    }

    // MARK: UNUserNotificationCenterDelegate

    /// App đang mở vẫn hiện banner (người dùng chủ động theo dõi dự án).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let projectID = (response.notification.request.content.userInfo["project_id"] as? String).flatMap(UUID.init(uuidString:))
        guard let projectID else { return }
        await MainActor.run { router.open(projectID: projectID) }
    }
}

/// AppDelegate nhận token trước khi SwiftUI kịp inject → chuyển qua cầu nối này.
@MainActor
enum PushBridge {
    static weak var service: PushNotificationService?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushBridge.service?.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushBridge.service?.didFailToRegister(error)
    }
}
