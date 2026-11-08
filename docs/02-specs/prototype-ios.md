# Prompt Prototype iOS — An Cư (SwiftUI · Liquid Glass · Mock data)

> Trạng thái: **đã chốt** 2026-11-06. Dùng làm spec khi scaffold `src/ios/`.
> Quyết định đã chốt: vùng MVP **TP.HCM (gồm Bình Dương cũ) + Đồng Nai** · deployment target **iOS 17 + fallback**, Liquid Glass chỉ bật trên iOS 26+.
> Đã chốt 2026-11-07: thêm loại tuyến `cao_toc` vào PRD/`schema.md`.
> Thay đổi 2026-11-07 theo luật hiện hành (NĐ 54/2026, NĐ 136/2026): wizard điều kiện còn **4 bước** (bỏ "Nơi làm việc"; hôn nhân có thêm "độc thân nuôi con dưới 18 tuổi"; nhà ở xét tại tỉnh có dự án). Mục 7 bên dưới giữ nguyên bản gốc để tham chiếu.
> Cách dùng: không chạy cả prompt một lần. Làm theo thứ tự ở mục 11, mỗi bước build/test xong mới qua bước sau.
> Xem trước UI: `prototype-preview/` (HTML + PNG).

---

````text
Hãy viết một prototype iOS bằng SwiftUI cho app "An Cư". App giúp người mua nhà ở xã hội (NOXH) tại TP.HCM, Bình Dương cũ và Đồng Nai xem dự án trên bản đồ cùng hạ tầng giao thông tương lai (Metro, Vành đai, Cao tốc), theo dõi đợt nhận hồ sơ và tự kiểm tra điều kiện mua.
Đây KHÔNG phải code dùng một lần: tôi sẽ phát triển tiếp chính codebase này thành app thật. Kiến trúc phải đúng chuẩn production ngay từ đầu, chỉ có data là mock.

# 1. Ràng buộc kỹ thuật
- Build bằng Xcode mới nhất (SDK iOS 26+). Deployment target iOS 17.
- Liquid Glass chỉ bật trên iOS 26+ qua `if #available(iOS 26, *)`. Từ iOS 17 đến iOS 25 fallback về `.ultraThinMaterial`.
- MỌI hiệu ứng kính phải đi qua modifier trong Core/DesignSystem/Glass.swift. Feature code KHÔNG gọi trực tiếp `.glassEffect()` hay `.ultraThinMaterial`. Các API chỉ có trên iOS 26 (GlassEffectContainer, glassEffectID, .buttonStyle(.glass/.glassProminent), tabBarMinimizeBehavior) cũng phải bọc trong DesignSystem.
- Tôn trọng Reduce Transparency và Increase Contrast: khi bật thì fallback về nền đặc `Color(.secondarySystemBackground)`. Tôn trọng Reduce Motion.
- State: @Observable + @MainActor ViewModel. Không dùng ObservableObject/Combine. Swift 6 strict concurrency.
- MapKit for SwiftUI (Map, Annotation, MapPolyline, MapCameraPosition). NavigationStack.
- Không thêm third-party dependency. Không gọi network.
- Toàn bộ text UI bằng tiếng Việt có dấu, gom vào Localizable.xcstrings.
- Có SwiftUI #Preview cho mọi màn hình chính, dùng mock data.

# 2. Kiến trúc (MVVM + Repository Pattern)
Mục tiêu: sau này thay backend (Supabase, rồi có thể .NET) mà không phải sửa View/ViewModel.
- Domain/: model Swift thuần, `Sendable`, `Hashable`, không import thư viện backend.
- Data/Mock/: DTO `Codable` (key snake_case, giống schema DB) + mapper DTO → Domain + `Mock*Repository` đọc JSON trong bundle. Giả lập độ trễ 300ms để UI có loading/skeleton state.
- Composition root `AppContainer` tạo repository và inject vào ViewModel qua `init`. Không dùng singleton bên trong repository.
- Lỗi luôn map về `enum RepositoryError: Error { case unauthorized, notFound, rateLimited, network, decoding }`.
- Các protocol:
```swift
protocol ProjectRepository: Sendable {
    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project]
    func project(id: Project.ID) async throws -> ProjectDetail   // gồm ga/nút giao gần nhất
    func search(_ query: String) async throws -> [SearchResult]   // tìm theo tên mới + tên cũ
}
protocol InfrastructureRepository: Sendable {
    func routes(types: Set<RouteType>) async throws -> [InfraRoute]
}
protocol LookupRepository: Sendable {
    func catalog() async throws -> LookupCatalog   // load 1 lần, cache trong memory
}
protocol BookmarkRepository: Sendable {
    func all() async throws -> [Bookmark]
    func toggle(projectID: Project.ID) async throws
    func setNotify(_ on: Bool, projectID: Project.ID) async throws
}
protocol NotificationRepository: Sendable { func inbox() async throws -> [AppNotification] }
protocol EligibilityRepository: Sendable { func currentRules() async throws -> [EligibilityRule] }
protocol AuthService: Sendable {
    var currentUser: AppUser? { get async }
    func signIn(with provider: AuthProvider) async throws -> AppUser   // mock: thành công ngay
    func signOut() async throws
    func deleteAccount() async throws
}
```
- Mock implementation: `MockProjectRepository`, `MockInfrastructureRepository`, `MockLookupRepository`… Bookmark lưu local (UserDefaults) để còn sau khi khởi động lại app.
- Logic kiểm tra điều kiện là một pure function `EligibilityEvaluator.evaluate(answers:rules:) -> EligibilityResult`, có unit test.

# 3. Cấu trúc thư mục
```
AnCu/
  App/              AnCuApp.swift, AppContainer.swift, RootTabView.swift
  Core/
    DesignSystem/   Colors.swift, Glass.swift, Typography.swift, Spacing.swift,
                    MeshBackground.swift, components (StatusBadge, MetricTile, GlassCard, PrimaryButton)
    Extensions/
  Domain/
    Models/         Project, ProjectDetail, InfraRoute, InfraNode, Bookmark, AppNotification, EligibilityRule, LookupCatalog...
    Repositories/   các protocol ở mục 2
    Services/       EligibilityEvaluator, DistanceFormatter
  Data/
    Mock/
      DTO/  Mappers/  Repositories/
      Resources/
        projects.json, routes.json, nodes.json, notifications.json
        Lookup/ project_statuses.json, legal_statuses.json, route_types.json,
                route_statuses.json, node_types.json, service_areas.json,
                administrative_units.json, eligibility_subjects.json,
                housing_conditions.json, notification_types.json, eligibility_rules.json
  Features/
    Map/          MapScreen, MapViewModel, ProjectPinView, ClusterView, LayerChipsBar, LegendSheet, ProjectDetailSheet
    Tracking/     TrackingScreen, TrackingViewModel, SavedProjectCard, CompareView, InboxView, SignInPromptView
    Account/      AccountScreen, AccountViewModel, SettingsList, DeleteAccountFlow
    Eligibility/  EligibilityWizard, EligibilityViewModel, step views, EligibilityResultView
AnCuTests/        EligibilityEvaluatorTests, MapperTests, MockRepositoryTests
```

# 4. Lookup data (danh mục dùng chung, KHÔNG hardcode trong View)
Mỗi file JSON là một mảng `{ "code", "label_vi", "sort_order", ... }`. Ở Domain, các danh mục này là enum có `rawValue` = `code`, còn label/màu/icon lấy từ `LookupCatalog`, để sau này đổi text/màu từ server mà không phải phát hành app.
- project_statuses: sap_mo (Sắp mở), nhan_ho_so (Đang nhận hồ sơ), da_dong (Đã đóng), dang_xay (Đang xây dựng). Kèm `color_hex`, `sf_symbol`.
- legal_statuses: chu_truong_dau_tu, da_co_giay_phep_xd, du_dieu_kien_ban, da_ban_giao.
- route_types: metro, vanh_dai, cao_toc, quoc_lo.
- route_statuses: quy_hoach, dang_thi_cong, da_khai_thac. Kèm `line_style` (dashed / thin / solid).
- node_types: ga_metro, nut_giao, diem_hat_nhan (vd sân bay).
- service_areas: hcm_cu (TP.HCM cũ), binh_duong_cu (Bình Dương cũ), dong_nai_cu (Đồng Nai cũ).
  Mỗi vùng gồm `label_vi`, `new_province` (TP.HCM / Đồng Nai), `center`, `in_mvp: true`.
  Thêm ba_ria_vung_tau_cu và binh_phuoc_cu với `in_mvp: false`. UI hiển thị "Sắp có" nếu người dùng tìm tới hai vùng này.
- administrative_units: phường/xã theo địa giới mới. Mỗi đơn vị có `service_area`, `old_names` (tên quận/huyện/thị xã cũ như "Thủ Đức", "Dĩ An", "Biên Hòa", "Nhơn Trạch") để tìm kiếm. Khoảng 20 đơn vị. Ghi chú MOCK, cần đối chiếu danh mục chính thức.
- eligibility_subjects: thu_nhap_thap_do_thi, cong_nhan, can_bo_cong_chuc, luc_luong_vu_trang, ho_ngheo_can_ngheo, khac.
- housing_conditions: chua_co_nha, nha_duoi_15m2_nguoi, da_co_nha.
- notification_types: mo_nhan_ho_so, doi_gia, doi_trang_thai. Kèm `sf_symbol`, `color_hex`.
- eligibility_rules: `{ rule_key, value, legal_reference, effective_from }`. Ví dụ ngưỡng thu nhập người độc thân / đã kết hôn, kèm dẫn chiếu Luật Nhà ở 2023 và Nghị định 100/2024/NĐ-CP. Giá trị là MOCK và phải gắn nhãn MOCK cả trên UI.

# 5. Mock data
- Map khởi tạo ở khoảng (10.88, 106.80), span đủ phủ Thủ Dầu Một – Biên Hòa – Long Thành – trung tâm TP.HCM. Có segmented control đổi nhanh vùng: TP.HCM / Bình Dương / Đồng Nai.
- projects.json: 15 dự án NOXH tên hư cấu (không dùng tên chủ đầu tư thật), rải theo vùng:
  TP.HCM cũ (Thủ Đức, Bình Chánh, Nhà Bè, Củ Chi), Bình Dương cũ (Dĩ An, Thuận An, Bến Cát, Thủ Dầu Một), Đồng Nai cũ (Biên Hòa, Long Thành, Nhơn Trạch).
  Giá 15–30 triệu/m². Đồng Nai và Bình Dương cũ rẻ hơn TP.HCM cũ. 300–1.500 căn. Trạng thái phân bố đều.
  `application_window` có cái đang mở / sắp mở / đã qua so với ngày hiện tại. Mỗi dự án bắt buộc có `source_url`, `verified_at`, `service_area`.
- routes.json (trạng thái là MOCK, cần đối chiếu ở bước 0.2):
  Metro 1 Bến Thành – Suối Tiên (đã khai thác), Metro 2 Bến Thành – Tham Lương (đang thi công),
  tuyến Metro kéo dài Suối Tiên – Bình Dương/Biên Hòa (quy hoạch),
  Vành đai 3 (đang thi công / khai thác từng đoạn), Vành đai 4 (quy hoạch),
  Cao tốc TP.HCM – Long Thành – Dầu Giây (đã khai thác), Cao tốc Biên Hòa – Vũng Tàu (đang thi công),
  QL1, QL13, QL51. Polyline gần đúng thực tế, 15–40 điểm mỗi tuyến, kèm `expected_year`, `color_hex`.
- nodes.json: các ga Metro 1, nút giao Vành đai 3 chính, điểm cao tốc gần các dự án, POI Sân bay Long Thành (`diem_hat_nhan`).
- Khoảng cách tới ga/nút giao gần nhất tính bằng đường chim bay (CLLocation.distance) trong mock repository. UI ghi rõ "Đường chim bay".
- notifications.json: 8 thông báo mẫu thuộc 3 loại.

# 6. Design system — Liquid Glass
## Nguyên tắc
- Hai lớp rõ ràng. Content layer (map, ghim, tuyến, nội dung card) mang màu. Glass layer (tab bar, toolbar, search, chip, nút nổi, sheet) trung tính và nổi trên content.
- Không glass-on-glass. Card nằm trong sheet dùng nền đặc nhẹ, không dùng kính.
- Không gắn glass cho ghim trên map. Ghim là content: hình tròn màu đặc, viền trắng 2pt, shadow.
- Mỗi màn chỉ 1 nút `.glassProminent` có tint `brandPrimary`. Còn lại dùng `.glass` không tint.
- Các nhóm control đặt cạnh nhau phải bọc trong `GlassEffectContainer` (iOS 26) để kính hòa vào nhau và morph. Fallback: HStack thường.

## Token màu (Colors.swift + Asset Catalog, Light/Dark + High Contrast)
brandPrimary #0D9488 / #2DD4BF · brandAccent #FF5A3C / #FF7A5C (KHÔNG dùng làm tint kính)
statusOpen #10B981 / #34D399 · statusSoon #F59E0B / #FBBF24 · statusClosed #94A3B8 / #64748B · statusBuilding #6366F1 / #818CF8
routeRing #F97316 · routeExpressway #A855F7 · routeMetro1 #EF4444 · routeMetro2 #3B82F6 · routeMetroExt #22C55E · routeNational #64748B
Quy hoạch = nét đứt opacity 0.5 · Đang thi công = nét liền 3pt · Đã khai thác = nét liền 5pt
Nền màn không có map: MeshGradient 3×3 (iOS 18+; iOS 17 dùng LinearGradient), light #CCFBF1 / #F0FDFA / #FFE4DC, dark #042F2E / #0B1120 / #3B1A12, chuyển động chậm (chu kỳ ~20s), tắt khi Reduce Motion.

## Modifier bọc kính (điểm duy nhất trong codebase biết về iOS 26)
```swift
enum GlassStyle { case regular, tinted(Color), interactive }

struct AdaptiveGlass<S: Shape>: ViewModifier {
    let style: GlassStyle
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemBackground), in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        switch style {
        case .regular: .regular
        case .tinted(let c): .regular.tint(c)
        case .interactive: .regular.interactive()
        }
    }
}

extension View {
    func adaptiveGlass<S: Shape>(_ style: GlassStyle = .regular, in shape: S = Capsule()) -> some View {
        modifier(AdaptiveGlass(style: style, shape: shape))
    }
}
```

## Áp dụng theo màn hình
- TabView: tab bar kính mặc định của iOS 26, thêm `.tabBarMinimizeBehavior(.onScrollDown)` ở tab Theo dõi (bọc #available).
- Map: search bar nổi = capsule glass. Nút "Gần tôi" và "Chú giải" = cụm nút glass tròn dọc bên phải. Hàng chip layer bọc GlassEffectContainer, chip đang chọn dùng `.tinted(brandPrimary.opacity(0.6))`, kèm glassEffectID để chip morph khi bật/tắt.
- Sheet chi tiết dự án: dùng sheet mặc định (iOS 26 tự là kính ở detent thấp, chuyển đặc khi .large). KHÔNG tự set presentationBackground.
- Trong sheet: MetricTile, khối "Kết nối giao thông" dùng nền đặc `.secondarySystemBackground` bo 20pt. "Bật thông báo" = glassProminent tint brandPrimary. "Lưu" = glass.
- Tab Theo dõi / Tài khoản: nền MeshGradient. Card dự án dùng kính `.regular`. Card "Kiểm tra điều kiện" dùng `.tinted(brandPrimary)`.
- Wizard điều kiện: thanh progress và nút Tiếp/Quay lại dùng kính, lựa chọn đáp án dùng card nền đặc.
- Banner "NOXH không có suất ngoại giao": nền đặc brandAccent 12% + icon brandAccent, KHÔNG dùng kính.

## Typography & motion
SF Pro, số liệu `.monospacedDigit()` semibold. Icon SF Symbols.
Spring khi mở sheet. glassEffectID morph cho chip và nút. `.symbolEffect(.bounce)` khi bấm Lưu. `.sensoryFeedback(.success)` khi bật thông báo. Pulse cho ghim "Đang nhận hồ sơ". Có skeleton `.redacted(reason: .placeholder)` khi loading.

# 7. Màn hình
## Tab 1 — Bản đồ
- Map style `.standard(pointsOfInterest: .including([.school, .university, .hospital, .airport, .publicTransport, .store, .foodMarket, .park]))` — tiện ích quanh dự án, chỉ hiển thị, không chọn được (2026-11-08; trước đó `.excludingAll`).
- Search bar nổi (tìm theo tên dự án, phường/xã, cả tên mới lẫn tên cũ) + nút "Gần tôi" (mock vị trí).
- Segmented đổi vùng: TP.HCM / Bình Dương / Đồng Nai.
- Hàng chip cuộn ngang: Metro · Vành đai · Cao tốc · Quốc lộ · Tất cả NOXH · Đã lưu, kèm chip lọc nhanh "Đang nhận hồ sơ".
- Nút Chú giải mở sheet giải thích màu/kiểu nét theo trạng thái và năm dự kiến.
- Ghim màu theo trạng thái, gom cụm đơn giản theo lưới khi zoom out (badge số).
- Bấm ghim mở sheet chi tiết `.presentationDetents([.height(200), .medium, .large])`:
  tên, địa chỉ, badge trạng thái; grid 2×2 (Giá tham khảo, Số căn, Pháp lý, Khung nhận hồ sơ + countdown "Còn N ngày");
  "Kết nối giao thông" (ga Metro, nút giao Vành đai/Cao tốc gần nhất + khoảng cách + năm khai thác; dự án ở Đồng Nai hiện thêm khoảng cách tới Sân bay Long Thành);
  dòng "Nguồn: … · Cập nhật: dd/MM/yyyy" + nút "Báo thông tin sai" (form ghi chú, mock gửi);
  nút "Lưu" và "Bật thông báo" (yêu cầu đăng nhập, xem mục 8);
  banner cố định "NOXH không có suất ngoại giao — cẩn trọng lời mời mua suất".

## Tab 2 — Theo dõi
- Chưa đăng nhập: SignInPromptView gồm 3 lợi ích + nút Apple / Google / Facebook (mock).
- Đã đăng nhập: danh sách card dự án đã lưu, sắp theo hạn nộp gần nhất, có progress thời gian còn lại.
- Chế độ "So sánh": chọn 2–3 dự án → bảng so sánh giá, khoảng cách tới ga, trạng thái, highlight giá trị tốt nhất.
- Segment "Thông báo": inbox, icon/màu theo notification_types.

## Tab 3 — Tài khoản
- Header profile + trạng thái xác thực SĐT.
- Card "Kiểm tra điều kiện mua NOXH" → wizard 5 bước có progress: Đối tượng → Nhà ở hiện tại → Thu nhập → Hôn nhân → Nơi làm việc. Các lựa chọn lấy từ lookup.
- Kết quả 3 mức: "Có thể đủ điều kiện" / "Cần kiểm tra thêm" / "Chưa đủ", kèm điều khoản dẫn chiếu, câu miễn trừ "Kết quả chỉ để tham khảo, cơ quan có thẩm quyền xét duyệt mới là căn cứ cuối cùng", và dòng "Câu trả lời không được lưu lên máy chủ".
- Grouped List: Cài đặt thông báo, Quy tắc cộng đồng, Chính sách quyền riêng tư, Điều khoản, Đăng xuất, "Xóa tài khoản" (đỏ, confirmationDialog 2 bước).

# 8. Guest mode
- Khách được xem bản đồ, bật/tắt lớp, xem chi tiết.
- Bấm Lưu / Bật thông báo / layer "Đã lưu" / tab Theo dõi khi chưa đăng nhập: hiện sheet yêu cầu đăng nhập. Riêng Lưu thì khách vẫn được lưu tạm trên máy; khi đăng nhập, danh sách tạm được gộp vào tài khoản (mock merge).

# 9. Ngoài scope (không làm)
Bình luận/ảnh cộng đồng, push notification thật, đăng nhập thật, quảng cáo/tin rao.
Đánh dấu các điểm nối backend sau này bằng `// TODO(backend):`.

# 10. Đầu ra
1. Cây thư mục đầy đủ.
2. Toàn bộ file .swift và .json, không viết tắt kiểu "// ... tương tự".
3. Unit test cho EligibilityEvaluator và mapper.
4. README ngắn: cách chạy, cách thay Mock*Repository bằng implementation thật trong AppContainer, danh sách TODO(backend).

# 11. Thứ tự thực hiện (mỗi bước build/test xong mới qua bước sau)
1. Scaffold project + app rỗng chạy được trên Simulator.
2. Domain (model, protocol, RepositoryError).
3. Lookup + mock JSON, DTO, mapper, Mock*Repository, AppContainer + unit test.
4. DesignSystem (token, Glass.swift, component) + #Preview light/dark.
5. Feature Map → 6. Tracking → 7. Eligibility (+ test) → 8. Account.
9. Kiểm tra Reduce Transparency, Dark mode, Dynamic Type lớn, nhánh fallback trên Simulator iOS 17/18.
````
