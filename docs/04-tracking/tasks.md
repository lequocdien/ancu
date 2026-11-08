# Tracking Bảng Công Việc (Task Board) - An Cư

> File này dùng để đồng bộ tiến độ tức thời với Claude Code.

## 🚀 Đang thực hiện (In Progress)
- [ ] Staging dữ liệu + crawler (plan Bước 7) — 7.0–7.4 xong; còn nguồn crawl đầu tiên + đẩy migration 16
  - **Lý do chưa xong:** Nguồn thật cần khảo sát + liên hệ cho User-Agent; migration 16 lên cloud chờ bạn chạy.
- [x] Địa điểm đã lưu + ghi chú (PRD 4.6, plan Bước 6) — code, test, cloud (migration 13) xong 2026-11-07
- [ ] Review lại tài liệu đã phân bổ từ Đặc tả v2 (`01-ideas/`, `02-specs/`, `03-plans/`)
  - **Lý do chưa xong:** Việc review cần bạn đọc và xác nhận nội dung theo góc nhìn sản phẩm; Claude đã phân bổ xong, chờ phản hồi của bạn.

---

## 📋 Hàng đợi việc cần làm (Todo Backlog)
- [x] Chạy thử migration Supabase local (CLI 3.0.0, Postgres 17): 4 migration + seed OK, pgTAP 24/24, `db lint --schema public` sạch
- [ ] Đối chiếu `docs/03-plans/roadmap.md` với sơ đồ roadmap gốc (embedded, bị mất khi export) — chốt Cổng A, B, D *(cần file gốc của bạn)*
  - **Lý do chưa xong:** Sơ đồ roadmap gốc bị mất khi export; cần bạn gửi lại file gốc (ảnh/Figma) mới đối chiếu được.
- [ ] Demo prototype cho stakeholder / người dùng thử (TestFlight nội bộ) *(cần tài khoản Apple Developer)*
  - **Lý do chưa xong:** Phân phối qua TestFlight cần tài khoản Apple Developer. Tạm thời có thể demo bằng Simulator hoặc cài thẳng lên máy bạn (Personal Team, hết hạn sau 7 ngày).
- [ ] Đối chiếu nguyên văn NĐ 136/2026, NĐ 54/2026, Luật Dân số 2025 (khoản 13 Điều 76) trên Công báo / moc.gov.vn — ngưỡng hiện lấy từ báo chí
  - **Lý do chưa xong:** Lần tra cứu trước chỉ tìm được nguồn báo chí; cần mở văn bản gốc trên Công báo / cổng Bộ Xây dựng (hoặc nhờ luật sư) để xác nhận con số.
- [ ] Kiểm tra TP.HCM, Đồng Nai đã ban hành hệ số điều chỉnh thu nhập (điểm d khoản 1 Điều 30) chưa
  - **Lý do chưa xong:** Chưa tìm thấy quyết định của UBND hai tỉnh/thành trong nguồn đã tra; cần theo dõi tiếp hoặc hỏi Sở Xây dựng.
- [ ] Người phụ trách dữ liệu: polyline tuyến, tên phường/xã mới, 15 dự án mock → dữ liệu thật (Phase 1 Bước 0.2–0.3)
  - **Lý do chưa xong:** Chưa có người phụ trách dữ liệu; theo quyết định của bạn, Phase 1 dùng mock, dữ liệu thật crawl ở giai đoạn sau.
- [ ] Theo dõi: Vành đai 3 đoạn trên cao (thông xe 11/2026?), Metro TP mới Bình Dương – Suối Tiên (khởi công 12/2026?), Sân bay Long Thành (khai thác thương mại 24/12/2026?)
  - **Lý do chưa xong:** Đây là sự kiện tương lai (11–12/2026) — chỉ cập nhật được khi có tin chính thức.
- [ ] Phase 1 Bước 0.4 (xem trên máy thật) + 0.5 (tư vấn luật sư NĐ 147, Luật BVDLCN)
  - **Lý do chưa xong:** Code khóa vùng bản đồ đã xong; còn xem bằng mắt trên iPhone thật (Simulator không thay được hiển thị thực tế) và phần luật sư (0.5).
- [x] Nối app với Supabase — bước 1: 4 repository đọc công khai + chọn backend + integration test (architecture.md 5.5)
- [x] **Phase 1 — toàn bộ phần code** (2026-11-07): 0.4, 2.6, 2.8, 3.2–3.6, 4.1–4.8, 5.1–5.3; 5.4 một phần. Chi tiết `03-plans/phase-1-mvp.md`
- [ ] **Phase 1 — việc cần bạn** (bảng cuối `03-plans/phase-1-mvp.md`): Apple Developer, APNs key, Supabase cloud, Google/Meta OAuth, luật sư, xem máy thật
  - **Lý do chưa xong:** Tất cả cần tài khoản/chi phí hoặc người ngoài (Apple Developer, Supabase cloud, Google/Meta, luật sư, máy thật) — Claude không thể tạo thay bạn.
- [x] Tạo Supabase project cloud → điền `src/ios/Config/Secrets-Debug.xcconfig` (2026-11-07: `ancu`, gói Free, 12 migration + seed mock, SMTP Gmail tạm, đăng nhập email OTP thử thật OK). Region đang là Mumbai — xem nợ kỹ thuật
- [ ] Trước phát hành: SMTP domain riêng (Resend/SES) thay Gmail, `Secrets-Release.xcconfig`, tạo lại project ở Singapore, lên Pro
  - **Lý do chưa xong:** Chưa có domain gửi mail và chưa tới lúc phát hành (chờ Apple Developer / TestFlight); Gmail chỉ đủ cho dev (~500 mail/ngày, dễ vào spam).
- [x] Nối app với Supabase — bước 2: Auth (email OTP chạy thật; Apple/Google/Facebook sẵn sàng bật), Bookmark, Notification, DataReport, push token, analytics

---

## ✅ Đã hoàn thành (Done)
- [x] Chốt quyết định: ở lại Supabase lâu dài; ngưỡng Android (retention W4 ≥ 20%, ≥ 30% bật thông báo, ≥ 1.000 MAU); thêm loại tuyến `cao_toc`
- [x] Tra cứu lại đối thủ (2026-11-07) — cập nhật raw-ideas, thêm rủi ro VNeID vào PRD
- [x] Đối chiếu mock: 4 tuyến sai trạng thái/tên/năm → đã sửa; luật điều kiện theo NĐ 136/2026 (25/35/50 triệu, bỏ điều kiện nơi làm việc, thêm nhóm ≥ 2 con) → đã sửa app + test
- [x] Viết migration Supabase (schema PostGIS, RLS, RPC, trigger), seed sinh từ mock, 24 test pgTAP
- [x] Prototype iOS bước 9: kiểm tra dark mode, Increase Contrast, Dynamic Type AX5, fallback iOS 18.5 — sửa 4 lỗi layout/tương phản. `Localizable.xcstrings` (183 key) + `scripts/sync_strings.py`. `src/ios/README.md` — 96 test pass
- [x] Prototype iOS bước 8: tab Tài khoản (header, card kiểm tra điều kiện, cài đặt thông báo, 3 trang chính sách, liên hệ, đăng xuất, xóa tài khoản 2 bước)
- [x] Prototype iOS bước 7: `EligibilityEvaluator` (pure) + wizard 5 bước + màn kết quả 3 mức
- [x] Prototype iOS bước 6: tab Theo dõi (đã lưu theo hạn nộp, so sánh 2–3 dự án, hộp thông báo, mời đăng nhập)
- [x] Prototype iOS bước 5.3: sheet chi tiết dự án, `SessionStore`, prompt đăng nhập, chip "Đã lưu", báo thông tin sai
- [x] Prototype iOS bước 5.2: search (tên cũ, "Sắp có" vùng ngoài MVP), chip vùng, chip lớp + "Đang nhận hồ sơ", Gần tôi (mock), Chú giải — 57 test pass
- [x] Prototype iOS bước 5.1: MapViewModel + MapScreen (tuyến theo kiểu nét, ghim theo trạng thái, gom cụm lưới, tải theo khung nhìn có debounce) — 48 test pass
- [x] Prototype iOS bước 4: DesignSystem (7 token adaptive, `Glass.swift`, 4 component, MeshBackground, gallery light/dark) — 38 test pass
- [x] Prototype iOS bước 3: mock JSON (15 dự án, 11 tuyến, 34 node, 22 phường/xã, 11 lookup), DTO, mapper, 8 Mock repository, `AppContainer` — 33 test pass
- [x] Prototype iOS bước 2: Domain models + repository protocols + `RepositoryError`, 14 unit test pass
- [x] Prototype iOS bước 1: scaffold `src/ios/AnCu.xcodeproj`, app 3 tab chạy được, smoke test pass (iOS 27 sim)
- [x] Cập nhật "Lệnh thường dùng" trong `CLAUDE.md` cho Xcode
- [x] Tạo cấu trúc thư mục Vibe Coding chuẩn cho dự án An Cư
- [x] Tạo file cấu hình `CLAUDE.md` và các template hướng dẫn
- [x] Phân bổ Đặc tả sản phẩm v2 vào các folder docs + bổ sung Repository Pattern

---

## 🐛 Lỗi phát hiện & Nợ kỹ thuật (Bugs & Tech Debt)
- [ ] Supabase cloud `ancu` (`minfsjbwcmxgoqiptjka`) đang ở **Mumbai `ap-south-1`**, không phải Singapore như kế hoạch — tạo lại bằng `supabase projects create … --region ap-southeast-1` trước khi phát hành / lên Pro
  - **Lý do chưa xong:** Lúc tạo chọn region "auto" nên Supabase xếp vào Mumbai; bạn quyết định (2026-11-07) giữ Mumbai cho giai đoạn dev, chuyển sau. Không đổi region tại chỗ được — phải tạo project mới + `db push --remote` + nạp lại dữ liệu. Ảnh hưởng: trễ thêm ~30–50 ms/request; hồ sơ chuyển dữ liệu ra nước ngoài (0.5) phải ghi đúng quốc gia.
- [ ] Ranh giới vùng (highlight khi chọn chip) là đa giác giản lược mock — thay bằng ranh giới chính thức (tỉnh cũ, trước sáp nhập 7/2025)
  - **Lý do chưa xong:** Bạn chọn mock (2026-11-07); ranh giới chính xác cần nguồn chính thức hoặc OSM (giấy phép ODbL, phải ghi công) — làm cùng đợt crawl dữ liệu.
- [ ] `xcodebuild test` song song 2 lần bị treo (host app dừng giữa chừng → `simctl diagnose` chờ 10 phút) khi đang đổi DB/sửa code cùng lúc; 4 lần chạy sau đều pass ~1 phút. Nếu lặp lại: chạy `-parallel-testing-enabled NO`, lấy `sample` của process AnCu lúc treo
  - **Lý do chưa xong:** Không tái hiện được (4 lần chạy sau đều pass) và crash report không được lưu, nên chưa xác định nguyên nhân — để theo dõi thay vì sửa mò.
- [ ] Sign in with Apple: chưa lưu tên (Apple chỉ gửi lần đầu) vào `profiles.display_name`
  - **Lý do chưa xong:** Không test được khi chưa có capability Sign in with Apple (cần Apple Developer); làm cùng lúc bật đăng nhập Apple.
- [ ] Analytics: chưa có job xóa sự kiện > 13 tháng; ingest chưa có rate limit theo IP (security-review.md mục 4)
  - **Lý do chưa xong:** Chưa cần ở quy mô hiện tại (chưa có người dùng thật); rate limit theo IP phải làm ở gateway (Cloudflare) khi có hạ tầng cloud.
- [ ] Deno test của `send-push` mới chạy qua shim Node (máy chưa cài deno)
  - **Lý do chưa xong:** Máy chưa cài Deno và theo quy tắc dự án không tự cài công cụ mới khi chưa hỏi bạn.
- [ ] Gom cụm theo lưới: cụm có thể nằm sát ghim lẻ ở ô bên cạnh (thấy trên Simulator). Cân nhắc gom theo khoảng cách điểm ảnh nếu khó chịu khi test thật
  - **Lý do chưa xong:** Chỉ là vấn đề thẩm mỹ thấy trên Simulator; cần thử trên máy thật để quyết định có đáng đổi thuật toán không.
- [ ] Chip đang bật trên iOS 17–25 (fallback material) vẫn khá nhạt — kiểm tra lại trên máy thật
  - **Lý do chưa xong:** Độ đậm nhạt của material phụ thuộc màn hình thật; Simulator không đánh giá chính xác được.
- [ ] Chưa kiểm tra trực quan (simctl không gõ/bấm được, chỉ có unit test): kết quả tìm kiếm, sheet Chú giải, bảng So sánh, màn kết quả wizard, luồng xóa tài khoản. Cần thêm UI test (XCUITest) hoặc test tay trên máy
  - **Lý do chưa xong:** simctl không bấm/gõ được nên các màn cần thao tác chưa được chụp; cần viết XCUITest (chưa làm vì ưu tiên các mục Phase 1) hoặc bạn test tay.
- [ ] Overlay bản đồ (search, chip) ở Dynamic Type AX5 chưa kiểm tra
  - **Lý do chưa xong:** Cùng lý do: cần thao tác trên giao diện, simctl không làm được; nằm trong phạm vi XCUITest đề xuất.
- [ ] Chưa kiểm tra Reduce Transparency trực tiếp (simctl không bật được) — nhánh code dùng chung với Increase Contrast đã kiểm tra
  - **Lý do chưa xong:** Simulator không có lệnh bật Reduce Transparency qua simctl; cần bật tay trong Cài đặt trên máy/Simulator.
- [ ] Logic `EligibilityEvaluator` là MOCK (ngưỡng thu nhập 25/35/50 triệu, nhóm không xét trần thu nhập) — cần luật sư/chuyên gia đối chiếu Luật Nhà ở 2023, NĐ 100/2024
  - **Lý do chưa xong:** Ngưỡng hiện lấy từ báo chí; phải có luật sư/chuyên gia đối chiếu văn bản gốc trước khi bỏ nhãn MOCK.
- [ ] Quốc lộ đã khai thác (xám, 5pt) lấn át map và gần màu ghim "Đã đóng" — cần chốt lại với design
  - **Lý do chưa xong:** Là quyết định thiết kế (màu/độ dày nét) — cần designer hoặc bạn chốt, không nên tự đổi.
