# Nhật ký phát triển (Developer Log) - An Cư

Tài liệu này ghi lại tóm tắt sau mỗi phiên làm việc cùng Claude Code để giữ ngữ cảnh không bị mất đi qua thời gian.

---

## [Khởi tạo] - 2026-11-06
- **Mục tiêu phiên**: Khởi tạo cấu trúc dự án và quy trình Vibe Coding.
- **Những việc đã thực hiện**:
  - Tạo cấu trúc thư mục 4 tầng: `01-ideas`, `02-specs`, `03-plans`, `04-tracking`.
  - Tạo `CLAUDE.md` định hướng nguyên tắc code, lệnh chạy và cấu trúc tài liệu.
  - Tạo bảng task và các file mẫu.
- **Kế hoạch phiên tiếp theo**:
  - Mở terminal, gõ `claude` tại thư mục này.
  - Điền ý tưởng dự án vào `docs/01-ideas/raw-ideas.md` và nhờ Claude hoàn thiện PRD.

## [Phân bổ spec v2] - 2026-11-06
- **Mục tiêu phiên**: Phân bổ "Đặc tả sản phẩm – NOXH & Hạ Tầng Map (v2, iOS trước)" vào cấu trúc docs.
- **Những việc đã thực hiện**:
  - Bản gốc chuyển vào `01-ideas/source/` (giữ làm nguồn tham chiếu).
  - `01-ideas/raw-ideas.md`: bài toán, đối thủ, giá trị cốt lõi, câu hỏi mở.
  - `01-ideas/prd.md`: persona, màn hình, tính năng, scope MVP, tiêu chí thành công, rủi ro.
  - `02-specs/architecture.md`: tech stack, iOS-first, chủ quyền bản đồ, pipeline kiểm duyệt/thông báo, **Repository Pattern** (chuẩn bị chuyển Supabase → .NET).
  - `02-specs/schema.md`: bảng, kiểu PostGIS, RLS, RPC contracts (đề xuất).
  - Mới: `02-specs/data-strategy.md`, `02-specs/compliance.md`, `03-plans/roadmap.md`.
  - `03-plans/phase-1-mvp.md`: viết lại theo SwiftUI + Supabase.
- **Quyết định / lưu ý**:
  - Repository protocol nhận `MapRegion` + filter (không dùng `getProjects()` trơn), tách DTO khỏi domain, gọi Supabase qua RPC.
  - Roadmap gốc là embedded content bị mất khi export — Cổng A, B, D đang là bản dựng lại.
- **Kế hoạch phiên tiếp theo**: trả lời câu hỏi mở, đối chiếu roadmap, bắt đầu Bước 0.

## [Điều chỉnh scope] - 2026-11-06
- Bỏ đoạn "Ai gặp vấn đề" trong `raw-ideas.md`.
- **Trang web công khai từng dự án dời ra khỏi MVP** (làm sau). Cập nhật PRD scope/tiêu chí/rủi ro, architecture, roadmap, phase-1 (bỏ task web, đánh số lại Bước 5), CLAUDE.md.

## [Chốt vùng MVP + prompt prototype] - 2026-11-06
- **Quyết định**: vùng MVP = TP.HCM (gồm Bình Dương cũ) + Đồng Nai. Hà Nội làm sau.
- **Lưu ý**: địa giới mới rộng hơn phạm vi (TP.HCM mới gồm cả Bà Rịa – Vũng Tàu cũ, Đồng Nai mới gồm cả Bình Phước cũ) → phạm vi xác định theo địa giới cũ / polygon, không theo `province`.
- **Đã cập nhật**: prd, raw-ideas, data-strategy, phase-1-mvp (0.1), roadmap, CLAUDE.md, tasks.
- **Quyết định**: deployment target iOS 17; Liquid Glass chỉ trên iOS 26+, fallback `.ultraThinMaterial`, cô lập trong `Core/DesignSystem/Glass.swift`.
- **Đã tạo**: `docs/02-specs/prototype-ios.md` (prompt prototype đầy đủ), `docs/02-specs/prototype-preview/` (HTML + PNG xem trước UI).
- **Kế hoạch phiên tiếp theo**: chốt cách tạo `.xcodeproj` và loại tuyến `cao_toc`, rồi scaffold prototype theo mục 11 của spec.

## [Scaffold prototype iOS — bước 1] - 2026-11-06
- **Đã làm**: tạo `src/ios/AnCu.xcodeproj` viết tay (objectVersion 77, synchronized folders, không dependency), target `AnCu` + `AnCuTests` (Swift Testing), shared scheme. Bundle id `vn.ancu.app`, Swift 6, iOS 17.
- **Nội dung**: `AnCuApp`, `RootTabView` (3 tab, tab Bản đồ là `Map` tâm vùng MVP, 2 tab còn lại placeholder), asset `AccentColor` = brandPrimary.
- **Xác minh**: `xcodebuild test` pass trên iPhone 18 Pro (iOS 27). Chạy app trên Simulator: tab bar Liquid Glass native hiển thị đúng.
- **Lưu ý**: Apple Maps hiển thị nhãn theo ngôn ngữ máy (sim tiếng Anh → "Ho Chi Minh City") và còn vẽ ranh giới tỉnh cũ — liên quan bước 0.4 (kiểm tra hiển thị bản đồ).
- **Phiên tiếp theo**: bước 2 — Domain.

## [Prototype iOS — bước 2: Domain] - 2026-11-06
- **Đã làm**: `src/ios/AnCu/Domain/` — `Geo` (GeoPoint, MapRegion), `Lookup` (9 enum danh mục + LookupCatalog), `Project` (PriceRange, ApplicationPhase, NearestInfra, ProjectDetail, ProjectFilter), `Infrastructure`, `Place` (AdministrativeUnit, SearchResult), `UserData` (AppUser, Bookmark, AppNotification, EligibilityRule); `Repositories/` — 8 protocol + `RepositoryError`.
- **Quyết định**:
  - Enum lookup có case `.unknown`; mapper map code lạ → `.unknown` để server thêm trạng thái mới không làm hỏng app bản cũ.
  - `GeoPoint` riêng thay `CLLocationCoordinate2D` (không Hashable) trong Domain.
  - Tính ngày nhận hồ sơ theo lịch `Asia/Ho_Chi_Minh` để hạn nộp không lệch ngày khi máy để múi giờ khác.
  - Thêm so với spec: `LookupRepository.administrativeUnits()`, `BookmarkRepository.mergeGuestBookmarks()`, `NotificationRepository.markAsRead`, `DataReportRepository` (nút "Báo thông tin sai"); `toggle` trả về trạng thái mới.
- **Xác minh**: `xcodebuild test` 14/14 pass trên iOS 27, không warning.
- **Phiên tiếp theo**: bước 3 — Lookup/mock JSON + Data/Mock.

## [Prototype iOS — bước 3: Data/Mock] - 2026-11-06
- **Đã làm**:
  - `Data/Mock/Resources/`: `projects.json` (15 dự án hư cấu: 5 TP.HCM cũ, 5 Bình Dương cũ, 5 Đồng Nai cũ), `routes.json` (11 tuyến: 4 Metro, 2 Vành đai, 2 Cao tốc, 3 Quốc lộ), `nodes.json` (34 ga/nút giao + Sân bay Long Thành), `notifications.json`, `Lookup/` (9 danh mục + `administrative_units` + `eligibility_rules`). UUID sinh xác định (uuid5) để chạy lại không đổi.
  - `Data/Mock/DTO`, `Mappers` (parse ngày theo giờ VN, validate contract → `RepositoryError.decoding`), `Repositories` (MockDataStore + 8 repository), `App/AppContainer.swift` (composition root + `EnvironmentValues.container`).
- **Quyết định**:
  - `DateShift`: mọi ngày trong mock dời theo (hôm nay − 2026-11-06) để prototype luôn có dự án đang mở/sắp mở dù chạy ngày nào. Chỉ ở mock.
  - `UserDefaults` không Sendable → truyền `MockDefaultsSuite` (tên suite), mỗi actor tự mở instance.
  - Khách lưu được (cờ `isLocalOnly`); bật thông báo / inbox / báo sai cần đăng nhập → `unauthorized`. Bật thông báo cho dự án chưa lưu thì tự lưu. Đăng xuất chỉ giữ bookmark của khách.
  - `NearestInfra` route fields thành optional (Sân bay Long Thành không thuộc tuyến). Điểm hạ tầng lớn chỉ hiện trong bán kính 25 km.
  - Tìm kiếm bỏ dấu + "đ"→"d", khớp cả tên cũ; "Long Bình" trả về cả TP.HCM và Đồng Nai.
- **Xác minh**: 33/33 test pass trên iOS 27 (gồm test kiểm tra tính nhất quán của chính JSON); build pass trên iOS 18.5.
- **Rủi ro dữ liệu**: tên phường/xã mới, tọa độ tuyến, trạng thái/năm khai thác, ngưỡng thu nhập đều là MOCK — đã thêm task đối chiếu.
- **Phiên tiếp theo**: bước 4 — DesignSystem.

## [Prototype iOS — bước 4: DesignSystem] - 2026-11-06
- **Đã làm**: `src/ios/AnCu/Core/DesignSystem/`:
  - Token adaptive trong `Assets.xcassets/Tokens` (Light/Dark/High Contrast): BrandPrimary, BrandAccent, OnBrandPrimary, StatusOpen/Soon/Closed/Building. Xcode tự sinh `Color.brandPrimary`… — `Colors.swift` không khai báo lại.
  - `Glass.swift`: `GlassStyle`, `.adaptiveGlass`, `AdaptiveGlassContainer`, `.adaptiveGlassID`, `.adaptiveGlassButton(.regular/.prominent)`, `.adaptiveTabBarMinimizeOnScroll`. iOS 26 kính · iOS 17–25 material · Reduce Transparency/Increase Contrast nền đặc + viền.
  - `LookupStyle.swift` (code → màu/icon/kiểu nét tuyến), `Typography.swift` (font số liệu, `Motion`, `.pulsing`), `Spacing.swift`, `MeshBackground.swift` (MeshGradient iOS 18+, 30fps, dừng khi Reduce Motion; iOS 17 LinearGradient).
  - Component: `StatusBadge`, `MetricTile`, `GlassCard`, `PrimaryButton`. `DesignSystemGallery` (#Preview light/dark, DEBUG launch arg `-DesignSystemGallery`).
- **Quyết định**:
  - StatusBadge: chữ `.primary`, chỉ icon mang màu (chữ amber trên nền sáng ~2:1, không đạt WCAG).
  - Thêm token `onBrandPrimary`: dark mode chữ trắng trên `#2DD4BF` chỉ ~1.9:1 → dùng chữ tối. Phát hiện qua ảnh chụp dark.
  - Code đã biết → token adaptive; danh mục chưa có token → `color_hex` từ catalog. `RouteStatus.unknown` vẽ như "quy hoạch" (không để người dùng tưởng tuyến đã chạy).
  - `tabBarMinimizeBehavior` là modifier của cả `TabView`, không áp riêng một tab được như spec viết.
  - Test kiến trúc `glassAPIsOnlyInGlassFile`: quét source, fail nếu file ngoài `Glass.swift` gọi API kính/material.
- **Xác minh**: 38/38 test pass (iOS 27), build pass iOS 18.5. Chụp gallery trên Simulator: iOS 27 light/dark, iOS 18.5 fallback — hiển thị đúng.
- **Chưa kiểm tra**: Reduce Transparency, Increase Contrast, Dynamic Type lớn trên Simulator (để bước 9). Chưa có `Localizable.xcstrings`.
- **Phiên tiếp theo**: bước 5 — Feature Map.

## [Prototype iOS — bước 5.1: Map core] - 2026-11-06
- **Đã làm**: `Features/Map/` — `ProjectClusterer` (pure), `MapViewModel` (@Observable @MainActor), `ProjectPinView` + `ClusterView`, `MapScreen` (Map + MapPolyline + Annotation, banner loading/lỗi kính). `RootTabView` dùng `MapScreen` thay placeholder.
- **Quyết định**:
  - Gom cụm lưới neo tọa độ tuyệt đối, kích thước ô làm tròn lũy thừa 2 → kéo/zoom nhẹ không xáo trộn cụm. Zoom sâu hơn 0.04° kinh không gom. Bấm cụm → zoom vào khung bao.
  - Dự án tải theo khung nhìn ×1.5, debounce 300ms, hủy task cũ + kiểm tra `Task.isCancelled` sau await để kết quả cũ không ghi đè. Lỗi giữ ghim cũ, hiện nút "Thử lại".
  - Tuyến (11) tải một lần, bật/tắt lớp lọc ở client; vẽ quy hoạch → thi công → khai thác. TODO(backend): `routes_in_bbox` + giản lược theo zoom.
  - Ghim "Đang nhận hồ sơ" pulse (tắt khi Reduce Motion / đang chọn). Cụm dùng màu brand, không theo trạng thái.
- **Xác minh**: 48/48 test pass (iOS 27), build pass iOS 18.5. Chụp app trên Simulator: tuyến đúng kiểu nét, ghim đúng màu, có cụm.
- **Ghi nhận (tech debt)**: cụm có thể sát ghim lẻ ở ô kề; Quốc lộ xám 5pt lấn át map.
- **Phiên tiếp theo**: 5.2 — overlay nổi trên map.

## [Prototype iOS — bước 5.2: overlay bản đồ] - 2026-11-07
- **Đã làm**: `MapControls.swift` (MapSearchBar, MapChip, MapSearchResults), `LegendSheet.swift` (+ RouteLineSample), mở rộng `MapViewModel` (search debounce, vùng, bộ lọc "Đang nhận hồ sơ", Gần tôi, `CameraRequest`), `MapScreen` ghép overlay.
- **Thay đổi kiến trúc**:
  - `SearchNormalizer` chuyển `Data/Mock` → `Domain/Services` (ViewModel cần dùng, không được phụ thuộc tầng Mock).
  - Thêm `LocationService` + `LocationError` (typed throws) vào Domain, `MockLocationService` (Thủ Đức), `AppContainer.location`. TODO(backend): CLLocationManager + NSLocationWhenInUseUsageDescription.
  - `GlassButtonKind.icon` cho nút tròn chỉ icon (fallback 48pt, đủ vùng chạm).
- **Quyết định**:
  - ViewModel phát `CameraRequest` (có id để yêu cầu trùng vùng vẫn kích hoạt), View quyết định animation.
  - Tìm kiếm phân biệt "lỗi" với "không có kết quả". Vùng/phường ngoài MVP (Bà Rịa – Vũng Tàu, Bình Phước cũ) hiện "Sắp có", không bấm được.
  - Bấm lại vùng đang chọn → về toàn vùng MVP.
  - Chip "Đã lưu" dời sang 5.3 (cần luồng đăng nhập + bookmark, dùng chung với nút Lưu).
  - Fallback tint 0.25 → 0.45 (chip bật gần như không thấy trên iOS 18). Differentiate Without Color → chip bật có dấu ✓.
- **Xác minh**: 57/57 test pass (iOS 27), build pass iOS 18.5. Chụp màn hình mặc định iOS 27 + 18.5.
- **Chưa xác minh trực quan**: kết quả tìm kiếm, sheet Chú giải, chấm vị trí (không gõ/bấm được qua simctl) — đã thêm task.
- **Phiên tiếp theo**: 5.3 — sheet chi tiết dự án.

## [Prototype iOS — bước 5.3: Sheet chi tiết + phiên] - 2026-11-07
- **Đã làm**: `App/SessionStore.swift` (user + bookmark dùng chung 3 tab), `Features/Auth/SignInPromptView.swift` (+ modifier `.signInPrompt`), `Features/Map/ProjectDetailViewModel.swift`, `ProjectDetailSheet.swift` (+ `ReportDataSheet`), `Core/Extensions/DisplayFormat.swift`, `App/DebugLaunchOptions.swift`. Chip "Đã lưu" trên map. `ProjectRepository.projects(ids:)`.
- **Quyết định**:
  - SessionStore KHÔNG giữ cờ prompt toàn cục: prompt thường bật khi sheet chi tiết đang mở, sheet từ root sẽ bị bỏ qua. Hàm trả kết quả, màn hình tự trình bày.
  - Khách lưu được (local); gợi ý đăng nhập chỉ một lần mỗi phiên. Bật thông báo / lớp Đã lưu / Báo sai cần đăng nhập.
  - Map giữ `selectedProject` (không chỉ id) → chọn từ tìm kiếm khi dự án chưa nằm trong khung đã tải vẫn mở được sheet; kéo map không tự đóng sheet.
  - Sheet `presentationBackgroundInteraction(.enabled(upThrough: .medium))` để vẫn thao tác map.
  - DisplayFormat dùng FormatStyle (Sendable), giờ VN. Tuyến đã khai thác ghi "Khai thác từ <năm>" thay vì "Dự kiến".
  - Debug launch args (`-SelectFirstProject`, `-DetailLarge`, `-SignedIn`, `-Tab`) gom ở `DebugLaunchOptions`, chỉ có tác dụng ở DEBUG.
- **Xác minh**: test pass; chụp sheet ở detent thấp và `.large` trên iOS 27.

## [Prototype iOS — bước 6: Tab Theo dõi] - 2026-11-07
- **Đã làm**: `Features/Tracking/` — `TrackingViewModel`, `TrackingScreen` (+ `SavedProjectCard`), `InboxView`, `CompareView`. Khách thấy `SignInPromptView` nhúng trong card kính. `.adaptiveTabBarMinimizeOnScroll()` trên TabView. Debug flag `-SeedBookmarks`.
- **Quyết định**:
  - Sắp xếp: đang mở (ít ngày trước) → sắp mở → chưa công bố → đã kết thúc. Progress chỉ cho đợt đang mở.
  - So sánh tối đa 3; vượt → haptic cảnh báo. Bỏ lưu dự án đang chọn → tự rời khỏi so sánh. "Tốt nhất" chỉ đánh dấu khi có ≥ 2 giá trị và nhỏ nhất là duy nhất; hiển thị bằng chữ đậm + ✓ (không chỉ màu).
  - Bấm card mở lại `ProjectDetailSheet` (dùng chung với Bản đồ). Đánh dấu đã đọc lạc quan.
- **Xác minh**: test pass; chụp khách / rỗng / có danh sách trên iOS 27.

## [Prototype iOS — bước 7, 8, 9: Điều kiện, Tài khoản, kiểm tra] - 2026-11-07
- **Bước 7**: `Domain/Services/EligibilityEvaluator.swift` (pure, ngưỡng từ `eligibility_rules`), `Features/Eligibility/` (ViewModel + wizard + màn kết quả).
  - Hỏi **hôn nhân trước thu nhập** (khác thứ tự spec): ngưỡng và nghĩa "thu nhập" (cá nhân / tổng vợ chồng) phụ thuộc hôn nhân.
  - Kết quả = tiêu chí tệ nhất. Thiếu luật/câu trả lời → "Cần kiểm tra thêm", không bao giờ "đủ". "Đối tượng khác", làm việc tỉnh khác → cần kiểm tra thêm (không từ chối). Hộ nghèo bỏ qua ngưỡng thu nhập (MOCK).
  - Câu trả lời chỉ trong bộ nhớ; gắn nhãn MOCK khi luật là dữ liệu mẫu; số thập phân dấu phẩy.
- **Bước 8**: `Features/Account/` — header (chỉ icon mang màu), card kiểm tra điều kiện (kính tint), cài đặt thông báo (local, TODO backend), 3 trang chính sách tóm tắt, liên hệ (yêu cầu UGC App Store), đăng xuất, xóa tài khoản 2 bước (`AccountViewModel` chặn nhảy cóc).
- **Bước 9 — kiểm tra & sửa**:
  - Dark, Increase Contrast (token HC + nhánh nền đặc), iOS 18.5 fallback: đúng.
  - Dynamic Type AX5 vỡ layout → thêm `AdaptiveStack` (ngang ↔ dọc theo cỡ chữ), lưới số liệu 1 cột, nút hành động xếp dọc full-width, badge 2 dòng.
  - Chữ "Đã xác thực SĐT" màu xanh ~2,5:1 → chữ secondary, chỉ icon mang màu.
  - `Localizable.xcstrings` (183 key). `xcodebuild` không đồng bộ catalog → `scripts/sync_strings.py` đọc `.stringsdata`.
  - `src/ios/README.md`: chạy, kiến trúc, thay Mock bằng backend, bảng TODO(backend), debug flags.
- **Xác minh**: 96/96 test pass (iOS 27), build pass iOS 18.5.
- **Chưa xác minh trực quan**: kết quả tìm kiếm, Chú giải, So sánh, kết quả wizard, luồng xóa tài khoản, overlay map ở AX5 — đã ghi tech debt; đề xuất thêm XCUITest.

## [Xử lý Todo Backlog] - 2026-11-07
- **Quyết định của bạn**: ở lại Supabase lâu dài (architecture.md 5.0, vendor lock-in thấp ở tầng dữ liệu, đường lui self-host); ngưỡng Android = retention W4 ≥ 20% + ≥ 30% bật thông báo + ≥ 1.000 MAU iOS; thêm `cao_toc`; viết migration SQL trước, chưa thêm dependency vào app.
- **Tra cứu (agent, nguồn báo chí/cổng chính thức)**:
  - Đối thủ: chưa ai làm "bản đồ NOXH + hạ tầng" ở TP.HCM/BD/ĐN. Rủi ro mới: phần mềm đăng ký NOXH Hà Nội, đề xuất xét duyệt qua VNeID → thêm vào PRD.
  - Tuyến: Cao tốc Biên Hòa – Vũng Tàu đã khai thác (18/5/2026); Vành đai 4 đang thi công; metro kéo dài đổi thành "Suối Tiên – Sân bay Long Thành" (chưa có năm) và "TP mới Bình Dương – Suối Tiên" (2030). Đã sửa routes.json + source_url thật.
  - Luật: NĐ 136/2026 (hiệu lực 07/04/2026) nâng trần 25/35/50 triệu; NĐ 54/2026 bỏ điều kiện cư trú/nơi làm việc, nhà ở xét tại tỉnh có dự án; Luật Dân số 2025 thêm nhóm ≥ 2 con (01/07/2026).
- **App**: `EligibilityEvaluator` viết lại — `Family` (độc thân / nuôi con / kết hôn), bỏ tiêu chí nơi làm việc, nhóm xét trần thu nhập lấy từ rule `income_ceiling_subjects` (không hardcode). Wizard 4 bước. Thêm `EligibilitySubject.multipleChildren`. Test cập nhật — 96/96 pass.
- **Supabase** (`src/supabase/`): 4 migration (lookup table thay enum + FK qua cột generated; RLS; RPC trả đúng shape mock JSON; trigger profile, lịch sử, fan-out 1 thông báo/ngày/dự án, ga gần nhất KNN; `delete_my_account`), `scripts/generate_seed.py` → `seed.sql`, 24 test pgTAP, README contract RPC ↔ protocol.
- **Chưa xác minh**: migration chưa chạy (thiếu Supabase CLI, Docker tắt). Ngưỡng luật lấy từ báo, chưa đọc nguyên văn.

## [Chạy thử Supabase local] - 2026-11-07
- Cài Supabase CLI 3.0.0 (brew), `supabase init` trong `src/` (project_id `ancu`), `supabase start` (Postgres 17.11).
- **Kết quả**: 4 migration + `seed.sql` áp được ngay lần đầu, không phải sửa. `supabase test db`: 24/24 pass. `supabase db lint --schema public`: không lỗi.
- **Lưu ý**: `supabase db lint` không giới hạn schema báo lỗi trong hàm nội bộ PostGIS (`extensions.*`, ví dụ `lockrow`, `st_findextent`). Đó là code của extension, không phải của mình → lint chỉ schema `public`.
- **Chưa xác minh**: gọi RPC qua REST/PostgREST (curl bị chặn quyền trong session). pgTAP đã gọi trực tiếp các RPC với role anon/authenticated.
- **Tiếp theo**: nối app với Supabase cần `supabase-swift` → chờ duyệt dependency.

## [Nối app với Supabase — bước 1: dữ liệu công khai] - 2026-11-07
- **Dependency (đã duyệt)**: `supabase-swift` 2.55.6 qua SPM (product `Supabase`, chỉ target app).
- **Quyết định** (architecture.md 5.5): 4 repository đọc công khai trước; Auth/Bookmark/Notification/DataReport vẫn Mock (container lai, id trùng vì seed sinh từ mock). Repository phụ thuộc `RPCClient` mỏng → test bằng fake. Lấy raw `Data`, decode bằng decoder của app → dùng lại DTO. Map lỗi tập trung ở `SupabaseErrorMapper`.
- **Code**: `Data/Shared/` (DTO + `DTOMapper`, đổi tên từ `MockMapper`; thêm DTO `project_detail`, `search_places`), `Data/Supabase/`, `App/BackendConfig.swift` (`-Backend local`, env `ANCU_SUPABASE_URL/KEY`), `AppContainer.supabase(...)`/`.make(_:)`.
- **Supabase**: migration 05 `administrative_units_all()` (bảng có cột geography → WKB qua PostgREST, phá contract `{lat, lng}`). pgTAP 25/25.
- **Xác minh**: 120 test pass (iOS 27) gồm 13 unit test Supabase (fake RPC, error mapper, BackendConfig) + 7 integration test gọi stack local thật qua PostgREST (dữ liệu khớp mock seed, P0002 → `.notFound`, anon insert bookmark bị RLS chặn). Build iOS 18.5 pass. Chạy app `-Backend local`: sheet chi tiết hiển thị đúng, ga gần nhất lấy từ `project_nearest_infra`.
- **Tiếp theo**: bước 2 — Sign in with Apple (cần Apple Developer account + capability), `SupabaseAuthService`, bookmark/notification/report qua RLS + RPC.

## [Phase 1 — đối chiếu kế hoạch + bước 1.3 cấu hình môi trường] - 2026-11-07
- **Đối chiếu** `phase-1-mvp.md` với code: 14 mục đã xong từ prototype + Supabase bước 1, 7 mục xong một phần (ghi rõ phần còn thiếu). Thứ tự việc không chờ ai: 1.3 → 3.4 → 3.3 → 4.8 → 3.2 → 5.2.
- **1.3**: `src/ios/Config/` — `Debug.xcconfig`, `Release.xcconfig` (`#include?` file `Secrets-*.xcconfig` gitignore), `Secrets.example.xcconfig`, `Info.plist` (gộp với plist sinh tự động: `AnCuSupabaseURL/Key = $(ANCU_SUPABASE_*)`). `BackendConfig` đọc thêm Info.plist; thêm `-Backend mock`; từ chối `sb_secret_` / JWT `service_role` (yêu cầu 5.3 làm sớm).
- **Bẫy**: `//` trong xcconfig là comment → URL phải viết `https:/$()/…`. Có test cho trường hợp quên (giá trị bị cắt thành `https:` → Mock).
- **Xác minh**: 9 test `BackendConfigTests` (gồm kiểm tra Info.plist đã build có key). Thử thật với `Secrets-Debug.xcconfig` trỏ stack local: plist có URL đầy đủ, display name/launch screen vẫn giữ; mở app **không cờ** → log Kong thấy `rpc/routes`, `rpc/lookup_catalog`. Đã xóa file Secrets tạm. Toàn bộ test pass.

## [Phase 1 — làm toàn bộ (phần 1)] - 2026-11-07
- **Quyết định của bạn** (AskUserQuestion): chưa có Apple Developer → làm sẵn, test bằng email OTP; đăng nhập Apple + Google + Facebook (OAuth web, không SDK); analytics tự làm (Supabase + MetricKit, không thư viện); chủ quyền = giới hạn vùng camera. Dữ liệu tiếp tục mock, crawl ở giai đoạn sau. Ghi ở architecture.md 5.6, mục 3.
- **3.4** đã có từ prototype (`Project.isStale` + nhãn trong sheet) — đối chiếu trước đó bỏ sót.
- **0.4**: `MapCameraBounds` (khung tâm `MapRegion.allowedArea`, 300 m – 250 km). Test: khung phủ vùng MVP + mọi dự án; Hoàng Sa/Trường Sa cách khung > 1,5× độ cao tối đa.
- **3.3**: `Data/Device/CoreLocationService` (lấy 1 lần, timeout 10 s, xử lý hủy không treo continuation), `NSLocationWhenInUseUsageDescription`, lỗi mới `.outsideServiceArea` + nút "Mở Cài đặt" khi bị từ chối. Cờ `-LocateOnLaunch`. Chụp Simulator: chấm vị trí đúng chỗ đặt.
- **4.8**: migration 06 `client_config(platform)`, `ConfigRepository` (Mock/Supabase), `AppVersion` so theo số, `UpdateGate` kiểm tra lúc mở + mỗi lần về foreground, fail-open. Cờ `-ForceUpdate`. Chụp màn chặn OK.
- **4.4 server** (agent): Edge Function `send-push` (APNs JWT ES256 qua WebCrypto, không dependency — jsr.io bị 403 nên gọi PostgREST bằng fetch), dry-run khi thiếu `.p8`, secret webhook; migration 10 trigger → `pg_net`, URL/secret trong Vault (`seeds/push_webhook_local.sql` cho local). pgTAP push 9 test.
- **2.6** (agent): `src/data/geojson/` + `build_data.py` (validate đầy đủ, `--check` cho CI) → mock JSON app → `seed.sql`, output byte-identical; 20 unittest. Hợp đồng cho crawler: `src/data/README.md`.
- **Sự cố**: Docker daemon tự tắt giữa chừng → mở lại Docker Desktop, `supabase start`. Container edge runtime thoát (255) — chạy `supabase functions serve` khi cần thử push.
- **Xác minh**: `supabase db reset` sạch (7 migration + 2 seed), pgTAP 36/36; xcodebuild test pass.

## [Phase 1 — làm toàn bộ (phần 2)] - 2026-11-07
- **3.2**: `RouteDetail` (coarse/medium/full theo `longitudeDelta`) → `routes(types, tolerance_degrees)`, cache theo bậc.
- **4.1 Auth**: `SupabaseAuthService` — email OTP (`signInWithOTP`/`verifyOTP`, mẫu email `templates/otp.html`), Apple (`AppleIDCredentialRequest`: nonce SHA-256 → `signInWithIdToken`), Google/Facebook (`signInWithOAuth`, `ancu://login-callback`). Hủy → `CancellationError`, UI không báo lỗi. Provider bật theo `ANCU_AUTH_PROVIDERS` (có Google/FB → tự thêm Apple). `EmailSignInViewModel` (chỉ giữ 6 số, gửi lại sau 30s).
- **4.2/4.5/3.6/4.7**: migration 07 (bookmark RPC, `report_data` 10/24h mã `AC429`, push token + `environment`), `SupabaseBookmarkRepository` (khách lưu `LocalBookmarkStorage` → gộp khi đăng nhập), Notification, DataReport. Migration 09: tùy chọn loại thông báo theo tài khoản, fan-out tôn trọng; màn Cài đặt thông báo lưu lạc quan, lỗi thì trả lại.
- **4.4 app**: `PushNotificationService` (xin quyền khi bật thông báo dự án — không lúc mở app; token + môi trường sandbox/production; gỡ token trước khi đăng xuất/xóa tài khoản), bấm thông báo → `DeepLinkRouter` → mở sheet dự án. `send-push` chọn host APNs theo token (sửa rủi ro xóa nhầm token agent báo).
- **5.1**: migration 08 `analytics_events` (không user_id, chỉ ghi qua `track_events`, thu hồi quyền bảng), view `analytics_weekly_retention`, `analytics_funnel_28d`. App: `BatchingAnalytics` (lô 20, 30s, flush khi vào nền, tắt được), MetricKit → `diagnostic` (chỉ số đếm). Sự kiện: app_open, project_viewed, project_saved, notify_enabled, sign_in_completed, eligibility_completed, report_submitted, compare_opened.
- **5.2**: `ConnectivityMonitor` (NWPathMonitor — framework hệ thống), nhãn ngoại tuyến + tự tải lại; gợi ý "Xem toàn vùng" khi khung nhìn trống.
- **5.3**: `docs/02-specs/security-review.md`. **Lỗ tìm thấy**: policy INSERT `data_reports` cho ghi thẳng → né rate limit → migration 11 sửa. Trần analytics 2.000/24h/install.
- **5.4**: `PrivacyInfo.xcprivacy`, bảng App Privacy + checklist nộp bản (compliance.md 2.1–2.2).
- **0.4 phụ**: `MapCameraBounds` dạng `MKCoordinateRegion` làm MapKit iOS 27 log liên tục "invalid coordinate" (đảo lat/lng nội bộ) → đổi sang `MKMapRect`, hết log.
- **Lỗi đã sửa khi test**: SQL `on conflict (user_id, …)` mơ hồ với tham số cùng tên → `on conflict on constraint`; SQLSTATE lớp 22/23 bị map thành `.network` → `.decoding`.
- **Xác minh**: `supabase db reset` sạch (11 migration, 2 seed), pgTAP 64/64 (4 file), lint `public` sạch. iOS 172/172 test (gồm integration với stack local: vòng đời tài khoản email OTP qua Mailpit, bookmark, báo sai, inbox, tùy chọn thông báo, analytics, xóa tài khoản). Chụp: "Gần tôi", màn chặn cập nhật, màn đăng nhập (local chỉ email), bản đồ dữ liệu Supabase.
- **Chưa xác minh**: Apple/Google/Facebook, APNs thật, TestFlight (cần tài khoản); Hoàng Sa/Trường Sa trên máy thật; 2 lần treo test song song (ghi nợ kỹ thuật).

## [Highlight vùng khi chọn chip TP.HCM / Bình Dương / Đồng Nai] - 2026-11-07
- **Quyết định của bạn**: ranh giới mock giản lược; kiểu nổi bật = viền + tô nhạt.
- **Dữ liệu**: `src/data/geojson/service_areas.geojson` (3 đa giác, ~15–25 đỉnh, chung đỉnh ở biên giáp nhau). `build_data.py` thêm kiểm tra: vòng khép kín, không lỗ, mỗi vùng 1 feature, **dự án phải nằm trong vùng của nó** (bắt được khi vẽ: Thuận An, Biên Hòa nằm sát biên). 27 unittest.
- **DB**: migration 12 bảng `service_area_boundaries` + RPC `service_area_boundary` (giản lược tùy chọn). pgTAP thêm 3 (gồm `ST_Covers`: mọi dự án trong vùng) → 67/67.
- **App**: `AreaBoundary`, `LookupRepository.boundary(of:)` (Supabase cache cả "không có"), `MapViewModel.focus` tải ranh giới → `focusedBoundary` + camera ôm vùng; bỏ chọn/đổi vùng hủy tải cũ. `MapPolygon` tô 16% + halo trắng 7pt + viền đứt nét 3pt. Cờ `-FocusArea <code>`.
- **Lỗi phát hiện khi chụp**: (1) `.region` không ôm trọn khung ở màn dọc → đổi sang `.rect(MKMapRect)`; (2) `maxCameraDistance` 250 km chỉ thấy ~75 km bề ngang → camera bị kẹp, không ôm được tỉnh → nâng 600 km, test chủ quyền đổi sang tỉ lệ nửa đường chéo đo được; (3) mock Đồng Nai lấn sang Đồng Xoài (Bình Phước) → sửa biên bắc. Đỉnh thẳng hàng bị `ST_SimplifyPreserveTopology` bỏ là đúng — sửa test cho phù hợp.
- **Xác minh**: iOS 176/176 (gồm integration), chụp TP.HCM và Đồng Nai trên stack local.

## [Đưa backend lên Supabase cloud (gói Free)] - 2026-11-07
- **Project**: `ancu` (`minfsjbwcmxgoqiptjka`). Tạo bằng region "auto" → Supabase xếp vào **Mumbai `ap-south-1`**; bạn quyết định giữ cho dev, tạo lại ở Singapore sau (nợ kỹ thuật). Bài học: luôn chỉ định region cụ thể.
- **Bẫy CLI 3.x**: `supabase db push` mặc định nhắm **stack local** → lần đầu "thành công" nhưng cloud không có bảng. Phải `--remote`. Sửa lệnh trong `CLAUDE.md`, `src/supabase/README.md` (mục "Triển khai cloud").
- **Schema + dữ liệu**: `db push --remote` 12/12 migration, lint sạch; `seed.sql` nạp bằng `psql` qua Session pooler (không `--include-seed` — sẽ ghi Vault local lên cloud).
- **Auth**: cloud không cho sửa email template khi dùng SMTP mặc định → cấu hình SMTP Gmail (app password) tạm cho dev; template Magic link + Confirm signup = `templates/otp.html`, OTP 6 số.
- **App**: `Config/Secrets-Debug.xcconfig` (URL + key publishable, gitignore). Xác minh: log simulator gọi `minfsjbwcmxgoqiptjka.supabase.co/rest/v1/rpc/…`; bản đồ hiện dự án, tuyến, highlight TP.HCM từ cloud; bạn thử đăng nhập email OTP, lưu dự án, analytics — OK.
- **Còn lại trước phát hành**: SMTP domain riêng, `Secrets-Release.xcconfig`, project Singapore + Pro, Vault/Edge Function push khi có APNs key.

## [Ghi nhớ chip bản đồ (UserDefaults)] - 2026-11-07
- **Quyết định của bạn**: nhớ lớp tuyến + "Đang nhận hồ sơ" + vùng; không nhớ "Đã lưu". Khôi phục vùng có bay camera, deep link ưu tiên. Ghi ở architecture.md 5.6.
- **Code**: `MapPreferences` + protocol `MapPreferencesStore` (Domain), `UserDefaultsMapPreferencesStore` (key `map.preferences`, JSON) + `InMemoryMapPreferencesStore` (Data/Local), inject qua `AppContainer.mapPreferences`. `MapViewModel`: khôi phục lớp tuyến/bộ lọc trong `init` (trước lần tải đầu), vùng sau khi có danh mục; lưu ở `didSet`.
- **Thiết kế**: lưu lớp tuyến **đã tắt** (loại mới thêm sau tự bật, "tắt hết" vẫn nhớ được); lưu mã, mã lạ bỏ qua; thiếu khóa → mặc định; vùng ngoài MVP → bỏ và ghi lại.
- **Sửa kèm**: ranh giới tải xong không còn giật camera về khung vùng nếu đã có yêu cầu camera mới hơn (chọn dự án/tìm kiếm/deep link trong lúc đang tải) — lỗi tiềm ẩn có từ trước. Cờ `-FocusArea` không còn bỏ chọn khi vùng đã được khôi phục (focus là toggle). Cờ mới `-ResetMapPreferences`.
- **Xác minh**: 10 test mới (`MapPreferencesTests`), toàn bộ 230 test case pass. Simulator (backend cloud): mở với `-FocusArea dong_nai_cu` → tắt → mở lại không cờ → Đồng Nai được chọn lại, highlight + camera ôm vùng.

## [Địa điểm đã lưu + ghi chú (PRD 4.6)] - 2026-11-07
- **Quyết định của bạn**: riêng tư; `saved_places` cho dự án ngoài hệ thống, `bookmarks` (+ `note`) cho dự án có sẵn; bắt buộc đăng nhập; không lưu ngoài vùng MVP (có thông báo); chống trùng 300 m; loại NOXH · Thương mại · Khác; ghim tay; ghim trên bản đồ trong lớp "Đã lưu". App Privacy: dùng "Other User Content" đã khai, Physical Address chờ luật sư (0.5 câu d).
- **DB (migration 13)**: `saved_places` (RLS chỉ đọc của mình, ghi qua RPC SECURITY DEFINER, ≤ 200 với advisory lock, vùng MVP `ST_DWithin` 3 km), `bookmarks.note` + `set_bookmark_note`, `data_reports.kind` + `suggest_project` (chung giới hạn 10/24h, không gửi ghi chú), `place_kinds` chèn trong migration (cloud không chạy seed) + seed `on conflict do update`. pgTAP +33 → 100/100, lint sạch.
- **App**: `SavedPlace`/`PlaceKind`/`ServiceAreaLocator` (cùng quy tắc server), `SavedPlaceRepository` (Mock/Supabase), `PlaceSearchService` → `MKLocalSearch` (framework hệ thống). Tìm kiếm 2 nhóm (An Cư trên, Apple Maps dưới; ngoài vùng mờ + nhãn). `PlaceEditorSheet` (tên/loại/ghi chú, gợi ý dự án trùng, đề xuất NOXH). Nhấn giữ bản đồ → ghim tay (ngoài vùng → alert). Ghi chú trong sheet dự án. Tab Theo dõi: "Địa điểm của tôi". Ghim ô vuông theo loại trong lớp "Đã lưu". Lỗi mới `outsideServiceArea`/`limitReached` (AC403/AC409).
- **Xác minh**: iOS 266 test case pass (gồm integration với stack local: tạo/sửa/xóa, ngoài vùng, ghi chú bookmark, đề xuất, xóa tài khoản xóa theo). Chụp: tìm "vinhomes" ra kết quả Apple Maps thật; tab Theo dõi; lớp "Đã lưu" trên bản đồ. Sửa sau khi chụp: icon ghim bị chồng → ô vuông viền trắng.
- **Phát hiện**: Apple Maps trả lẫn khách sạn/căn hộ dịch vụ ("Vinhomes … by Bevista") — đúng dự đoán, ghim tay là đường lui. Chưa xác minh điều khoản MapKit về lưu tọa độ (chỉ lưu dữ liệu người dùng xác nhận).
- **Còn lại**: đẩy migration 13 lên cloud (chờ bạn). Để sau: so sánh khoảng cách ga cho địa điểm riêng; phát hiện trùng khi dự án được thêm vào hệ thống.

## [Xem trên bản đồ trước khi lưu + chỉnh vị trí bằng kéo bản đồ] - 2026-11-07
- **Yêu cầu của bạn**: bấm kết quả tìm kiếm / nhấn giữ → hiện trên map trước, không mở form lưu ngay; chỉnh vị trí bằng cách di chuyển map. Kèm: viền vùng mảnh nét đứt 1,5pt (bỏ halo trắng).
- **Thiết kế**: ghim cố định giữa màn hình (mẫu Grab/Uber), tâm bản đồ = điểm chọn (`onMapCameraChange(.continuous)`), kiểm tra vùng khi camera dừng. Thẻ dưới đáy: trạng thái vùng + Hủy / Lưu tại đây; ẩn thanh tìm kiếm/chip khi đang chọn. Hủy trong form → quay lại chế độ chọn; lưu xong → thoát. Ngoài vùng không còn alert — nút Lưu tắt, kéo lại vào vùng là lưu được. Dời > 100 m khỏi kết quả Apple Maps → bỏ địa chỉ + mã Apple Maps.
- **Code**: `PlacePick` + `startPick` / `pickCenterDidChange` / `pickCenterDidSettle` / `cancelPick` trong `MapViewModel`; `PlacePickViews.swift` (ghim tâm, gợi ý, thẻ). Cờ `-PickAt lat,lng`.
- **Xác minh**: 4 test mới, 261 test case pass. Chụp: chọn ở Thảo Điền (trong TP.HCM, nút Lưu bật) và biển Vũng Tàu (ngoài vùng, nút tắt). Sửa sau khi chụp: thân ghim lệch màu đầu ghim.

## [Địa chỉ cập nhật theo vị trí ghim + nút X tìm kiếm] - 2026-11-07
- **Nút X ô tìm kiếm không phản hồi**: vùng chạm chỉ là icon ~17pt → mở rộng 44×44 (HIG), bù padding để thanh không đổi kích thước. Chưa tái hiện được bằng chạm thật (simctl không tap) — chờ bạn thử lại.
- **Địa chỉ theo ghim** (yêu cầu của bạn): `ReverseGeocoder` (Domain) → `MapKitReverseGeocoder` (`MKReverseGeocodingRequest` iOS 26+, `CLGeocoder` cũ hơn; framework hệ thống) + `MockReverseGeocoder`. Tra khi camera dừng (debounce 0,5 s, hủy lần cũ, bỏ kết quả lỗi thời). Kết quả Apple Maps chưa dời > 100 m → giữ địa chỉ gốc. Địa chỉ lưu = địa chỉ đang hiện.
- **Phát hiện khi chụp**: Simulator tiếng Anh → Apple trả "42 Thong Nhat, Thu Duc" (mất dấu) → ép `preferredLocale = vi_VN` → "42 Thống Nhất, P. Thủ Đức" (tên phường mới sau sáp nhập).
- **Xác minh**: 3 test mới (địa chỉ theo ghim, dời xa tra lại, kết quả cũ không ghi đè), 263 test case pass.

## [Icon tự chọn cho địa điểm đã lưu] - 2026-11-07
- **Quyết định của bạn**: bộ ~16 icon có sẵn (không màu tự chọn, không emoji).
- **Thiết kế**: lưu MÃ danh mục `place_icons` (vd `cho_lam`), không lưu tên SF Symbol → Android map được, server thêm icon (kèm `sf_symbol`) không cần phát hành app. `nil` = icon theo loại; màu ghim vẫn theo loại.
- **DB (migration 14)**: `place_icons` chèn trong migration, `saved_places.icon` + FK, `saved_place_json` trả `icon`, `create_saved_place` / `update_saved_place` thêm `icon` — **drop chữ ký cũ** (PostgREST không chọn được giữa 2 hàm trùng tên). pgTAP +8 → 108/108, lint sạch.
- **App**: `LookupCategory.placeIcon`, `catalog.placeIconSymbol`, `SavedPlace.icon`, repository `update(…icon…)`, `PlaceIconPicker` (lưới, ô đầu "Theo loại"), ghim + thẻ vẽ theo icon. Cờ `-EditFirstPlace`.
- **Xác minh**: 222 test (47 suite) pass tuần tự gồm integration local; 1 test cũ fail đúng dự đoán (tập tham số gửi đi có thêm `icon`) → cập nhật. Lần chạy song song đầu kéo dài > 10 phút (nợ kỹ thuật treo test song song) nhưng vẫn hoàn tất. Chụp lưới icon.
- **Còn lại**: đẩy migration 14 lên cloud (chờ bạn) — trước khi đẩy, app trỏ cloud sẽ lỗi khi lưu/sửa địa điểm.

## [Ghim cố định trên bản đồ, kéo ghim để chỉnh] - 2026-11-07
- **Góp ý của bạn**: ghim giữa màn hình (kéo map = đổi điểm) không cho zoom in/out khi đang ghim → đổi: ghim cố định theo tọa độ, chỉ kéo ghim mới đổi vị trí.
- **Code**: ghim là `Annotation` (anchor `.bottom` = mũi ghim) + `DragGesture(.global)`; lúc bắt đầu kéo lưu vị trí màn hình của mũi ghim (`MapProxy.convert`) rồi cộng quãng kéo → không nhảy theo chỗ ngón tay chạm đầu ghim. Ghim phóng 1,2× + rung nhẹ khi nhấc. Thả → kiểm tra vùng + tra địa chỉ. Bỏ theo dõi camera liên tục. Nút "Đưa ghim vào giữa" (ghim trôi khỏi màn hình; cách chỉnh cho VoiceOver). `MapViewModel`: `movePick(to:)` / `finishMovingPick()`.
- **Xác minh**: 2 test mới (kéo/zoom map không đổi điểm chọn; đưa ghim vào giữa), 224 test pass. Chụp giao diện. **Chưa kiểm được thao tác kéo thật** (simctl không kéo được) — cần thử trên máy.

## [Màu tuyến theo loại + chạm tuyến xem tên] - 2026-11-07
- **Ý tưởng của bạn**: Metro/Vành đai/Cao tốc/Quốc lộ phân biệt bằng màu, nhiều metro vẫn một màu. Đồng ý + 2 điều chỉnh: đổi bảng màu (Metro đỏ → xanh dương vì đỏ cạnh cam khó phân biệt với mù màu đỏ–lục; Cao tốc tím → hồng đậm vì trùng ghim "Đang xây"); chạm tuyến để biết tên (cùng màu thì mất phân biệt từng tuyến).
- **Code**: `LookupCatalog.color(for: RouteType)` từ `route_types.color_hex` (fallback token `routeMetro/Ring/Expressway/National`), bỏ `InfraRoute.displayColor`. `RouteHitTester` (khoảng cách điểm–đoạn, mét) + `MapViewModel.selectRoute(near:toleranceMeters:)`; MapScreen quy 22pt ra mét theo zoom qua `MapProxy`. Tuyến chọn: halo trắng + đậm hơn, tuyến khác mờ 30%; `RouteInfoCard` (loại · tên · trạng thái · năm). Ẩn loại tuyến đang chọn / bắt đầu chọn vị trí / mở dự án → bỏ chọn tuyến. Chú giải: mục "Màu theo loại tuyến". Migration 15 (màu `route_types`). Cờ `-SelectRouteAt`.
- **Xác minh**: 8 test mới (hit test, màu 4 loại khác nhau từ catalog, chọn/bỏ chọn, loại ẩn không chọn được, chọn vị trí chặn chọn tuyến); 230 test pass gồm integration; pgTAP 108/108. Chụp: tổng quan TP.HCM và chọn Metro số 2.

## [Cùng độ rộng line, trạng thái bằng kiểu nét] - 2026-11-07
- **Góp ý của bạn** (ảnh iPhone): line không đều. Nguyên nhân: không phải lỗi vẽ — độ dày đang mã hóa trạng thái (đã khai thác 5pt, đang thi công 3pt); khi các tuyến cùng loại cùng màu, khác biệt độ dày bị đọc thành lỗi. Ảnh iPhone vẫn metro đỏ vì cloud chưa có migration 15.
- **Đổi (bạn chọn)**: mọi tuyến 4pt; đã khai thác = liền, đang thi công = gạch dài 12–4, quy hoạch = gạch ngắn 4–6 mờ 60%. **Bẫy đã tránh**: đầu nét `.round` lấn lineWidth/2 mỗi bên vào khe → khe 4pt bị lấp kín, nét đứt nhìn như liền → nét đứt dùng `.butt`.
- **Xác minh**: 3 test mới (cùng độ rộng, 3 kiểu nét khác nhau, nét đứt đầu vuông) → 233 test pass. Chụp phóng to trung tâm TP.HCM: Metro 2 / Vành đai 3 gạch dài, Cao tốc / Quốc lộ liền, cùng độ rộng.
- **Đổi tiếp (góp ý)**: đang thi công = **gạch chấm** `[10, 4, 3, 4]` (chấm 3pt để thấy rõ ở nét 4pt đầu vuông). Test giữ mẫu gạch–chấm; 233 test pass; chụp: Metro 2 / Vành đai 3 gạch chấm.
- **"Nét đứt vẫn to hơn" (ảnh iPhone)**: đo pixel trên ảnh của bạn — liền 13,1px ≈ 4,4pt, gạch chấm 13,4px ≈ 4,5pt → bằng nhau; Simulator cũng vậy. Là ảo giác (đầu vuông khối đặc, nhịp đặc–rỗng, nét liền gần dọc mép khử răng cưa). Bạn chọn **bù thị giác**: liền 4,5pt, đứt/gạch chấm 3,5pt. Test chốt chênh đúng 1pt; 233 test pass; chụp so sánh cùng vị trí.
- **Quay lại (theo bạn)**: mọi tuyến 4pt; liền / gạch dài 12–4 / gạch ngắn 4–6 mờ 60%. Bỏ gạch chấm và bù thị giác.

## [Staging dữ liệu (schema ingest) + crawler tách biệt + geometry_accuracy] - 2026-11-08
- **Quyết định của bạn**: dữ liệu thu thập vào schema riêng, admin duyệt mới vào bảng chính; crawler ở folder riêng; chốt theo đề xuất: `src/crawler/` (httpx, beautifulsoup4, pdfplumber — ghim phiên bản), staging gồm tuyến + ga + dự án, thêm `geometry_accuracy`; duyệt bằng DBeaver (user postgres).
- **DB (migration 16)**: schema `ingest` (không mở API, thu hồi quyền anon/authenticated, RLS): `batches`, `route/node/project_candidates` (+ `raw`, `evidence_url`, `review_status`, `validation_errors` do trigger tính), mỗi id 1 bản pending (bản mới → `superseded`), view `pending_review` (trường đổi, dời mét qua UTM 48N). `approve_route/node/project` (dự án: admin truyền lat/lng nếu thiếu), `approve_batch` all-or-nothing, `reject` (bắt buộc lý do). `verified_at` = ngày duyệt; đợt `silent` → cờ phiên `ancu.silent_ingest` (đặt lại mỗi lần duyệt, không lây) → fan-out bỏ qua, `project_updates` vẫn ghi. `geometry_accuracy` cho tuyến/ga + trong `routes()` / node JSON.
- **Lỗi bắt được bằng pgTAP**: (1) `text[] || 'chuỗi'` bị hiểu là mảng → `array_append`; (2) **Postgres kiểm CHECK trên dòng định chèn TRƯỚC khi xét ON CONFLICT** → bản nháp chỉ có `price_max` (trống = giữ cũ) vi phạm "giá đủ cặp" → dự án đã có dùng UPDATE, dự án mới bắt buộc đủ cặp ngay khi ghi.
- **`src/data`**: `staging.py` + `build_data.py --stage FILE | --stage-manual` → `data/out/stage.sql` (thư viện chuẩn; `python3 -I` cần tự thêm sys.path). Contract v1 (khối `ancu`). Kiểm 2 tầng: Python cấu trúc, DB nghiệp vụ. Thử local: 45 bản nháp mock → `approve_batch` → 11 tuyến + 34 ga.
- **`src/crawler`**: venv riêng, KHÔNG có thông tin DB. `fetch.py` (robots.txt — không đọc được = chặn, ≥ 3 s/host, User-Agent, retry + Retry-After, lưu bằng chứng), `contract.py` (UUID v5 ổn định, Run → features.geojson + report.json), CLI, `sources.json` (2 nguồn chưa khảo sát). Test không mạng (MockTransport) + **test contract phía tiêu thụ** bằng chính `staging.py`.
- **App**: `GeometryAccuracy` (thiếu → minh họa), thẻ tuyến cảnh báo "Hướng tuyến minh họa…", chi tiết dự án ghi "vị trí ga minh họa/gần đúng".
- **Xác minh**: pgTAP 140/140; data 37/37; crawler 9/9; iOS 237 test gồm integration. Chụp thẻ tuyến có cảnh báo.
- **Còn lại**: đẩy migration 16 lên cloud (chờ bạn); nguồn crawl đầu tiên sau khảo sát.

## [Nguồn crawl đầu tiên: Sở XD TP.HCM (phương án A)] - 2026-11-08
- **Khảo sát** (~6 request, ≥ 4 s/request): robots.txt cho phép `/Tin-tuc/`, `/DesktopModules/MVC/`; danh sách NOXH nạp bằng JS (GET `…/BaiViet/StyleView?ViewStyle=DanhSach&moduleID=2635`, header ModuleId/TabId — đúng request trình duyệt gửi); bài "Danh mục các dự án NOXH đang tiếp nhận hồ sơ" (06/11/2026): mỗi dự án 1 dòng (tên có dấu, số văn bản, ngày) + 1 PDF. **Tải PDF → F5 WAF "Request Rejected" → dừng, không lách.** Ghi `sources.json`.
- **Bạn**: không ghi liên hệ vào User-Agent (giữ `AnCuCrawler/0.1`, vẫn tự xưng bot); chọn phương án A (crawler đọc danh mục, bạn tải PDF tay, `--pdf-dir` ghép theo số văn bản).
- **Code**: `sources/so_xay_dung_hcm.py` (tìm bài danh mục, parse dòng, phát hiện link PDF sai, đoán vùng chỉ theo tên không trùng), `pdf_fields.py` (thời gian tiếp nhận / số căn / giá đồng/m² — chỉ điền khi chắc, kèm đoạn trích; PDF scan → cảnh báo), `Fetcher.get(params, headers)` (cấm đổi User-Agent). Fixture = trích HTML thật; test chặn mọi request tới `/Files/`.
- **Chạy thật**: lần 1 robots.txt timeout → crawler chặn đúng thiết kế; lần 2: **4 dự án** (Long Trường; 35 Lê Văn Chí; Thạnh Tân GĐ1; Hiệp Thành III) → staging local: 2 hợp lệ chờ vị trí, 2 thiếu địa chỉ/vùng. Trang Sở có link sai (37302 → file 33745) — phát hiện + cảnh báo.
- **Sửa sau chạy thật**: bỏ gợi ý vùng theo tên phường trùng nhiều nơi (Hiệp Thành: Quận 12 và Thủ Dầu Một; Thạnh Tân).
- **Xác minh**: crawler 19/19 test. Chưa biết PDF là chữ hay scan.
- **Tổ chức lại + README "Chạy một lần crawl"**: module dùng chung vào `ancu_crawler/core/` (fetch, contract, pdf_fields, source), `sources/` chỉ code riêng từng nguồn. README thêm hướng dẫn 7 bước (cài → crawl → đọc cảnh báo → PDF tay → staging local → staging cloud → duyệt DBeaver → kiểm tra) + bảng xử lý cảnh báo. **Lỗi bắt được khi chạy thử README**: `pip install -e .` (setuptools editable) làm `ancu_crawler` mất `__init__.py`/`__main__.py` và bị nhận thành namespace package → bỏ `pyproject.toml`, cài bằng `requirements.txt`, chạy crawler trong `src/crawler`; khôi phục 2 file từ git. Kiểm lại bằng venv mới: test OK, `list` OK.
- **Đổi tên package** `ancu_crawler` → `app` (theo bạn; bớt lặp với thư mục project `src/crawler`): chạy `python -m app run <nguồn>`. Giữ 2 tầng (thư mục project / package) để tách code khỏi runs/, pdf/, .venv, tests.

### 2026-11-08 — Vùng phục vụ theo tỉnh mới (Plan Bước 8)
- **Phạm vi**: 5 tỉnh MỚI sau 1/7/2025 — TP.HCM (gồm Bình Dương cũ, BR-VT cũ), Đồng Nai (gồm Bình Phước cũ), Tây Ninh, Đồng Tháp, Lâm Đồng. Mã cũ giữ trong danh mục (`in_mvp=false`, `merged_into`), thêm `ha_noi` (chưa phục vụ) để "Sắp có" vẫn có nội dung.
- **DB**: migration 17 — danh mục, chuyển mã cũ ở mọi bảng (kể cả bản nháp ingest đang chờ), `validate_project` chỉ nhận vùng `in_mvp`, ranh giới mock 5 tỉnh (ST_Union từ ranh giới thành phần, không chồng lấn).
- **App**: enum `ServiceArea` mới; khung camera vĩ 10,0–12,6 · kinh 105,3–108,5, `maxCameraDistance` 750 km (test chủ quyền pass); chip vùng cuộn ngang (5 chip bị cắt chữ khi nằm trong HStack cố định); "Sắp có" bỏ mã đã gộp.
- **Crawler**: `AREA_HINTS` → `tp_hcm`; Hiệp Thành nay đoán được (Q.12 và Thủ Dầu Một cùng TP.HCM mới), Thạnh Tân vẫn để trống.
- **Xác minh**: iOS 237/237 (kèm integration local), pgTAP 156/156, lint public+ingest sạch, data 37/37, crawler 20/20; ảnh chụp chip + highlight Lâm Đồng/Tây Ninh/Đồng Tháp với `-Backend local`.
- **Nợ**: ranh giới mock thô — Tây Ninh lấn sang Svay Rieng/Bavet (Campuchia), Đồng Tháp lấn bờ nam sông Tiền (Vĩnh Long). Cần ranh giới thật trước khi lên store. Lâm Đồng mới (~250 km cao) không vừa một màn hình ở zoom tối đa.
- **Cờ ẩn/hiện tỉnh (migration 18)**: dùng chính `in_mvp` (không thêm cờ thứ hai). Hàm admin `ingest.set_service_area_active(code, active, reason)` — chặn mã đã gộp, bật tỉnh chưa có ranh giới, tắt vùng cuối cùng; ghi `paused_reason`/`paused_at`. `projects_in_bbox`/`search_places` ẩn dự án tỉnh tạm ngừng (bookmark vẫn mở). Xác minh: pgTAP 173/173 (+17), iOS 240/240 (+3 PausedAreaTests). Sự cố: simulator treo (xcodebuild lặp `simctl diagnose`) → shutdown/boot lại.
- **Ranh giới thật 3 tỉnh (migration 19)**: TP.HCM, Đồng Nai, Tây Ninh từ sapnhap.bando.com.vn (người dùng lưu response `pread_json` từng tỉnh; file thô gitignore). Diện tích lệch so với số chính thức: 0,5% / 0,0% / 0,1%. Đồng Tháp, Lâm Đồng mock cắt theo ranh giới thật. Camera chip ôm đa giác lớn nhất (bỏ Côn Đảo). pgTAP: chồng lấn ngưỡng 1.000 m², TP.HCM 7 đa giác.
- **POI tiện ích**: bản đồ hiện trường học, đại học, bệnh viện, sân bay, giao thông công cộng, cửa hàng/TTTM, chợ, công viên (`MapScreen.amenityCategories`), chỉ hiển thị. Nhìn cả vùng chỉ còn sân bay Long Thành; zoom gần mới hiện chi tiết.
