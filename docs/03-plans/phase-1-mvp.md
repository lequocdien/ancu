# Kế hoạch thực thi Phase 1: MVP - An Cư

> **Quy tắc làm việc:** Mỗi lần chỉ yêu cầu Claude Code thực hiện 1 mục con duy nhất (ví dụ: `1.1`), kiểm tra và test xong mới chuyển sang mục tiếp theo.
>
> Phạm vi: Giai đoạn 0 → 2 trong `roadmap.md` (iOS ra mắt **không có bình luận**). Spec: `01-ideas/prd.md`, `02-specs/*`.

> **Cập nhật 2026-11-07:** mọi việc code của Phase 1 đã xong. Còn lại là việc cần tài khoản / người ngoài — xem "Việc cần bạn làm" cuối file.

## Bước 0: Dữ liệu & pháp lý (song song với code)
- [x] 0.1 Chốt vùng MVP: TP.HCM (gồm Bình Dương cũ) + Đồng Nai
- [ ] 0.2 Số hóa tuyến Metro/Vành đai + ga/nút giao bằng QGIS/geojson.io → GeoJSON — *quyết định 2026-11-07: dùng **mock** tới khi crawl (giai đoạn sau); pipeline nhận GeoJSON đã sẵn (`src/data/README.md`)*
  - **Lý do chưa xong:** Bạn quyết định (2026-11-07) dùng dữ liệu mock trong Phase 1, dữ liệu thật sẽ crawl ở giai đoạn sau. Phần code đã sẵn: chỉ cần thay file GeoJSON rồi chạy `build_data.py`.
- [ ] 0.3 Nhập danh sách dự án NOXH kèm `source_url`, `verified_at` — *mock 15 dự án (`src/data/geojson/projects.geojson`), crawl sau*
  - **Lý do chưa xong:** Cùng quyết định với 0.2 — chưa có nguồn dữ liệu thật/người phụ trách dữ liệu; đang dùng 15 dự án mock.
- [x] 0.4 Kiểm tra cách Apple Maps hiển thị Hoàng Sa/Trường Sa; chọn phương án (tile overlay / giới hạn vùng) — *chọn giới hạn vùng: `MapCameraBounds` (khung tâm + 250 km); còn xem mắt thường trên máy thật*
- [ ] 0.5 Tư vấn luật sư: NĐ 147, Luật BVDLCN, chuyển dữ liệu ra nước ngoài — *cần bạn; danh sách câu hỏi ở mục "Việc cần bạn làm"*
  - **Lý do chưa xong:** Việc pháp lý phải do luật sư thực hiện, Claude không thay được. Câu hỏi đã soạn sẵn ở bảng "Việc cần bạn làm" (#5).
- [x] 0.6 Chốt ngưỡng bắt đầu Android: retention tuần 4 ≥ 20%, ≥ 30% người dùng hoạt động bật thông báo, ≥ 1.000 người dùng hoạt động/tháng trên iOS (đạt cả 3)

## Bước 1: Khởi tạo dự án & môi trường
- [x] 1.1 Tạo Xcode project SwiftUI (iOS target, Swift 6 strict concurrency), cấu trúc thư mục theo `architecture.md` mục 6 — *từ prototype*
- [x] 1.2 Tạo Supabase project + Supabase CLI local (`supabase init`, `supabase start`) — *local: 12 migration, pgTAP 67/67. Cloud (2026-11-07): project `ancu` gói Free, migration + seed mock, Auth email OTP qua SMTP Gmail tạm, app chạy thật với cloud. Còn: region Mumbai → Singapore, SMTP domain riêng trước phát hành (tasks.md)*
- [x] 1.3 Cấu hình môi trường: `AppConfig` (Debug/Release xcconfig), không commit key — *`Config/*.xcconfig` → Info.plist → `BackendConfig`; key thật trong `Secrets-*.xcconfig` (gitignore); app từ chối `sb_secret_`/service_role*
- [x] 1.4 Thêm `supabase-swift` qua SPM — *2.55.6, đã duyệt*

## Bước 2: Data Layer & Models
- [x] 2.1 Migration: enable PostGIS, tạo bảng theo `schema.md` (chưa gồm comments/reports/user_blocks)
- [x] 2.2 RLS policies + test policy (khách / user / service role)
- [x] 2.3 Trigger ghi `project_updates`
- [x] 2.4 Bảng tổng hợp `project_nearest_infra` + cơ chế refresh — *trigger; chuyển job định kỳ khi vài nghìn dự án*
- [x] 2.5 RPC: `projects_in_bbox`, `routes_in_bbox`, `project_detail`, `search_places` — *`routes(types, tolerance_degrees)` thay `routes_in_bbox` (11 tuyến, chưa cần lọc theo khung)*
- [x] 2.6 Seed script từ GeoJSON + dự án mẫu — *`src/data/scripts/build_data.py` (validate → mock JSON app → `seed.sql`), 20 unittest*
- [x] 2.7 Domain models + Repository protocols (`ProjectRepository`, `InfrastructureRepository`, `BookmarkRepository`, `EligibilityRepository`, `AuthService`) + `RepositoryError`
- [x] 2.8 `Supabase*Repository` + DTO/mapper + `CompositionRoot`; mock repository cho Preview/test — *toàn bộ repository + `SupabaseAuthService`*

## Bước 3: Tab Bản đồ
- [x] 3.1 MapView: ghim dự án gom cụm, màu theo trạng thái, tải theo khung nhìn (debounce)
- [x] 3.2 Lớp hạ tầng (Metro/Vành đai/Cao tốc/Quốc lộ) + chú giải màu, giản lược theo zoom — *`RouteDetail` 3 bậc, cache theo bậc*
- [x] 3.3 Tìm kiếm (tên dự án, quận/phường, tên cũ) + nút "Gần tôi" (quyền vị trí "khi dùng app") — *`CoreLocationService`, báo khi ở ngoài vùng hỗ trợ*
- [x] 3.4 Bottom sheet chi tiết: thông tin, khoảng cách ga/nút giao (ghi "đường chim bay"), nguồn + ngày cập nhật, cảnh báo > 30 ngày
- [x] 3.5 Bộ lọc "Đang nhận hồ sơ", lớp "Đã lưu"
- [x] 3.6 Nút "Báo thông tin sai" (`report_data`) — *giới hạn 10/24h, chỉ ghi qua RPC*

## Bước 4: Tài khoản, Theo dõi & Thông báo
- [x] 4.1 Đăng nhập Apple / Google / Facebook; chế độ khách + màn hình mời đăng nhập — *email OTP chạy thật (integration test qua Mailpit); Apple/Google/Facebook code sẵn, bật bằng `ANCU_AUTH_PROVIDERS` khi có tài khoản*
- [x] 4.2 Lưu dự án (local cho khách → `merge_guest_bookmarks` khi đăng nhập)
- [x] 4.3 Tab Theo dõi: danh sách theo hạn nộp hồ sơ, chế độ so sánh 2–3 dự án
- [x] 4.4 Push: đăng ký APNs, lưu `push_tokens`, Edge Function `send-push` (dedupe ≤ 1/ngày/dự án) — *dry-run end-to-end; gửi APNs thật cần key `.p8` + capability*
- [x] 4.5 Hộp thông báo trong app — *+ tùy chọn loại thông báo theo tài khoản, fan-out tôn trọng*
- [x] 4.6 Kiểm tra điều kiện mua NOXH (đọc `eligibility_rules`, không lưu câu trả lời mặc định)
- [ ] 4.7 Xóa tài khoản trong app (`delete-account`), trang chính sách / điều khoản / quy tắc cộng đồng — *xóa tài khoản xong (RPC); nội dung chính sách chờ luật sư (0.5)*
  - **Lý do chưa xong:** Phần code (xóa tài khoản) đã xong; còn nội dung 3 trang chính sách / điều khoản / quy tắc cộng đồng phải được luật sư duyệt (phụ thuộc 0.5) trước khi đưa lên store.
- [x] 4.8 Remote config tối thiểu: `min_supported_version` + force update

## Bước 5: Giám sát & phát hành
- [x] 5.1 Crashlytics + analytics, event cho phễu chính — *tự làm: `analytics_events` + MetricKit, view retention W4 + phễu; người dùng tắt được*
- [x] 5.2 Kiểm tra edge cases: không mạng, không có dữ liệu trong vùng, từ chối quyền vị trí — *nhãn ngoại tuyến + tự tải lại, gợi ý "Xem toàn vùng", nút mở Cài đặt*
- [x] 5.3 Review bảo mật RLS, không có service key trong app, rate limit — *`02-specs/security-review.md`; sửa 1 lỗ (ghi thẳng `data_reports`)*
- [ ] 5.4 Checklist App Store (`compliance.md` mục 2), App Privacy — *privacy manifest + bảng App Privacy xong; còn mục cần tài khoản/luật sư (compliance.md 2.2)*
  - **Lý do chưa xong:** Các mục còn lại cần thứ Claude không tự làm được: tài khoản Apple Developer (bật Sign in with Apple), Privacy Policy URL đã được luật sư duyệt, ảnh/mô tả store, kiểm tra trên máy thật (compliance.md 2.2).
- [ ] 5.5 TestFlight beta → phát hành — *cần Apple Developer account*
  - **Lý do chưa xong:** TestFlight bắt buộc tài khoản Apple Developer Program (99 USD/năm) để ký và tải bản build lên App Store Connect — chưa có tài khoản.

## Giai đoạn sau (chưa làm)
- Trang web công khai từng dự án (OG tags cho Zalo/Facebook, deep link / Universal Links mở app).
- Bình luận + ảnh, OTP, pipeline kiểm duyệt, báo cáo/chặn, trang quản trị, red-team kiểm duyệt.

## Việc cần bạn làm (chặn phần còn lại của Phase 1)

| # | Việc | Sau khi có, tôi làm |
| --- | --- | --- |
| 1 | **Apple Developer Program** (99 USD/năm). Gửi Team ID | Bật capability Sign in with Apple + Push Notifications, tạo Service ID, nối APNs key, TestFlight (5.5) |
| 2 | **APNs Auth Key `.p8`** (Certificates → Keys → Apple Push Notifications service). Gửi Key ID, KHÔNG gửi file qua chat — tự chạy `supabase secrets set` (lệnh ở `src/supabase/README.md`) | Kiểm tra gửi push thật, nhánh xóa token hết hạn |
| 3 | ✅ *(2026-11-07, dev — còn đổi region + SMTP domain)* **Supabase cloud** (region Singapore `ap-southeast-1`). Chạy `supabase link` + `supabase db push --remote` (*2026-11-07: project `ancu` đã tạo, gói Free, 12/12 migration đã đẩy*); điền `src/ios/Config/Secrets-Debug.xcconfig` (URL + key publishable) | Chạy integration test với cloud, cấu hình SMTP + Vault push (`security-review.md` mục 7) |
| 4 | **Google Cloud OAuth client** + **Meta app** (Facebook Login). Callback: `https://<ref>.supabase.co/auth/v1/callback` | Bật provider, đặt `ANCU_AUTH_PROVIDERS = apple,google,facebook`, thử trên máy |
| 5 | **Luật sư** (0.5): (a) app có cần xin phép/đăng ký theo NĐ 147 khi chưa có bình luận? (b) Luật BVDLCN: lưu email + analytics ẩn danh trên server Singapore — cần đánh giá tác động chuyển dữ liệu ra nước ngoài, cách lấy đồng ý? (c) Duyệt chính sách quyền riêng tư / điều khoản / quy tắc cộng đồng (bản tóm tắt đang ở app) | Cập nhật nội dung 3 trang + Privacy Policy URL cho App Store (4.7, 5.4) |
| 6 | **Xem trên iPhone thật**: Hoàng Sa/Trường Sa không lộ khi zoom/kéo tối đa (0.4); chip/màu tuyến (nợ thiết kế) | Chỉnh khung `MapRegion.allowedArea` nếu cần |
