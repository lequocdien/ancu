# Kiến trúc hệ thống (System Architecture) - An Cư

> Nguồn: Đặc tả sản phẩm v2 (`01-ideas/source/`) — mục 2, 4.3, 4.4, 5 (nguyên tắc). Mục 5 (Repository Pattern) bổ sung ngày 2026-11-06.

## 1. Tech Stack Overview

Bản đầu chỉ làm iOS bằng SwiftUI + MapKit để ra mắt nhanh, chi phí thấp. Backend Supabase dùng chung cho iOS, Android và trang web công khai (cả hai làm sau).

| Thành phần | Lựa chọn | Ghi chú |
| --- | --- | --- |
| Giao diện iOS | SwiftUI + MapKit | Apple Maps miễn phí, bottom sheet native, gom cụm ghim sẵn |
| Backend | Supabase: PostgreSQL + PostGIS, Auth, Storage, Realtime, Edge Functions | Dùng chung mọi nền tảng |
| Đăng nhập | Apple, Google, Facebook + OTP số điện thoại | OTP để đáp ứng Nghị định 147 (`compliance.md`) |
| Ảnh | Trình chọn ảnh hệ thống (PhotosPicker) | Nén + **xóa GPS EXIF** trước khi upload |
| Thông báo đẩy | APNs (Android sau: FCM) | Server gửi khi dữ liệu dự án thay đổi |
| Kiểm duyệt | Server-side: luật + Gemini API | App chỉ báo lỗi sớm, không tự quyết định duyệt |
| Trang web công khai *(giai đoạn sau)* | Mỗi dự án một trang | Chia sẻ Zalo/Facebook, SEO, phục vụ người dùng Android |
| Giám sát | Crashlytics + một công cụ analytics | Phễu: mở app → bấm ghim → lưu → đăng nhập → bật thông báo |

## 2. Chiến lược iOS trước, Android sau

Đánh đổi lớn nhất của sản phẩm: người mua NOXH phần đông dùng Android, nhưng iOS-first cho phép kiểm chứng nhanh với codebase nhỏ, trải nghiệm native tốt. Để không thành điểm nghẽn:

- **Trang web công khai cho từng dự án**: làm sau bản iOS đầu tiên (chưa nằm trong MVP).
- **Dồn logic về server:** tính khoảng cách, kiểm duyệt, luật điều kiện, gửi thông báo đều ở backend. App chỉ hiển thị → Android không viết lại nghiệp vụ.
- **Dữ liệu bản đồ ở dạng chuẩn** (GeoJSON, WGS84), không phụ thuộc MapKit.
- **Điều kiện bắt đầu Android (chốt 2026-11-07):** retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3).
- Android dự kiến: Kotlin + Jetpack Compose, Google Maps SDK hoặc Vietmap.

## 3. Bản đồ và vấn đề chủ quyền

MapKit miễn phí, mượt, nhưng cần kiểm tra cách Apple Maps hiển thị Hoàng Sa, Trường Sa với người dùng VN (Luật Đo đạc và Bản đồ). App tập trung đô thị nên ít khi thấy vùng biển, nhưng vẫn là rủi ro khi bị kiểm tra/phản ánh.

Phương án dự phòng:
- Phủ lớp bản đồ nền nhà cung cấp trong nước (Vietmap) lên MapKit (`MKTileOverlay`), hoặc
- Giới hạn vùng hiển thị (`cameraBounds`) trong phạm vi các thành phố có dữ liệu.
- Android: chọn nhà cung cấp hiển thị đúng chủ quyền ngay từ đầu.

**Quyết định 2026-11-07 (Phase 1 bước 0.4):** dùng `cameraBounds` — khóa tâm camera trong khung vùng MVP và giới hạn khoảng cách zoom out (600 km; nửa đường chéo khung nhìn ≈ 0,24 × khoảng cách → ~145 km, quần đảo gần nhất cách mép khung ~490 km), để không kéo được ra Biển Đông. Khung lưu ở `MapRegion.allowedArea` (mở rộng khi thêm Hà Nội). Vẫn cần kiểm tra mắt thường trên máy thật trước khi phát hành.

**Cập nhật 2026-11-08 (vùng phục vụ = TP.HCM + 4 tỉnh mới):** khung tâm camera nới tới Tây Ninh / Đồng Tháp / Lâm Đồng (Lâm Đồng mới gồm Bình Thuận — **gần Trường Sa hơn**). Ràng buộc giữ nguyên: test `MapBoundsTests` đòi mọi tâm camera cách các điểm Hoàng Sa/Trường Sa > `maxCameraDistance × visibleHalfDiagonalRatio` → mép đông của khung và zoom tối đa do test quyết định. Côn Đảo (TP.HCM mới) nằm ngoài khung tâm camera — chấp nhận (không có dự án NOXH).

## 4. Luồng xử lý phía server

### 4.1. Pipeline kiểm duyệt bình luận (Edge Function)

```text
Comment submitted ──► [1] Chuẩn hóa ──► [2] Luật ──► [3] Gemini ──► [4] Trust ──► status
                                           │ rõ ràng vi phạm
                                           └──► rejected
Sau khi publish: [5] ≥3 reports ──► tự ẩn, chờ kiểm duyệt viên
```

1. **Chuẩn hóa văn bản:** bỏ dấu, quy đổi chữ số viết bằng chữ ("không chín tám"), bỏ ký tự chèn giữa số ("0.9.8", "0 9 8"), quy đổi emoji số.
2. **Luật (regex + từ khóa):** số điện thoại, Zalo ID, link, từ khóa "suất ngoại giao", "tiền chênh", "bao đậu", "cam kết 100%". Ra **điểm rủi ro**, chỉ trường hợp rất rõ mới `rejected`.
3. **AI (Gemini):** phân loại văn bản + ảnh (số điện thoại, mã QR trong ảnh). Output JSON theo schema cố định (`label`, `reasons`). Nội dung bình luận luôn xử lý như **dữ liệu, không phải chỉ dẫn** (chống prompt injection). Chỉ gọi AI khi bước luật chưa quyết được (tiết kiệm chi phí).
4. **Độ tin cậy tài khoản:** tài khoản mới → `pending`; ≥ 5 bình luận đã duyệt + bước 2, 3 sạch → tự duyệt.
5. **Báo cáo cộng đồng:** ≥ 3 báo cáo → tự ẩn, chờ xem lại.

Ngưỡng 5 / 3 / 10 lưu thành cấu hình. Ảnh nằm ở private bucket tới khi `approved`. Realtime chỉ phát `approved`.

### 4.2. Thông báo

```text
UPDATE projects ──trigger──► project_updates ──► (worker/Edge Function) ──► APNs / FCM
                                                    └─ dedupe: ≤ 1 push/ngày/dự án
```

### 4.3. Nguyên tắc chung
- **Logic nằm ở server:** mọi quy tắc nghiệp vụ trong database hoặc Edge Functions để Android và web dùng lại.
- **Tải theo vùng nhìn:** chỉ lấy dự án/tuyến trong khung bản đồ; tuyến được giản lược điểm theo zoom.
- **Không để khóa quản trị (service role) trong app**, bật rate limit.

## 5. Repository Pattern phía iOS (chuẩn bị cho khả năng chuyển Supabase → .NET)

### 5.0. Quyết định (2026-11-07): ở lại Supabase lâu dài

- Không có kế hoạch chuyển .NET. Phạm vi Repository Pattern giữ ở mức mục 5.4: protocol + DTO tách khỏi domain + composition root. Mục 5.1–5.3 giữ làm tham khảo nếu sau này xem xét lại.
- **Vendor lock-in thấp ở tầng dữ liệu**: Postgres + PostGIS chuẩn, logic nghiệp vụ đặt trong SQL function/trigger (chạy được ở Postgres bất kỳ). Điểm khóa thật sự là Auth, Storage, Realtime và Edge Functions — chấp nhận đổi lấy tốc độ ra MVP.
- **Đường lui**: Supabase là mã nguồn mở, tự host được (Docker) nếu chi phí managed tăng quá mức. Vẫn ưu tiên SQL function hơn Edge Function cho logic có thể đặt trong DB.
- Force-update (`min_supported_version`) vẫn làm (phase-1 task 4.8) — cần cho mọi thay đổi contract, không riêng chuyện đổi backend.

**Mục tiêu:** khi chuyển backend từ Supabase sang .NET (ASP.NET Core) sau này, View (bản đồ) và ViewModel không phải sửa. Áp dụng ngay từ Phase 1.

### 5.1. Ý tưởng gốc

```swift
// Bước 1: Protocol
protocol ProjectRepository {
    func getProjects() async throws -> [Project]
}

// Bước 2: Phase 1 dùng Supabase
class SupabaseProjectRepository: ProjectRepository {
    func getProjects() async throws -> [Project] {
        return try await AppEnvironment.shared.client.from("projects").select().execute().value
    }
}

// Bước 3: Sau này chuyển sang .NET — chỉ viết thêm class mới
class DotNetProjectRepository: ProjectRepository {
    func getProjects() async throws -> [Project] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.ancu.vn/api/v1/projects")!)
        return try JSONDecoder().decode([Project].self, from: data)
    }
}
```

### 5.2. Hiệu chỉnh để abstraction không "rò rỉ"

Bản gốc đúng hướng nhưng sẽ vỡ nếu giữ nguyên, vì các lý do sau:

| Vấn đề | Hệ quả nếu bỏ qua | Cách xử lý |
| --- | --- | --- |
| `getProjects()` không tham số | Mâu thuẫn với "tải theo vùng nhìn" → phải đổi protocol sau, kéo theo sửa ViewModel | Protocol nhận `MapRegion` + `ProjectFilter` ngay từ đầu |
| Dùng chung `Project` làm DTO và domain model | Tên cột Supabase (`snake_case`, `geography` dạng GeoJSON/WKB) rò lên UI; .NET trả `camelCase` | Domain model thuần Swift; mỗi repository tự có DTO + mapper |
| `AppEnvironment.shared` singleton bên trong repository | Khó test, khó swap | Inject `SupabaseClient` qua `init`; chọn implementation ở composition root |
| Chỉ abstract đọc dữ liệu | Auth, Storage (upload ảnh), Realtime (bình luận) vẫn gọi Supabase SDK trực tiếp → vẫn phải sửa ViewModel | Abstract cả `AuthService`, `MediaUploader`, `CommentFeed` (trả `AsyncThrowingStream`) |
| Lỗi đặc thù backend (`PostgrestError` vs HTTP 4xx/5xx) | ViewModel phải `catch` theo kiểu của từng backend | Map về `enum RepositoryError` chung |
| `URL(string:)!`, `class` không `Sendable` | Crash runtime; cảnh báo strict concurrency Swift 6 | URL từ config; `final class ...: Sendable` hoặc `actor` |

Phiên bản đề xuất:

```swift
// Domain/ — không import Supabase
struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let status: ProjectStatus
    let applicationWindow: DateInterval?
    let priceRange: ClosedRange<Decimal>?
    let sourceURL: URL
    let verifiedAt: Date
}

enum RepositoryError: Error { case unauthorized, notFound, rateLimited, network(underlying: Error), decoding }

protocol ProjectRepository: Sendable {
    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project]
    func project(id: Project.ID) async throws -> ProjectDetail   // gồm khoảng cách tới ga/nút giao
}

// Data/Supabase/
final class SupabaseProjectRepository: ProjectRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project] {
        do {
            let rows: [ProjectRow] = try await client
                .rpc("projects_in_bbox", params: BBoxParams(region, filter))  // RPC, không query bảng trực tiếp
                .execute().value
            return rows.map(Project.init(row:))
        } catch { throw RepositoryError(supabase: error) }
    }
    // ...
}

// App/CompositionRoot.swift — điểm duy nhất biết backend nào đang dùng
@MainActor
enum CompositionRoot {
    static func makeProjectRepository(config: AppConfig) -> ProjectRepository {
        switch config.backend {
        case .supabase: SupabaseProjectRepository(client: .init(url: config.supabaseURL, key: config.anonKey))
        case .dotnet:   DotNetProjectRepository(baseURL: config.apiBaseURL, session: .shared)
        }
    }
}
```

**Gợi ý quan trọng:** gọi Supabase qua **RPC (Postgres function)** thay vì `.from("projects").select()`. RPC chính là "API contract" — sau này .NET expose endpoint cùng shape (`GET /api/v1/projects?bbox=...`), mapper hai phía gần như giống nhau. Query bảng trực tiếp thì contract chính là schema DB, rất khó giữ khi đổi backend.

### 5.3. Repository Pattern chỉ bảo vệ phía app — backend vẫn phải tính

Spec chủ trương "dồn logic về server" (RLS, trigger, PostGIS, Edge Functions). Khi chuyển sang .NET:

| Thành phần Supabase | Khi chuyển .NET | Ghi chú |
| --- | --- | --- |
| Postgres + PostGIS, SQL functions, trigger `project_updates` | **Giữ nguyên** (.NET dùng chung DB: Npgsql + NetTopologySuite) | Lý do nên đặt logic trong SQL function thay vì Edge Function |
| RLS | Chuyển thành authorization ở .NET (policy-based) hoặc giữ RLS + set `request.jwt.claims` | Rủi ro cao nhất — dễ hổng quyền khi viết lại |
| Edge Functions (Deno/TS): kiểm duyệt, push | Viết lại bằng .NET (Worker Service / Azure Functions / AWS Lambda) | Pipeline kiểm duyệt hợp với queue: Azure Service Bus hoặc SQS |
| Supabase Auth (JWT) | .NET validate JWT của Supabase trong giai đoạn chuyển tiếp, sau đó mới thay IdP (Entra External ID / Cognito / Duende) | Tránh bắt toàn bộ người dùng đăng nhập lại |
| Storage | Azure Blob / S3 + signed URL | Giữ cơ chế private → public sau duyệt |
| Realtime | SignalR (Azure SignalR Service) / API Gateway WebSocket | Abstraction `CommentFeed` phía app che phần này |

**Edge case dễ bị bỏ sót — các bản app cũ:** sau khi chuyển .NET, người dùng chưa cập nhật app vẫn gọi Supabase trực tiếp. Cần chuẩn bị từ Phase 1:
- **Remote config** (Firebase Remote Config hoặc bảng `app_config`) để bật/tắt backend và **force update** theo `min_supported_version`.
- Giữ Supabase chạy song song (hoặc chỉ read-only) cho tới khi tỷ lệ bản cũ đủ thấp.
- Trang web công khai (khi có) cũng là một client — cùng chiến lược.

### 5.4. Khi nào KHÔNG cần làm quá mức
- Nếu chưa có kế hoạch .NET cụ thể: chỉ cần **protocol + DTO tách khỏi domain + composition root**. Chưa cần viết `DotNetProjectRepository`, chưa cần remote config backend switch (nhưng force-update thì nên có từ đầu).
- Đừng thêm generic `Repository<T>` — mỗi aggregate một protocol theo use case (Project, Infrastructure, Bookmark, Comment, Eligibility) là đủ.

### 5.5. Nối Supabase — bước 1: dữ liệu công khai (2026-11-07)
Dependency đã duyệt: `supabase-swift` (SPM, product `Supabase`, từ 2.55.0, up to next major).

| Quyết định | Lý do / trade-off |
| --- | --- |
| Bước 1 chỉ làm 4 repository **đọc công khai**: Project, Infrastructure, Lookup, Eligibility. Bookmark, Notification, DataReport, Auth vẫn Mock | Đọc công khai không cần đăng nhập → xác minh contract RPC end-to-end trước. Auth cần Sign in with Apple (Apple Developer account) — làm bước 2. Container lai được vì `seed.sql` sinh từ cùng mock JSON → id dự án trùng nhau |
| Repository phụ thuộc protocol `RPCClient` mỏng (`call(function, params) → Decodable`), không phụ thuộc trực tiếp `SupabaseClient` | Unit test repository bằng fake trả JSON fixture, không cần mạng. Chỉ `SupabaseRPCClient` import SDK. Đổi sang .NET: viết `HTTPRPCClient` hoặc repository riêng |
| `SupabaseRPCClient` lấy **raw `Data`** rồi tự decode bằng decoder của app (`convertFromSnakeCase`) | Dùng lại nguyên DTO + mapper của Mock (chuyển sang `Data/Shared/`). Không phụ thuộc decoder mặc định của SDK |
| Map lỗi tập trung trong `SupabaseRPCClient`: `P0002` → `.notFound`, `42501`/JWT → `.unauthorized`, 429 → `.rateLimited`, `URLError`/5xx → `.network`, lỗi decode → `.decoding`; hủy Task → giữ `CancellationError` | ViewModel chỉ thấy `RepositoryError` (5.2) |
| Chọn backend ở composition root, ưu tiên: env `ANCU_SUPABASE_URL/KEY` → DEBUG `-Backend local\|mock` → Info.plist (từ `Config/Debug|Release.xcconfig` + `Secrets-*.xcconfig` gitignore) → Mock | Bản build thật cấu hình qua xcconfig, CI sinh `Secrets-Release.xcconfig` từ secret. Key nằm trong app là công khai → chỉ nhận publishable/anon; `sb_secret_`/JWT `service_role` bị từ chối (về Mock) |
| Phường/xã đọc qua RPC `administrative_units_all()` (migration 05), không đọc bảng trực tiếp | Cột `geography` qua PostgREST ra WKB hex, không phải `{lat, lng}` — giữ quy tắc "contract = RPC" |
| Integration test gọi stack local, **tự bỏ qua** khi không có `ANCU_SUPABASE_URL` | CI/máy không có Docker vẫn xanh. Chạy: `TEST_RUNNER_ANCU_SUPABASE_URL=… xcodebuild test` |

Rủi ro còn lại: dữ liệu thật không qua `DateShift` → trạng thái "đang mở" phụ thuộc ngày trong DB, không tự trượt như mock.

### 5.6. Quyết định Phase 1 (2026-11-07)

Dữ liệu dùng mock cho tới khi có pipeline crawl (giai đoạn sau). Chưa có Apple Developer account → làm sẵn mọi thứ, bật bằng cấu hình khi có.

| Mục | Quyết định | Trade-off / lý do |
| --- | --- | --- |
| 4.1 Đăng nhập | Supabase Auth: **email OTP** (chạy được ngay, local nhận mail qua Mailpit) + **Apple** (`signInWithIdToken`, cần capability) + **Google, Facebook** qua OAuth web (`ASWebAuthenticationSession`, không thêm SDK). Callback `ancu://login-callback` | Không thêm SDK Google/Facebook → ít dependency, nhưng UX là màn web thay vì native. Có Google/Facebook → App Store bắt buộc có Sign in with Apple |
| 4.2, 4.5, 3.6, 4.7 | `SupabaseBookmarkRepository` (khách lưu local → `merge_guest_bookmarks` khi đăng nhập), `SupabaseNotificationRepository`, `SupabaseDataReportRepository`, xóa tài khoản = RPC `delete_my_account` | Không cần Edge Function `delete-account`: RPC `security definer` xóa `auth.users` (cascade) là đủ khi chưa có Storage |
| 4.4 Push | App: xin quyền, đăng ký APNs, upsert `push_tokens`. Server: Database Webhook `notifications` INSERT → Edge Function `send-push` (APNs HTTP/2, JWT ES256). **Dry-run** khi thiếu key `.p8` | Dedupe ≤ 1/ngày/dự án đã ở trigger fan-out, function không phải lo |
| 4.8 Force update | RPC `client_config()` trả `min_supported_version`; app so phiên bản → màn chặn có nút mở App Store | Lỗi mạng **không** chặn app (fail-open) — chặn nhầm tệ hơn bỏ sót một lần |
| 5.1 Crash + analytics | Tự làm, **không thư viện**: bảng `analytics_events` (chỉ insert, không ai đọc qua API), app gửi theo lô; crash/hang qua **MetricKit**. Định danh = UUID cài đặt ngẫu nhiên (không IDFA → không cần ATT). Retention W4 = SQL view | Không phụ thuộc bên thứ ba, dữ liệu ở lại Supabase. Đổi lại: không có dashboard sẵn, crash chỉ có sau ~24h (đặc tính MetricKit) |
| 3.2 Giản lược tuyến | `routes(types, tolerance_degrees)` với tolerance theo `longitudeDelta` của camera, phân bậc để cache | Tránh gọi lại server mỗi lần zoom |
| Highlight vùng (2026-11-07) | Chọn chip vùng → tô nhạt (16%) + viền **mảnh nét đứt 1,5pt** (bỏ halo trắng 7pt theo góp ý 2026-11-07 — viền dày lấn tuyến), camera ôm trọn vùng (`.rect`, lề 30%). Ranh giới **mock giản lược** (`service_areas.geojson`, `is_mock`), RPC `service_area_boundary(code, tolerance)` | Mock đủ nhận biết hình dạng, không dùng xác định địa giới; thay bằng nguồn chính thức khi crawl. Phải nâng `maxCameraDistance` 250 → 600 km mới ôm được một tỉnh ở màn dọc |
| Staging dữ liệu + crawler tách biệt (2026-11-08) | Schema `ingest` (không mở qua API, thu hồi quyền anon/authenticated): `batches`, `route/node/project_candidates` (cột như bảng chính nhưng lỏng hơn + `raw`, `evidence_url`, `review_status`, `validation_errors`), view `pending_review` (đổi trường nào, dời bao nhiêu mét). Duyệt: `ingest.approve_*` / `approve_batch` (SECURITY DEFINER, kiểm tra người duyệt; upsert theo id trong 1 transaction; `verified_at` = ngày duyệt; đợt `silent` bỏ qua thông báo qua cờ phiên `ancu.silent_ingest`). Crawler: `src/crawler/` project Python riêng (httpx, beautifulsoup4, pdfplumber — đã duyệt), **không có thông tin kết nối DB**, chỉ xuất `features.geojson`; `src/data` (thư viện chuẩn) kiểm tra + sinh `stage.sql`. Cột `geometry_accuracy` cho tuyến/ga | Thay review diff Git: crawler ghi được, ràng buộc DB/PostGIS kiểm ngay, trang quản trị sau dùng lại hàm duyệt, audit trong DB. Bảng nháp theo từng loại (không JSONB chung) để giữ kiểm tra hình học. Crawler không giữ key → parser/thư viện bị lỗi hay độc cũng không ghi được DB. Duyệt cả đợt là all-or-nothing (bản sai phải từ chối trước) — tránh trạng thái nửa vời. `service_role`/`postgres` vẫn ghi thẳng được bảng chính → quy ước bắt buộc, không phải chặn kỹ thuật |
| Màu tuyến theo loại (2026-11-07) | Mọi tuyến cùng loại một màu, lấy từ `route_types.color_hex` (đổi từ server): Metro xanh dương `#2563EB`, Vành đai cam `#F97316`, Cao tốc hồng đậm `#DB2777`, Quốc lộ xám `#64748B`. **Màu = loại, kiểu nét = trạng thái; mọi tuyến cùng độ rộng 4pt** (đã khai thác liền · đang thi công gạch dài 12–4 (đã thử gạch chấm + bù thị giác, quay lại theo lựa chọn của bạn) · quy hoạch gạch ngắn 4–6 mờ 60%; nét đứt đầu vuông — đầu tròn lấp kín khe). Trước đó độ dày 5pt/3pt bị đọc là "line không đều" khi cùng màu. Chạm vào tuyến → tuyến nổi bật (halo trắng), tuyến khác mờ 30%, thẻ tên + trạng thái + năm (`RouteHitTester`, bán kính 22pt quy ra mét theo zoom) | Người mua cần biết "gần metro hay cao tốc", không cần nhận diện từng tuyến; khớp chip lọc theo loại. Bỏ đỏ (cạnh cam khó phân biệt với mù màu đỏ–lục) và tím (trùng ghim "Đang xây"). Không dùng sắc độ khác nhau trong cùng loại (không phân biệt được trên nét đứt mờ). `infrastructure_routes.color_hex` vẫn lưu, không dùng để vẽ |
| Ghi nhớ chip bản đồ (2026-11-07) | `MapPreferencesStore` (protocol) → `UserDefaults` (JSON, key `map.preferences`). Nhớ: lớp tuyến **đã tắt**, "Đang nhận hồ sơ", vùng đang chọn. **Không** nhớ "Đã lưu", "Tất cả NOXH". Khôi phục đồng bộ trong `init` (lớp tuyến, bộ lọc) và sau khi tải danh mục (vùng — cần kiểm tra còn trong MVP). Vùng khôi phục bay camera **chỉ khi chưa có yêu cầu camera nào khác** (deep link / tìm kiếm / "Gần tôi" thắng); ranh giới tải xong chỉ chỉnh camera nếu không có yêu cầu mới hơn | Tùy chọn hiển thị theo máy, không theo tài khoản; không PII, không lên server (không đổi App Privacy). Không dùng `@AppStorage` (logic vào View, khó test) / `@SceneStorage` (mất khi vuốt tắt app) / server (khách không dùng được, phải chờ mạng). Lưu lớp **đã tắt** để loại tuyến mới thêm sau tự bật; mã lạ bị bỏ qua. Cờ DEBUG `-ResetMapPreferences` |
| Địa điểm đã lưu + ghi chú (2026-11-07) | Bảng `saved_places` (ngoài hệ thống) tách khỏi `bookmarks` (dự án trong hệ thống — giữ nguyên luồng thông báo); `bookmarks.note`. Ghi chỉ qua RPC (giới hạn 200, vùng MVP `ST_DWithin` 3 km quanh ranh giới in_mvp). Tìm: `PlaceSearchService` → `MKLocalSearch` (framework hệ thống); ghim tay. Icon: mã danh mục `place_icons` (không lưu tên SF Symbol → Android map được; server thêm icon không cần phát hành app). Chọn vị trí trước khi lưu: ghim là `Annotation` cố định theo tọa độ, kéo ghim bằng `DragGesture` + `MapProxy.convert` (bám mũi ghim lúc bắt đầu kéo + quãng kéo, không giật); địa chỉ: `ReverseGeocoder` → `MKReverseGeocodingRequest` (iOS 26+, `CLGeocoder` cho cũ hơn), locale `vi_VN`, chỉ tra khi dừng kéo (debounce 0,5 s, hủy lần cũ — Apple giới hạn tần suất). Chống trùng bằng `projects_in_bbox` khung nhỏ (300 m). Đề xuất dự án = `data_reports.kind = de_xuat_du_an` | Riêng tư, bắt buộc đăng nhập (không lưu tạm cho khách). Không gộp vào một bảng `saved_items` (phải viết lại bookmark/thông báo ngay trước phát hành). Không dùng Google Places (cấm lưu kết quả + hiển thị trên bản đồ khác). Apple Maps ở VN thiếu dự án mới → ghim tay là đường lui. Dung sai 3 km vì ranh giới đang mock; app kiểm tra cùng quy tắc để làm mờ kết quả, server là chốt chặn |
| 2.6 Seed | Hạ tầng lấy từ **GeoJSON** (`src/data/geojson/`) → sinh cả mock JSON của app lẫn `seed.sql` | Pipeline crawl sau này chỉ cần xuất GeoJSON đúng schema |

## 6. Cấu trúc thư mục mã nguồn (đề xuất)

```text
ios/AnCu/
├── App/                 # AnCuApp, CompositionRoot, AppConfig
├── Domain/              # Models thuần Swift, protocols Repository/Service, RepositoryError
├── Data/
│   ├── Supabase/        # Supabase*Repository, DTO (Row), mappers
│   └── Local/           # Lưu tạm bookmark của khách (SwiftData/UserDefaults)
├── Features/
│   ├── Map/             # MapView, MapViewModel, ProjectSheet
│   ├── Tracking/        # Saved list, compare, inbox
│   ├── Account/         # Auth, eligibility checker, settings, delete account
│   └── Comments/        # (sau Cổng C)
└── Shared/              # UI components, extensions
supabase/
├── migrations/          # SQL: tables, PostGIS, RLS, triggers, RPC functions
├── functions/           # Edge Functions: moderate-comment, send-push
└── seed/                # GeoJSON tuyến/ga, dự án mẫu
web/                     # (giai đoạn sau) Trang web công khai từng dự án
```

## 7. Luồng dữ liệu chính (Data Flow)

`View` → `ViewModel` → `Repository protocol` → `Supabase*Repository` (RPC / Auth / Storage) → `Postgres + PostGIS (RLS)`
