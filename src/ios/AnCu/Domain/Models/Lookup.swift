import Foundation

// MARK: - Danh mục dùng chung (lookup)
//
// Enum chỉ giữ `code` (khóa ổn định, khớp DB). Nhãn, màu, icon, thứ tự lấy từ `LookupCatalog`
// để đổi từ server mà không cần phát hành app.
// Mỗi enum có `.unknown`: mapper trả về case này khi server thêm code mới mà app cũ chưa biết,
// thay vì làm hỏng cả lần decode.

enum LookupCategory: String, CaseIterable, Sendable {
    case projectStatus = "project_statuses"
    case legalStatus = "legal_statuses"
    case routeType = "route_types"
    case routeStatus = "route_statuses"
    case nodeType = "node_types"
    case serviceArea = "service_areas"
    case eligibilitySubject = "eligibility_subjects"
    case housingCondition = "housing_conditions"
    case notificationType = "notification_types"
    case placeKind = "place_kinds"
    case placeIcon = "place_icons"
}

protocol LookupCode: RawRepresentable<String>, CaseIterable, Hashable, Sendable {
    static var category: LookupCategory { get }
    static var unknown: Self { get }
}

extension LookupCode {
    /// Map code từ backend; code lạ → `.unknown`.
    init(code: String) {
        self = Self(rawValue: code) ?? .unknown
    }
}

enum ProjectStatus: String, LookupCode {
    case upcoming = "sap_mo"
    case acceptingApplications = "nhan_ho_so"
    case closed = "da_dong"
    case underConstruction = "dang_xay"
    case unknown
    static let category = LookupCategory.projectStatus
}

enum LegalStatus: String, LookupCode {
    case investmentApproved = "chu_truong_dau_tu"
    case buildingPermit = "da_co_giay_phep_xd"
    case eligibleForSale = "du_dieu_kien_ban"
    case handedOver = "da_ban_giao"
    case unknown
    static let category = LookupCategory.legalStatus
}

enum RouteType: String, LookupCode {
    case metro
    case ringRoad = "vanh_dai"
    case expressway = "cao_toc"
    case nationalHighway = "quoc_lo"
    case unknown
    static let category = LookupCategory.routeType
}

enum RouteStatus: String, LookupCode {
    case planned = "quy_hoach"
    case underConstruction = "dang_thi_cong"
    case operational = "da_khai_thac"
    case unknown
    static let category = LookupCategory.routeStatus
}

enum NodeType: String, LookupCode {
    case metroStation = "ga_metro"
    case interchange = "nut_giao"
    case keyLandmark = "diem_hat_nhan"
    case unknown
    static let category = LookupCategory.nodeType
}

/// Vùng phục vụ theo địa giới MỚI (sau sáp nhập 1/7/2025): TP.HCM + 4 tỉnh giáp ranh (data-strategy.md, 2026-11-08).
/// Mã cũ (`…Old`) vẫn còn trong danh mục (`in_mvp = false`, `merged_into`) để đọc dữ liệu/lịch sử cũ — không còn là chip.
enum ServiceArea: String, LookupCode {
    /// TP.HCM cũ + Bình Dương cũ + Bà Rịa – Vũng Tàu cũ.
    case hcm = "tp_hcm"
    /// Đồng Nai cũ + Bình Phước cũ.
    case dongNai = "dong_nai"
    /// Tây Ninh cũ + Long An cũ.
    case tayNinh = "tay_ninh"
    /// Đồng Tháp cũ + Tiền Giang cũ.
    case dongThap = "dong_thap"
    /// Lâm Đồng cũ + Đắk Nông cũ + Bình Thuận cũ.
    case lamDong = "lam_dong"
    /// Chưa phục vụ (in_mvp = false) — tìm kiếm hiện "Sắp có".
    case haNoi = "ha_noi"
    // Mã cũ đã gộp
    case hcmOld = "hcm_cu"
    case binhDuongOld = "binh_duong_cu"
    case dongNaiOld = "dong_nai_cu"
    case baRiaVungTauOld = "ba_ria_vung_tau_cu"
    case binhPhuocOld = "binh_phuoc_cu"
    case unknown
    static let category = LookupCategory.serviceArea
}

enum EligibilitySubject: String, LookupCode {
    case urbanLowIncome = "thu_nhap_thap_do_thi"
    case industrialWorker = "cong_nhan"
    case civilServant = "can_bo_cong_chuc"
    case armedForces = "luc_luong_vu_trang"
    case poorHousehold = "ho_ngheo_can_ngheo"
    /// Có từ 2 con đẻ trở lên (Luật Nhà ở 2023 Điều 76 khoản 13, bổ sung bởi Luật Dân số 2025, từ 01/07/2026).
    case multipleChildren = "nhieu_con"
    case other = "khac"
    case unknown
    static let category = LookupCategory.eligibilitySubject
}

enum HousingCondition: String, LookupCode {
    case noHouse = "chua_co_nha"
    case under15SqmPerPerson = "nha_duoi_15m2_nguoi"
    case ownsHouse = "da_co_nha"
    case unknown
    static let category = LookupCategory.housingCondition
}

enum NotificationType: String, LookupCode {
    case applicationsOpened = "mo_nhan_ho_so"
    case priceChanged = "doi_gia"
    case statusChanged = "doi_trang_thai"
    case unknown
    static let category = LookupCategory.notificationType
}

// MARK: - Catalog

struct LookupItem: Hashable, Sendable {
    let code: String
    let label: String
    let sortOrder: Int
    /// Hex dạng "#RRGGBB". Domain không biết SwiftUI.Color — DesignSystem tự chuyển.
    let colorHex: String?
    let symbolName: String?
    /// Thuộc tính riêng theo danh mục: `line_style` (route_statuses), `new_province`, `in_mvp` (service_areas)…
    let attributes: [String: String]
    let center: GeoPoint?

    init(
        code: String,
        label: String,
        sortOrder: Int,
        colorHex: String? = nil,
        symbolName: String? = nil,
        attributes: [String: String] = [:],
        center: GeoPoint? = nil
    ) {
        self.code = code
        self.label = label
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.attributes = attributes
        self.center = center
    }
}

struct LookupCatalog: Sendable {
    private let storage: [LookupCategory: [String: LookupItem]]

    init(items: [LookupCategory: [LookupItem]]) {
        storage = items.mapValues { list in
            Dictionary(list.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    static let empty = LookupCatalog(items: [:])

    func item<C: LookupCode>(for code: C) -> LookupItem? {
        storage[C.category]?[code.rawValue]
    }

    /// Nhãn hiển thị; thiếu trong catalog thì trả về code để UI không bao giờ trống.
    func label<C: LookupCode>(for code: C) -> String {
        item(for: code)?.label ?? code.rawValue
    }

    /// SF Symbol của một icon địa điểm (mã `place_icons`). Mã lạ / `nil` → `nil` (caller dùng icon theo loại).
    func placeIconSymbol(_ code: String?) -> String? {
        guard let code else { return nil }
        return storage[.placeIcon]?[code]?.symbolName
    }

    func items(in category: LookupCategory) -> [LookupItem] {
        (storage[category]?.values).map { $0.sorted { $0.sortOrder < $1.sortOrder } } ?? []
    }

    /// Các case có trong catalog, theo `sort_order`. Bỏ `.unknown`. Dùng cho chip lọc, lựa chọn wizard.
    func orderedCases<C: LookupCode>(_ type: C.Type) -> [C] {
        items(in: C.category).compactMap { C(rawValue: $0.code) }.filter { $0 != .unknown }
    }

    func isInMVP(_ area: ServiceArea) -> Bool {
        item(for: area)?.attributes["in_mvp"] == "true"
    }
}
